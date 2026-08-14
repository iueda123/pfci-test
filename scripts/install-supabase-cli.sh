#!/usr/bin/env bash
# Supabase CLI を .deb で導入します。
# versionは、引数 > SUPABASE_CLI_VERSION > GitHubの最新release の順に決まります。
# 導入前にURLとSHA-256を表示し、確認してからsudoを実行します。
set -euo pipefail

DRY_RUN=0
VERSION=''
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
使い方: scripts/install-supabase-cli.sh [--dry-run] [version]

  version    例: 2.34.5（省略時はGitHubの最新releaseを参照します）
  --dry-run  取得先URLを表示するだけで、download も install もしません
USAGE
      exit 0
      ;;
    -*) echo "不明な引数: $1" >&2; exit 2 ;;
    *) VERSION="$1" ;;
  esac
  shift
done
VERSION="${VERSION:-${SUPABASE_CLI_VERSION:-}}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "$1 が必要です。" >&2; exit 1; }; }
need curl

if ! command -v dpkg >/dev/null 2>&1; then
  cat >&2 <<'MESSAGE'
dpkgが無いため、この方法では入れられません。
他のOSでの導入方法は https://github.com/supabase/cli の README を参照してください。
MESSAGE
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64) ;;
  *) echo ".debが配布されていないarchitectureです: $ARCH" >&2; exit 1 ;;
esac

if command -v supabase >/dev/null 2>&1; then
  echo "導入済み: $(supabase --version 2>/dev/null || echo '版を取得できません')"
fi

# 最新releaseのtagを解決します（tagは v2.34.5 の形式）。
if [ -z "$VERSION" ]; then
  echo 'GitHubの最新releaseを参照しています...'
  # grepを直接pipeで受けるとSIGPIPEでcurlが落ちるため、一度変数へ受けてから解析します。
  response="$(curl -fsSL --proto '=https' --tlsv1.2 \
    https://api.github.com/repos/supabase/cli/releases/latest || true)"
  tag="$(printf '%s' "$response" | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
  if [ -z "$tag" ]; then
    cat >&2 <<'MESSAGE'
最新releaseを解決できませんでした。versionを引数で指定してください。
  https://github.com/supabase/cli/releases で確認できます
  例: scripts/install-supabase-cli.sh 2.34.5
MESSAGE
    exit 1
  fi
  VERSION="${tag#v}"
fi
VERSION="${VERSION#v}"

ASSET="supabase_${VERSION}_linux_${ARCH}.deb"
URL="https://github.com/supabase/cli/releases/download/v${VERSION}/${ASSET}"

echo "version : $VERSION"
echo "asset   : $ASSET"
echo "url     : $URL"

if [ "$DRY_RUN" = 1 ]; then
  echo '--dry-run のため、ここで終了します。'
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fSL --proto '=https' --tlsv1.2 -o "$WORK/$ASSET" "$URL"

echo
echo "bytes   : $(stat -c '%s' "$WORK/$ASSET")"
echo "sha256  : $(sha256sum "$WORK/$ASSET" | cut -d' ' -f1)"
echo 'このSHA-256を、releaseページに掲載されている値と照合してください。'
echo

read -r -p "sudo dpkg -i で導入しますか? [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo '導入しませんでした。'; exit 1 ;;
esac

sudo dpkg -i "$WORK/$ASSET"
supabase --version
