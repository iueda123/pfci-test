#!/usr/bin/env bash
# 未到達のstageを1つずつ進めます。判定は scripts/doctor.sh と同じstage定義を使います。
# コマンドの実行と値の書き込みは、毎回確認してから行います。既定はいずれも「実行しない」です。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=quick
ROUTE=''
ALL=0
GITHUB_APP_FLOW=0

usage() {
  cat <<'USAGE'
使い方: scripts/setup.sh [--all] [--route app|local|cloud] [--offline] [--github-app]

  （引数なし） 未到達のstageを1つだけ進めます
  --all       進められなくなるまで繰り返します
  --route     routeの自動推定を上書きします
  --offline   network到達確認を行いません
  --github-app  Edge用GitHub AppのPEM生成・install案内を再表示します
                必要ならsecret再登録とfinalize-report deployも続けて実行します
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1 ;;
    --offline) MODE=offline ;;
    --github-app) GITHUB_APP_FLOW=1 ;;
    --route) ROUTE="${2:-}"; shift ;;
    --route=*) ROUTE="${1#--route=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

. "$ROOT/scripts/setup/stages.sh"

load_dotenv "$ROOT/.env" DOTENV
load_dotenv "$ROOT/supabase/.env" DOTENV_SERVER
load_env_metadata "$ROOT/.env.example"
load_env_metadata "$ROOT/supabase/.env.example"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  BOLD=''; DIM=''; OFF=''
fi
interactive=1
[ -t 0 ] || interactive=0

ask() {
  local prompt="$1" answer
  read -r -p "$prompt" answer || return 1
  printf '%s' "$answer"
}

confirm() {
  local answer
  answer="$(ask "$1 [y/N] ")" || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --- route ---------------------------------------------------------------------

choose_route() {
  local answer
  printf '%sどのルートで進めますか。%s\n' "$BOLD" "$OFF"
  printf '  1) app    ローカル保存のみ。Supabaseを用意せず、仕組みだけ見ます\n'
  printf '  2) local  Supabase localスタック。Dockerが必要です\n'
  printf '  3) cloud  Supabase cloud project。本番相当です\n'
  answer="$(ask '番号 [1] ')" || return 1
  case "$answer" in
    2) ROUTE=local ;;
    3) ROUTE=cloud ;;
    *) ROUTE=app ;;
  esac
  printf 'route=%s で進めます。あとから --route で変更できます。\n\n' "$ROUTE"
}

if [ -z "$ROUTE" ]; then
  ROUTE="$(detect_route)"
  if [ "$ROUTE" = app ] && [ "$interactive" = 1 ]; then
    choose_route || exit 1
  fi
fi
case "$ROUTE" in
  app|local|cloud) ;;
  *) echo "route は app / local / cloud のいずれかです: $ROUTE" >&2; exit 2 ;;
esac

# --- .env への書き込み ----------------------------------------------------------

quote_value() {
  case "$1" in
    *[!A-Za-z0-9_./:@-]*) printf "'%s'" "${1//\'/\'\\\'\'}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# 既存の行を保ちながら1変数だけ差し替えます。ファイルは常に 600 で作ります。
env_upsert() {
  local file="$1" name="$2" value="$3" line found=0 tmp
  tmp="$file.setup.$$"
  ( umask 077; : > "$tmp" )
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" == "$name="* ]]; then
        printf '%s=%s\n' "$name" "$(quote_value "$value")" >> "$tmp"
        found=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$file"
  fi
  [ "$found" = 1 ] || printf '%s=%s\n' "$name" "$(quote_value "$value")" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

seed_env_file() {
  local file="$1" template="$2"
  [ -f "$file" ] && return 0
  ( umask 077; cp "$template" "$file" )
  chmod 600 "$file"
  printf '%s を %s から作りました（0600）。\n' "${file#"$ROOT"/}" "${template#"$ROOT"/}"
}

# 他の変数から一意に決まる値は、入力させずに提案します。
suggest_value() {
  local name="$1" scope="${2:-client}" api
  case "$name" in
    DISPATCHER_ENDPOINT)
      api="$(file_value REPORT_API_URL)"
      [ -n "$api" ] && printf '%s/functions/v1/dispatcher-control' "$(origin_of "$api")"
      return 0
      ;;
  esac
  # 反対側に同名の値があるなら、それに合わせます（DISPATCHER_TOKEN は完全一致が条件）。
  paired_value "$name" "$scope" || return 0
}

# 提案値の出どころ。@secret は値を出せないので、代わりにこの説明を表示します。
suggest_origin() {
  local name="$1" scope="${2:-client}"
  case "$name" in
    DISPATCHER_ENDPOINT) printf 'REPORT_API_URL から導出' ;;
    *) case "$scope" in
         server) printf 'ルート .env の %s と同じ値' "$name" ;;
         *)      printf 'supabase/.env の %s と同じ値' "$name" ;;
       esac ;;
  esac
}

WROTE_ENV_FILE=0
# .env にある値をこの実行へ読み込んだだけの状態。プロセスが終われば失われるので、
# 「進んだ」とは数えず、利用者のシェルでの source を促します。
LOADED_DOTENV=0
# シェルにfileと違う値が残っている状態。source し直すまで判定は変わりません。
SHELL_IS_STALE=0

# fileにある正しい値を、この実行の後続stageへ引き継ぎます。
# 利用者のシェルは書き換えられないので、食い違いはsourceで直してもらいます。
adopt_file_value() {
  local name="$1" scope="$2" value="$3"
  [ "$scope" = client ] || return 0
  { [ -n "$value" ] && ! is_placeholder "$value"; } || return 0
  [ "${!name:-}" = "$value" ] && return 0
  [ -n "${!name:-}" ] && SHELL_IS_STALE=1
  export "$name=$value"
  LOADED_DOTENV=1
}
# 尋ねたのに埋まらなかった必須の変数。これが残る限りstageは通りません。
PENDING_REQUIRED=()

# stageに属する変数だけを順に尋ねます。@secret は入力を画面に出しません。
configure_env_stage() {
  local target="$1" key name scope side file value current prompt attempts suggestion example slug filled changed=0 shown_side=''
  for key in "${ENV_KEYS[@]}"; do
    [ "${META_STAGE[$key]:-}" = "$target" ] || continue
    name="${META_NAME[$key]}"
    scope="${META_SCOPE[$key]}"
    side="${META_SIDE[$key]:-app}"
    # cloudのGitHub App認証はPEM pathから安全に登録する専用フローを使います。
    # base64化したprivate keyを対話入力やsupabase/.envへ保存しません。
    if [ "$target" = edge-secrets ] && [ "$ROUTE" = cloud ]; then
      case "$name" in GITHUB_APP_ID|GITHUB_APP_PRIVATE_KEY_BASE64) continue ;; esac
    fi
    # 尋ねるかどうかはfileの値で決めます。シェルに残った古い値で判断すると、
    # 保存しても状況が変わらず、同じ質問を繰り返すことになります。
    current="$(file_value "$name" "$scope")"

    # 任意の変数は尋ねませんが、.env にある値はこの実行の後続stageのために読み込みます。
    if [ "${META_REQUIRED[$key]}" != yes ]; then
      adopt_file_value "$name" "$scope" "$current"
      continue
    fi

    if [ "$scope" = server ]; then
      file="$ROOT/supabase/.env"; seed_env_file "$file" "$ROOT/supabase/.env.example"
    else
      file="$ROOT/.env"; seed_env_file "$file" "$ROOT/.env.example"
    fi
    suggestion="$(suggest_value "$name" "$scope")"
    # 形式が正しくても、他の変数から導ける値と食い違っていれば尋ね直します
    # （templateの既定値がlocal向けのまま cloud に残る、など）。
    if [ -n "$current" ] && ! is_placeholder "$current" \
       && { [ -z "${META_FORMAT[$key]:-}" ] || [[ "$current" =~ ${META_FORMAT[$key]} ]]; } \
       && { [ -z "$suggestion" ] || [ "$current" = "$suggestion" ]; }; then
      adopt_file_value "$name" "$scope" "$current"
      continue
    fi

    # 同じ名前の変数が両側にあるので、どちら向けの値をどのファイルに入れるのかを先に宣言します。
    if [ "$side" != "$shown_side" ]; then
      printf '\n%sここからは %sの値です。%s に保存します。%s\n' \
        "$BOLD" "$(env_side_label "$side")" "${file#"$ROOT"/}" "$OFF"
      if [ "$scope" = server ]; then
        if [ "$ROUTE" = cloud ]; then
          printf '  %sこのあと supabase secrets set --env-file supabase/.env で登録します。%s\n' "$DIM" "$OFF"
        else
          printf '  %ssupabase functions serve --env-file supabase/.env で渡します。%s\n' "$DIM" "$OFF"
        fi
      fi
      shown_side="$side"
    fi

    printf '\n%s%s%s  %s[%s → %s]%s\n' \
      "$BOLD" "$name" "$OFF" "$DIM" "$(env_side_tag "$side")" "${file#"$ROOT"/}" "$OFF"
    [ -n "${META_DESC[$key]:-}" ] && printf '  %s%s%s\n' "$DIM" "${META_DESC[$key]}" "$OFF"
    [ -n "${META_DOC[$key]:-}" ] && printf '  %s→ %s%s\n' "$DIM" "${META_DOC[$key]}" "$OFF"
    if [ -n "$current" ] && ! is_placeholder "$current"; then
      if [ "${META_SECRET[$key]}" = yes ]; then
        printf '  %s現在: 設定済み（値は表示しません）%s\n' "$DIM" "$OFF"
      else
        printf '  %s現在: %s%s\n' "$DIM" "$current" "$OFF"
      fi
    fi

    example="$(env_example "$key")"
    if [ -n "$suggestion" ]; then
      if [ "${META_SECRET[$key]}" = yes ]; then
        # secretの提案値は表示できないので、出どころだけを伝えます。
        printf '  %s推奨: %s%s\n' "$DIM" "$(suggest_origin "$name" "$scope")" "$OFF"
      else
        printf '  %s推奨: %s%s\n' "$DIM" "$suggestion" "$OFF"
      fi
    elif [ -n "$example" ]; then
      printf '  %s例: %s%s\n' "$DIM" "$example" "$OFF"
    fi

    # ここに来る変数はすべて @required で、いまの値は使えません。
    # 空Enterは「据え置き」ではなく「未入力のまま」なので、そう言います。
    filled=0
    attempts=0
    while [ "$attempts" -lt 3 ]; do
      attempts=$(( attempts + 1 ))
      if [ "${META_SECRET[$key]}" = yes ]; then
        if [ -n "$suggestion" ]; then
          prompt='  値（表示されません。空Enterで推奨値を採用）: '
        else
          prompt='  値（表示されません。必須です）: '
        fi
        read -rs -p "$prompt" value || return 1
        printf '\n'
        [ -z "$value" ] && [ -n "$suggestion" ] && value="$suggestion"
      elif [ -n "$suggestion" ]; then
        prompt='  値（空Enterで推奨値を採用）: '
        read -r -p "$prompt" value || return 1
        [ -z "$value" ] && value="$suggestion"
      else
        prompt='  値（必須です）: '
        read -r -p "$prompt" value || return 1
      fi
      if [ -z "$value" ]; then
        printf '  %s✖ 未入力です。この値が無いと %s は通りません。%s\n' "$DIM" "$target" "$OFF"
        break
      fi
      # cloneのURLを貼ってしまいがちなので、owner/repo に直してから検査します。
      if [ "$name" = GITHUB_REPOSITORY ]; then
        slug="$(github_repo_slug "$value" || true)"
        if [ -n "$slug" ] && [ "$slug" != "$value" ]; then
          printf '  %sowner/repo の形に直しました: %s%s\n' "$DIM" "$slug" "$OFF"
          value="$slug"
        fi
      fi
      if [ -n "${META_FORMAT[$key]:-}" ] && ! [[ "$value" =~ ${META_FORMAT[$key]} ]]; then
        printf '  ✖ 形式が一致しません。期待する形式: %s\n' "${META_FORMAT[$key]}"
        # 正規表現だけでは何を書けばよいか伝わりません。拒否した瞬間こそ例が要ります。
        [ -n "$example" ] && printf '    例: %s\n' "$example"
        continue
      fi
      if [ "$name" = SUPABASE_PUBLISHABLE_KEY ] && looks_like_service_role "$value"; then
        printf '  ✖ secret/service-role相当の鍵です。デスクトップアプリには配布できません。\n'
        printf '    → docs/setup-env.md#26-鍵の種類を見分ける\n'
        continue
      fi
      # 形式が合っていても、cloneが無ければdispatcherは動きません。その場で気づけるようにします。
      if [ "$name" = DISPATCHER_REPOSITORY ] && [ ! -d "$value" ]; then
        printf '  ✖ そのpathはありません。GITHUB_REPOSITORY のcloneの絶対pathを入れてください。\n'
        continue
      fi
      env_upsert "$file" "$name" "$value"
      if [ "$scope" = server ]; then DOTENV_SERVER["$name"]="$value"; else DOTENV["$name"]="$value"; export "$name=$value"; fi
      changed=1
      filled=1
      WROTE_ENV_FILE=1
      printf '  保存しました: %s\n' "${file#"$ROOT"/}"
      break
    done
    if [ "$filled" = 0 ]; then
      PENDING_REQUIRED+=("$name")
      printf '  %s%s に %s= を直接書いてもかまいません（0600のまま）。%s\n' \
        "$DIM" "${file#"$ROOT"/}" "$name" "$OFF"
    fi
  done
  return $(( 1 - changed ))
}

configure_edge_github_app() {
  local mode="${1:-required}" app_id private_key repository
  local -a command
  printf '\n%sEdge用GitHub Appの認証を設定します。%s\n' "$BOLD" "$OFF"
  printf '  %sApp IDとPEMのpathだけを入力します。private keyの内容は表示・保存しません。%s\n' "$DIM" "$OFF"
  printf '\n  PEMをまだ取得していない場合:\n'
  printf '    1. GitHub右上のアイコン → Settings → Developer settings → GitHub Apps\n'
  printf '    2. このPoCのEdge用App（pfci-edge-*）を開く\n'
  printf '    3. General画面の「Private keys」まで下へ移動\n'
  printf '    4. 「Generate a private key」を押す\n'
  printf '    5. ダウンロードされた .pem を保護された場所へ移動する\n'
  printf '  %sorganization所有のAppはorganization Settingsから開きます。dispatcher用AppのPEMと間違えないでください。%s\n\n' "$DIM" "$OFF"
  repository="$(file_value GITHUB_REPOSITORY server)"
  printf '  Edge用Appを対象repositoryへinstallする必要があります:\n'
  printf '    1. Edge用App設定画面の左sidebar → Install App\n'
  printf '    2. repository所有者の行で「Install」を押す\n'
  printf '    3. 「Only select repositories」を選ぶ\n'
  printf '    4. %s を選択して「Install」\n' "${repository:-supabase/.envのGITHUB_REPOSITORY}"
  printf '  %sorganizationのポリシーによっては管理者の承認が必要です。%s\n\n' "$DIM" "$OFF"
  confirm '  Edge用Appを上記repositoryへinstallしましたか?' || {
    printf '  install後にsetup.shをもう一度実行してください。\n'
    return 1
  }
  if [ "$mode" = optional ] && ! confirm '  GitHub App認証secretも再登録しますか?'; then
    printf '  install案内のみ確認しました。既存secretは変更していません。\n'
    return 0
  fi
  app_id="$(ask '  GitHub App ID: ')" || return 1
  private_key="$(ask '  private key PEMの絶対path: ')" || return 1
  if ! [[ "$app_id" =~ ^[0-9]+$ ]]; then
    printf '  ✖ App IDは数値です。\n' >&2
    return 1
  fi
  if [ -z "$private_key" ] || [ ! -r "$private_key" ]; then
    printf '  ✖ PEMファイルを読み取れません。\n' >&2
    printf '    GitHub AppのGeneral → Private keys → Generate a private keyで取得し、\n' >&2
    printf '    ダウンロード先を含む絶対pathを指定してください。\n' >&2
    return 1
  fi
  command=("$ROOT/scripts/configure-edge-github-app.sh" --app-id "$app_id" --private-key "$private_key" --server-env "$ROOT/supabase/.env")
  if [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
    command+=(--project-ref "$SUPABASE_PROJECT_REF")
  fi
  confirm '  必要な4 secretを登録し、finalize-reportをdeployしますか?' || {
    printf '  実行しませんでした。\n'
    return 1
  }
  "${command[@]}"
}

# 全stage到達後も、dispatcherを起動する前に目視確認すべき値は残ります。
# secretは値を表示せず、Supabase側のsecret値は取得できないことも明示します。
print_dispatcher_settings() {
  local github_repository dispatcher_repository dispatcher_endpoint dispatcher_scratch codex_bin claude_bin
  github_repository="$(file_value GITHUB_REPOSITORY server)"
  dispatcher_repository="$(env_value DISPATCHER_REPOSITORY)"
  dispatcher_endpoint="$(env_value DISPATCHER_ENDPOINT)"
  dispatcher_scratch="$(env_value DISPATCHER_SCRATCH)"
  codex_bin="$(env_value CODEX_BIN)"
  claude_bin="$(env_value CLAUDE_BIN)"

  printf '\n%s§1.7 dispatcher設定（目視確認）%s\n' "$BOLD" "$OFF"
  if [ -n "$github_repository" ] && ! is_placeholder "$github_repository"; then
    printf '  GITHUB_REPOSITORY=%q  %s(supabase/.envの登録元)%s\n' "$github_repository" "$DIM" "$OFF"
  else
    printf '  GITHUB_REPOSITORY=(supabase/.envの登録元にはありません。Edge登録値は取得できません)\n'
  fi
  printf '  DISPATCHER_REPOSITORY=%q\n' "$dispatcher_repository"
  printf '  DISPATCHER_ENDPOINT=%q\n' "$dispatcher_endpoint"
  if [ "$(env_state DISPATCHER_TOKEN)" != unset ]; then
    printf '  DISPATCHER_TOKEN=(設定済み。secretのため値は表示しません)\n'
  else
    printf '  DISPATCHER_TOKEN=(未設定)\n'
  fi
  if [ -n "$dispatcher_scratch" ]; then
    printf '  DISPATCHER_SCRATCH=%q\n' "$dispatcher_scratch"
  else
    printf '  DISPATCHER_SCRATCH=%q  %s(未設定時の既定値)%s\n' \
      "$(dispatcher_scratch_default)" "$DIM" "$OFF"
  fi
  if [ -n "$codex_bin" ]; then
    printf '  CODEX_BIN=%q\n' "$codex_bin"
  else
    printf '  CODEX_BIN=codex  %s(未設定時の既定値)%s\n' "$DIM" "$OFF"
  fi
  if [ -n "$claude_bin" ]; then
    printf '  CLAUDE_BIN=%q\n' "$claude_bin"
  else
    printf '  CLAUDE_BIN=claude  %s(未設定時の既定値)%s\n' "$DIM" "$OFF"
  fi
  printf '  %sSupabaseに登録済みのsecretは値を取得できないため、上記GITHUB_REPOSITORYは登録元の値です。%s\n' \
    "$DIM" "$OFF"
}

# --- コマンドの実行 --------------------------------------------------------------

# 「次の1手」は、実行できるコマンドとは限りません（資料の参照や、値を埋める必要のある雛形）。
# 先頭の VAR=value を読み飛ばしたうえで、実体のあるコマンドのときだけ実行を提案します。
is_runnable() {
  local token
  for token in $1; do
    case "$token" in
      [A-Za-z_]*=*) continue ;;
      ./*|scripts/*) return 0 ;;
      *) command -v "$token" >/dev/null 2>&1; return $? ;;
    esac
  done
  return 1
}

run_command() {
  local command="$1"
  case "$command" in
    *'<'*|*'owner/repo'*)
      printf '\n次のコマンドを、山かっこの部分を埋めて実行してください。\n  %s\n' "$command"
      return 1
      ;;
  esac
  if ! is_runnable "$command"; then
    printf '\n次の手順を実施してください。\n  %s\n' "$command"
    return 1
  fi
  printf '\n実行するコマンド:\n  %s\n' "$command"
  confirm '実行しますか?' || { printf ' 実行しませんでした。\n'; return 1; }
  ( cd "$ROOT" && bash -c "$command" )
}

# --- 1 stageを進める --------------------------------------------------------------

advance() {
  local id status line acted=1
  for id in "${STAGE_IDS[@]}"; do
    status=0
    # checkが起動する子processに、ウィザードへの入力を横取りさせません。
    evaluate_stage "$id" < /dev/null || status=$?
    [ "$status" = 1 ] || continue

    printf '%s未到達: %s — %s%s\n' "$BOLD" "$id" "${STAGE_TITLE[$id]}" "$OFF"
    if [ "${#STAGE_DETAILS[@]}" -gt 0 ]; then
      for line in "${STAGE_DETAILS[@]}"; do
        printf '  %s%s%s\n' "$DIM" "$line" "$OFF"
      done
    fi
    printf '  %s詳細 → %s%s\n' "$DIM" "${STAGE_DOC[$id]}" "$OFF"

    if [ "$interactive" = 0 ]; then
      printf '\n次の1手:\n  %s\n' "${STAGE_HINT:-${STAGE_NEXT[$id]}}"
      return 1
    fi

    case "$id" in
      env-app|dispatcher-env)
        configure_env_stage "${id}" && acted=0
        if [ "$WROTE_ENV_FILE" = 1 ] || [ "$LOADED_DOTENV" = 1 ]; then
          if [ "$WROTE_ENV_FILE" = 0 ] && [ "$SHELL_IS_STALE" = 1 ]; then
            printf '\n%s.env の値は揃っています。古いのはこのシェルの環境変数だけです。%s\n' "$BOLD" "$OFF"
          else
            printf '\n%s.env は自動では読まれません。あなたのシェルで次を実行してください。%s\n' "$BOLD" "$OFF"
          fi
          printf '  set -a; source .env; set +a\n'
          printf '  ./scripts/setup.sh\n'
          # sourceは利用者のシェルでしか効かないので、ここで再判定しても未到達のままです。
          NEEDS_SOURCE=1
        fi
        ;;
      edge-secrets)
        configure_env_stage edge-secrets && acted=0
        if [ "$ROUTE" = cloud ]; then
          if [ "${#PENDING_REQUIRED[@]}" -eq 0 ]; then
            acted=0
            configure_edge_github_app required || acted=1
          fi
        fi
        ;;
      *)
        run_command "${STAGE_HINT:-${STAGE_NEXT[$id]}}" && acted=0
        ;;
    esac

    LAST_STAGE="$id"
    # 実行しただけでは進んだとは限りません（コマンドが成功しても判定が変わらないことがあります）。
    # 同じ手を何度も勧めないよう、その場で測り直します。
    STAGE_STILL_FAILING=0
    if [ "${#PENDING_REQUIRED[@]}" -gt 0 ]; then
      : # 未入力の必須値は再判定するまでもありません。呼び出し側が報告します。
    elif [ "$acted" = 0 ] && [ "$NEEDS_SOURCE" = 0 ]; then
      status=0
      evaluate_stage "$id" < /dev/null || status=$?
      if [ "$status" = 1 ]; then
        STAGE_STILL_FAILING=1
        printf '\n%s%s は実行後もまだ未到達です。%s\n' "$BOLD" "$id" "$OFF"
        for line in "${STAGE_DETAILS[@]}"; do
          printf '  %s%s%s\n' "$DIM" "$line" "$OFF"
        done
        printf '  %s詳細 → %s%s\n' "$DIM" "${STAGE_DOC[$id]}" "$OFF"
      fi
    fi
    return "$acted"
  done
  return 2
}

# --- 実行 -------------------------------------------------------------------------

printf '%s継続的改善PoC — セットアップ%s  %s(route=%s)%s\n\n' "$BOLD" "$OFF" "$DIM" "$ROUTE" "$OFF"

if [ "$GITHUB_APP_FLOW" = 1 ]; then
  if [ "$ROUTE" != cloud ]; then
    printf '%s--github-appはcloud route専用です。--route cloudを指定してください。%s\n' "$BOLD" "$OFF" >&2
    exit 2
  fi
  if [ "$interactive" != 1 ]; then
    printf '%s--github-appは対話端末で実行してください。%s\n' "$BOLD" "$OFF" >&2
    exit 2
  fi
  configure_edge_github_app optional
  exit $?
fi

LAST_STAGE=''
previous=''
NEEDS_SOURCE=0
STAGE_STILL_FAILING=0
while true; do
  result=0
  advance || result=$?
  if [ "$result" != 2 ] && [ "${#PENDING_REQUIRED[@]}" -gt 0 ]; then
    # 入力を促したのに埋まらなかった値。sourceでもコマンドでも解消しません。
    printf '\n%s未入力の必須の値があるため、ここで止まります: %s%s\n' "$BOLD" "${PENDING_REQUIRED[*]}" "$OFF"
    printf '値を用意してから scripts/setup.sh をもう一度実行してください。\n'
    exit 1
  fi
  case "$result" in
    2)
      printf '\n未到達のstageはありません。全体を見るには scripts/doctor.sh を実行してください。\n'
      if [ "$ROUTE" = cloud ]; then
        print_dispatcher_settings
        printf '\nIssue作成からdraft PRまで対話で進めるには次を実行してください。\n'
        printf '  scripts/dispatcher-wizard.sh\n'
        if [ "$interactive" = 1 ] && confirm 'いまdispatcher wizardへ進みますか?'; then
          "$ROOT/scripts/dispatcher-wizard.sh"
          exit $?
        fi
        printf 'GitHub AppのPEM生成・install案内を再表示するには次を実行してください。\n'
        printf '  scripts/setup.sh --route cloud --github-app\n'
      fi
      exit 0
      ;;
    1)
      if [ "$LOADED_DOTENV" = 1 ] && [ "$WROTE_ENV_FILE" = 0 ]; then
        # このスクリプトはあなたのシェルの環境変数を変えられません。sourceは自分で実行してもらいます。
        printf '\n値は .env にあります。上のsourceを実行してから、もう一度実行してください。\n'
      else
        printf '\nここで止まります。解消したら scripts/setup.sh をもう一度実行してください。\n'
      fi
      exit 1
      ;;
  esac
  if [ "$STAGE_STILL_FAILING" = 1 ]; then
    printf '\n同じ操作を繰り返しても変わりません。上の詳細と資料を確認してください。\n'
    printf '全体を見るには scripts/doctor.sh を実行してください。\n'
    exit 1
  fi
  if [ "$ALL" = 0 ]; then
    printf '\n1つ進めました。続きは scripts/setup.sh をもう一度実行してください。\n'
    exit 0
  fi
  if [ "$LAST_STAGE" = "$previous" ]; then
    printf '\n%s は解消していません。ここで止まります。\n' "$LAST_STAGE"
    exit 1
  fi
  previous="$LAST_STAGE"
  printf '\n'
done
