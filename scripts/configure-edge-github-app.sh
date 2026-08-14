#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ID=''
PRIVATE_KEY_FILE=''
PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
SERVER_ENV=''
DEPLOY=1
SECRET_FILE=''

cleanup() {
  if [ -n "$SECRET_FILE" ] && [ -f "$SECRET_FILE" ]; then
    rm -f -- "$SECRET_FILE"
  fi
}
trap cleanup EXIT HUP INT TERM

usage() {
  cat <<'USAGE'
使い方:
  scripts/configure-edge-github-app.sh --app-id ID --private-key PATH [--project-ref REF] [--server-env PATH] [--no-deploy]

必須:
  --app-id       Edge用GitHub AppのApp ID（数値）
  --private-key  GitHubから取得したprivate key PEMのパス

省略可能:
  --project-ref  Supabase Project Reference ID
                 省略時はSUPABASE_PROJECT_REF、次にlink済みprojectを使用
  --server-env   GITHUB_REPOSITORYとDISPATCHER_TOKENを読むenvファイル
                 指定時はGitHub App認証と合わせて必要な4 secretを登録
  --no-deploy    secretsの登録だけ行い、finalize-reportをdeployしない

PEMとbase64値は標準出力、shell引数、リポジトリへ書きません。
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app-id) APP_ID="${2:-}"; shift ;;
    --app-id=*) APP_ID="${1#--app-id=}" ;;
    --private-key) PRIVATE_KEY_FILE="${2:-}"; shift ;;
    --private-key=*) PRIVATE_KEY_FILE="${1#--private-key=}" ;;
    --project-ref) PROJECT_REF="${2:-}"; shift ;;
    --project-ref=*) PROJECT_REF="${1#--project-ref=}" ;;
    --server-env) SERVER_ENV="${2:-}"; shift ;;
    --server-env=*) SERVER_ENV="${1#--server-env=}" ;;
    --no-deploy) DEPLOY=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数です: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ! [[ "$APP_ID" =~ ^[0-9]+$ ]]; then
  echo '--app-idにはGitHub Appの数値IDを指定してください。' >&2
  exit 2
fi
if [ -z "$PRIVATE_KEY_FILE" ] || [ ! -f "$PRIVATE_KEY_FILE" ] || [ ! -r "$PRIVATE_KEY_FILE" ]; then
  echo '--private-keyには読み取り可能なPEMファイルを指定してください。' >&2
  echo 'GitHub AppのGeneral → Private keys → Generate a private keyで取得できます。' >&2
  exit 2
fi
if ! grep -qE '^-----BEGIN (RSA )?PRIVATE KEY-----$' "$PRIVATE_KEY_FILE"; then
  echo '指定ファイルは対応するprivate key PEMではありません。' >&2
  exit 2
fi
if [ -z "$PROJECT_REF" ] && [ -r "$ROOT/supabase/.temp/project-ref" ]; then
  PROJECT_REF="$(sed -n '1p' "$ROOT/supabase/.temp/project-ref")"
fi
if ! [[ "$PROJECT_REF" =~ ^[a-z0-9]+$ ]]; then
  echo '--project-ref、SUPABASE_PROJECT_REF、またはlink済みprojectが必要です。' >&2
  exit 2
fi
command -v supabase >/dev/null || { echo 'supabase CLIが見つかりません。' >&2; exit 1; }
command -v base64 >/dev/null || { echo 'base64コマンドが見つかりません。' >&2; exit 1; }

env_value() {
  local file="$1" wanted="$2" line key value
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line#export }"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    [ "$key" = "$wanted" ] || continue
    value="${line#*=}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    printf '%s' "$value"
    return 0
  done <"$file"
  return 1
}

GITHUB_REPOSITORY_VALUE=''
DISPATCHER_TOKEN_VALUE=''
if [ -n "$SERVER_ENV" ]; then
  if [ ! -r "$SERVER_ENV" ]; then
    echo '--server-envを読み取れません。' >&2
    exit 2
  fi
  GITHUB_REPOSITORY_VALUE="$(env_value "$SERVER_ENV" GITHUB_REPOSITORY || true)"
  DISPATCHER_TOKEN_VALUE="$(env_value "$SERVER_ENV" DISPATCHER_TOKEN || true)"
  if ! [[ "$GITHUB_REPOSITORY_VALUE" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || [[ "$GITHUB_REPOSITORY_VALUE" == owner/* ]]; then
    echo '--server-envのGITHUB_REPOSITORYが未設定または不正です。' >&2
    exit 2
  fi
  if [ -z "$DISPATCHER_TOKEN_VALUE" ] || [[ "$DISPATCHER_TOKEN_VALUE" == replace-* ]]; then
    echo '--server-envのDISPATCHER_TOKENが未設定です。' >&2
    exit 2
  fi
fi

SECRET_FILE="$(mktemp /tmp/pfci-edge-github-secrets-XXXXXX)"
chmod 600 "$SECRET_FILE"
{
  printf 'GITHUB_APP_ID=%s\n' "$APP_ID"
  printf 'GITHUB_APP_PRIVATE_KEY_BASE64='
  base64 -w 0 -- "$PRIVATE_KEY_FILE"
  printf '\n'
  if [ -n "$SERVER_ENV" ]; then
    printf 'GITHUB_REPOSITORY=%s\n' "$GITHUB_REPOSITORY_VALUE"
    printf 'DISPATCHER_TOKEN=%s\n' "$DISPATCHER_TOKEN_VALUE"
  fi
} >"$SECRET_FILE"

echo "GitHub App認証secretsをSupabase project $PROJECT_REF へ登録します。"
supabase secrets set --env-file "$SECRET_FILE" --project-ref "$PROJECT_REF"

if [ "$DEPLOY" -eq 1 ]; then
  echo 'finalize-reportをdeployします。'
  supabase functions deploy finalize-report --project-ref "$PROJECT_REF"
fi

echo 'GitHub App認証の設定が完了しました。private keyとsecret値は表示していません。'
echo 'Edge用GitHub AppがGITHUB_REPOSITORYへinstall済みであることも確認してください。'
