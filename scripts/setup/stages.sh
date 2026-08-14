# Stage registry for scripts/doctor.sh. Sourced, never executed directly.
#
# Every stage declares metadata plus a check_<id> function that returns:
#   0 = 到達済み   1 = 未到達   2 = このrouteでは不要   3 = 未検査
# Checks report through detail()/hint() and must not print to stdout themselves,
# and must never print the value of a @secret variable.

STAGE_IDS=()
declare -A STAGE_TITLE=() STAGE_ROUTES=() STAGE_TIER=() STAGE_DOC=() STAGE_NEXT=()

stage() {
  STAGE_IDS+=("$1")
  STAGE_TITLE["$1"]="$2"
  STAGE_ROUTES["$1"]="$3"
  STAGE_TIER["$1"]="$4"
  STAGE_DOC["$1"]="$5"
  STAGE_NEXT["$1"]="$6"
}

STAGE_DETAILS=()
STAGE_HINT=''
detail() { STAGE_DETAILS+=("$1"); }
hint() { STAGE_HINT="$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- .env / .env.example ------------------------------------------------------

# 同じ変数名がclient側とserver側の両方に存在する（DISPATCHER_TOKEN）ため、metadataは scope|NAME で持ちます。
declare -A DOTENV=() DOTENV_SERVER=()
declare -A META_NAME=() META_SCOPE=() META_SIDE=() META_STAGE=() META_REQUIRED=() META_SECRET=() META_FORMAT=() META_DOC=() META_DESC=() META_EXAMPLE=()
ENV_KEYS=()

load_dotenv() {
  local file="$1" target="$2" line key value
  local -n store="$target"
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line#export }"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    store["$key"]="$value"
  done < "$file"
}

# Parses the "# @..." metadata blocks so .env.example stays the single source of truth.
load_env_metadata() {
  local file="$1" pending='' description='' line token name key scope side
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      '# @'*) pending="${line#\# }"; description='' ;;
      '#'*) if [ -n "$pending" ]; then description="${description:+$description }${line#\# }"; fi ;;
      '') ;;
      *)
        name="${line%%=*}"
        if [ -n "$pending" ] && [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          # @scope は誰が読むか（app / dispatcher / server）。fileの振り分けは client / server の2つです。
          side=app
          for token in $pending; do
            case "$token" in @scope=*) side="${token#@scope=}" ;; esac
          done
          case "$side" in server) scope=server ;; *) scope=client ;; esac
          key="$scope|$name"
          ENV_KEYS+=("$key")
          META_NAME["$key"]="$name"
          META_SCOPE["$key"]="$scope"
          META_SIDE["$key"]="$side"
          META_DESC["$key"]="$description"
          META_REQUIRED["$key"]=no
          META_SECRET["$key"]=no
          for token in $pending; do
            case "$token" in
              @stage=*)  META_STAGE["$key"]="${token#@stage=}" ;;
              @format=*) META_FORMAT["$key"]="${token#@format=}" ;;
              @example=*) META_EXAMPLE["$key"]="${token#@example=}" ;;
              @doc=*)    META_DOC["$key"]="${token#@doc=}" ;;
              @required) META_REQUIRED["$key"]=yes ;;
              @secret)   META_SECRET["$key"]=yes ;;
            esac
          done
        fi
        pending=''
        ;;
    esac
  done < "$file"
}

# client: shell = 起動プロセスに設定済み / dotenv = .env にはあるがシェル未設定 / unset = どこにもない
# server: file = supabase/.env にある / unset。Edge secretsは操作者のシェルからは読みません。
env_state() {
  local name="$1" scope="${2:-client}"
  if [ "$scope" = server ]; then
    [ -n "${DOTENV_SERVER[$name]:-}" ] && echo file || echo unset
    return 0
  fi
  if [ -n "${!name:-}" ]; then echo shell
  elif [ -n "${DOTENV[$name]:-}" ]; then echo dotenv
  else echo unset
  fi
}

env_value() {
  local name="$1" scope="${2:-client}"
  if [ "$scope" = server ]; then printf '%s' "${DOTENV_SERVER[$name]:-}"; return 0; fi
  if [ -n "${!name:-}" ]; then printf '%s' "${!name}"; else printf '%s' "${DOTENV[$name]:-}"; fi
}

# fileに書かれている値だけを見ます。ウィザードが書き換えるのはfileなので、
# 「もう一度尋ねるかどうか」はシェルの状態ではなくこちらで判断します
# （古い値をexportしたままのシェルで、同じ質問が延々と繰り返されるのを防ぎます）。
file_value() {
  local name="$1" scope="${2:-client}"
  if [ "$scope" = server ]; then printf '%s' "${DOTENV_SERVER[$name]:-}"; else printf '%s' "${DOTENV[$name]:-}"; fi
}

# 同じ変数名がclient側とserver側の両方にある（DISPATCHER_TOKEN）ため、
# 値を尋ねるときも報告するときも「どちら向けの値か」を必ず添えます。
env_side_tag() {
  case "$1" in
    server)     printf 'Edge secret' ;;
    dispatcher) printf 'dispatcher' ;;
    *)          printf 'アプリ' ;;
  esac
}

env_side_label() {
  case "$1" in
    server)     printf 'Edge Functions（server側）' ;;
    dispatcher) printf 'dispatcher（client側）' ;;
    *)          printf 'JavaFXアプリ（client側）' ;;
  esac
}

env_scope_file() {
  case "$1" in
    server) printf 'supabase/.env' ;;
    *)      printf '.env' ;;
  esac
}

# 同名の変数が反対側にもあるなら、その値を返します（両者は完全一致させる必要があります）。
paired_value() {
  local name="$1" scope="$2" other value
  case "$scope" in server) other=client ;; *) other=server ;; esac
  [ -n "${META_NAME["$other|$name"]:-}" ] || return 1
  value="$(file_value "$name" "$other")"
  { [ -n "$value" ] && ! is_placeholder "$value"; } || return 1
  printf '%s' "$value"
}

# 期待する値の実例。@example がその変数の一次情報で、machine毎に変わるものだけここで作ります。
dispatcher_scratch_default() {
  printf '%s/Documents/continuous-improvement' "$HOME"
}

env_example() {
  local key="$1"
  if [ -n "${META_EXAMPLE[$key]:-}" ]; then printf '%s' "${META_EXAMPLE[$key]}"; return 0; fi
  case "${META_NAME[$key]:-}" in
    DISPATCHER_REPOSITORY) printf '%s/pfci-private' "$HOME" ;;
    DISPATCHER_SCRATCH) dispatcher_scratch_default ;;
  esac
}

# cloneのURLを貼られても owner/repo に直します。すでにその形ならそのまま返します。
github_repo_slug() {
  local value="${1%.git}" repo rest owner
  value="${value%/}"
  value="${value#*://}"
  value="${value#*@}"
  value="${value#*:}"
  repo="${value##*/}"; rest="${value%/*}"; owner="${rest##*/}"
  { [ -n "$owner" ] && [ -n "$repo" ] && [ "$owner" != "$repo" ]; } || return 1
  printf '%s/%s' "$owner" "$repo"
}

# http(s)://host:port の部分だけを取り出します。
origin_of() {
  local url="${1%%/functions/*}"
  printf '%s' "${url%/}"
}

# Placeholder values from the template must not count as configured.
# 形式は正しいのに中身がtemplateのまま、という値もここで弾きます
# （owner/private-repository は @format=^[^/]+/[^/]+$ を満たしてしまいます）。
is_placeholder() {
  case "$1" in
    replace-*|*'/absolute/path/'*|*PROJECT_REF*) return 0 ;;
    owner/*|local-publishable-key) return 0 ;;
    *) return 1 ;;
  esac
}

# Detects a secret/service-role key that was pasted where a publishable key belongs.
looks_like_service_role() {
  local value="$1" payload
  case "$value" in
    sb_secret_*) return 0 ;;
    eyJ*)
      payload="${value#*.}"; payload="${payload%%.*}"
      payload="$(printf '%s' "$payload" | tr '_-' '/+')"
      while [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="${payload}="; done
      printf '%s' "$payload" | base64 -d 2>/dev/null | grep -q 'service_role' && return 0
      ;;
  esac
  return 1
}

# Generic check driven purely by .env.example metadata.
check_env_stage() {
  local target="$1" key name scope state value status=0 missing=0 shown label example
  for key in "${ENV_KEYS[@]}"; do
    [ "${META_STAGE[$key]:-}" = "$target" ] || continue
    name="${META_NAME[$key]}"
    scope="${META_SCOPE[$key]}"
    # 同名の変数が両側にあるため、名前だけでは足りません。
    label="$name [$(env_side_tag "${META_SIDE[$key]:-app}") → $(env_scope_file "$scope")]"
    state="$(env_state "$name" "$scope")"
    value="$(env_value "$name" "$scope")"
    if [ "$state" != unset ] && is_placeholder "$value"; then
      detail "$label: templateのままです（未設定として扱います）"
      state=unset
    fi
    if [ "${META_SECRET[$key]}" = yes ]; then shown='(値は表示しません)'; else shown="$value"; fi
    case "$state" in
      shell|file)
        detail "$label: 設定済み ${shown}"
        if [ -n "${META_FORMAT[$key]:-}" ] && ! [[ "$value" =~ ${META_FORMAT[$key]} ]]; then
          detail "  ✖ 形式が不正です。期待する形式: ${META_FORMAT[$key]}"
          example="$(env_example "$key")"
          if [ -n "$example" ]; then detail "  例: $example"; fi
          if [ -n "${META_DOC[$key]:-}" ]; then detail "  → ${META_DOC[$key]}"; fi
          hint "$(env_scope_file "$scope") の $name を修正してください${example:+（例: $example）}"
          status=1
        fi
        ;;
      dotenv)
        detail "$label: .env にはありますが、このシェルには未設定です"
        missing=1
        ;;
      unset)
        if [ "${META_REQUIRED[$key]}" = yes ]; then
          detail "$label: 未設定（必須）"
          example="$(env_example "$key")"
          if [ -n "$example" ]; then detail "  例: $example"; fi
          if [ -n "${META_DOC[$key]:-}" ]; then detail "  → ${META_DOC[$key]}"; fi
          hint "$(env_scope_file "$scope") に $name を設定してください${example:+（例: $example）}"
          status=1
        else
          detail "$label: 未設定（任意。既定値で動きます）"
        fi
        ;;
    esac
  done
  if [ "$missing" = 1 ]; then
    detail '.env は自動では読まれません。値はprocessの環境変数として渡します'
    hint 'set -a; source .env; set +a'
    status=1
  fi
  return "$status"
}

# doctor.sh と setup.sh が共有する評価の入口。STAGE_DETAILS と STAGE_HINT を埋めて状態を返します。
evaluate_stage() {
  local id="$1" status=0
  STAGE_DETAILS=(); STAGE_HINT=''
  if [[ " ${STAGE_ROUTES[$id]} " != *" $ROUTE "* ]]; then
    STAGE_DETAILS=("route=$ROUTE では不要です")
    return 2
  fi
  if [ "${STAGE_TIER[$id]}" = network ] && [ "$MODE" = offline ]; then
    STAGE_DETAILS=('未検査（--offline）')
    return 3
  fi
  "check_${id//-/_}" || status=$?
  return "$status"
}

# 環境変数の状態からrouteを推定します。保存された進捗には依存しません。
detect_route() {
  local api
  api="$(env_value REPORT_API_URL)"
  case "$api" in
    '') echo app ;;
    *127.0.0.1*|*localhost*) echo local ;;
    *) echo cloud ;;
  esac
}

# --- stage definitions --------------------------------------------------------

stage jdk 'JDK 25 toolchain' 'app local cloud' quick \
  'docs/setup-app.md#jdk-25の確認' './gradlew --version'
check_jdk() {
  local candidate version dist
  for candidate in "${JAVA_HOME:+$JAVA_HOME/bin/java}" "$(command -v java || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] || continue
    version="$("$candidate" -version 2>&1 | head -1)"
    case "$version" in
      *'"25'*) detail "$version"; return 0 ;;
    esac
  done
  dist="${GRADLE_USER_HOME:-$HOME/.gradle}/wrapper/dists"
  if [ ! -d "$dist" ]; then
    detail 'Gradle Wrapperのdistributionが未取得のため、toolchain検出まで確認できていません'
    hint './gradlew --version   # 初回はGradle 9.6.1を取得します'
    return 3
  fi
  if "$ROOT/gradlew" -q javaToolchains 2>/dev/null | grep -qE 'JDK 25([^0-9]|$)'; then
    detail 'Gradleがtoolchainとして JDK 25 を検出しています'
    return 0
  fi
  detail 'JDK 25 が見つかりません（PATH上のjava、JAVA_HOME、Gradleのtoolchain検出のいずれにも無し）'
  hint 'docs/setup-app.md の 1.1 方法A / 方法B'
  return 1
}

stage build 'build と test' 'app local cloud' full \
  'docs/setup-app.md#12-最初のbuildと検証' './gradlew test build'
check_build() {
  local module missing=0
  if [ "$MODE" = full ]; then
    detail './gradlew test build を実行中...'
    if "$ROOT/gradlew" test build >/dev/null 2>&1; then
      detail 'test と build が成功しました'
      return 0
    fi
    detail 'test または build が失敗しました。出力を見るには手で実行してください'
    return 1
  fi
  for module in app core dispatcher; do
    compgen -G "$ROOT/$module/build/libs/*.jar" >/dev/null || missing=1
  done
  if [ "$missing" = 1 ]; then
    detail 'build成果物がありません'
    return 1
  fi
  detail '前回のbuild成果物があります（実走で確かめるには --full）'
  return 0
}

stage smoke 'headless capture' 'app local cloud' full \
  'docs/setup-app.md#16-画面なしで動作確認するheadless--ci' 'APP_SMOKE_TEST=true xvfb-run -a ./gradlew :app:run'
check_smoke() {
  local output runner=()
  if [ "$MODE" != full ]; then
    detail '未検査（--full で実行します）'
    return 3
  fi
  if have xvfb-run; then runner=(xvfb-run -a)
  elif [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    detail 'xvfb-run が無く、DISPLAYもありません'
    return 3
  fi
  output="$(cd "$ROOT" && APP_SMOKE_TEST=true "${runner[@]}" ./gradlew -q :app:run 2>&1 | grep -m1 SMOKE_CAPTURE_OK || true)"
  if [ -n "$output" ]; then detail "$output"; return 0; fi
  detail 'SMOKE_CAPTURE_OK が出力されませんでした'
  return 1
}

stage local-bundle 'ローカルbundleの作成実績' 'app local cloud' quick \
  'docs/setup-app.md#14-画面の操作とそのとき起きること' './gradlew :app:run'
check_local_bundle() {
  local dir count=0 found
  for dir in "$(env_value REPORT_OUTPUT_DIR)" local-reports app/local-reports; do
    [ -n "$dir" ] || continue
    [ -d "$ROOT/$dir" ] || continue
    found="$(find "$ROOT/$dir" -maxdepth 2 -name manifest.json 2>/dev/null | wc -l)"
    count=$(( count + found ))
  done
  if [ "$count" -gt 0 ]; then
    detail "bundle: ${count}件（rawを含むため共有しないでください）"
    return 0
  fi
  detail 'bundleがまだ1件もありません'
  return 1
}

stage supabase-cli 'Supabase CLI' 'local cloud' quick \
  'docs/setup-supabase.md#cliを入れるubuntu' 'scripts/install-supabase-cli.sh'
check_supabase_cli() {
  if have supabase; then
    detail "supabase $(supabase --version 2>/dev/null | head -1)"
    return 0
  fi
  detail 'supabase コマンドがありません'
  detail 'versionはGitHubの最新releaseから解決されます（引数で固定もできます）'
  return 1
}

stage supabase-login 'CLIの認証' 'cloud' quick \
  'docs/setup-supabase.md#cliを入れるubuntu' 'supabase login'
check_supabase_login() {
  local output
  have supabase || { detail 'supabase コマンドがありません'; return 1; }
  if [ -n "${SUPABASE_ACCESS_TOKEN:-}" ]; then
    detail 'SUPABASE_ACCESS_TOKEN が設定されています'
    return 0
  fi
  if [ -s "$HOME/.supabase/access-token" ]; then
    detail '~/.supabase/access-token があります'
    return 0
  fi
  # 新しいCLIはOSのkeyringへ保存するため、fileが無くても認証済みのことがあります。
  # そこは実際にAPIを叩いて確かめます。
  [ "$MODE" != offline ] || { detail '未検査（--offline）'; return 3; }
  output="$(cd "$ROOT" && supabase projects list 2>&1 </dev/null || true)"
  case "$output" in
    *'Access token not provided'*|*'not logged in'*)
      detail 'CLIがSupabaseアカウントと紐づいていません'
      detail 'ブラウザが開けない環境では Dashboard > Account > Access Tokens で発行した値を'
      detail 'supabase login --token <値> で渡します'
      hint 'supabase login'
      return 1
      ;;
    '')
      detail 'projectを取得できましたが、1件もありません（認証は通っています）'
      return 0
      ;;
  esac
  if printf '%s' "$output" | grep -qi 'error\|failed'; then
    detail "認証状態を判定できませんでした: $(printf '%s' "$output" | head -1)"
    return 3
  fi
  detail '認証済みです'
  return 0
}

stage supabase-link 'cloud projectとのlink' 'cloud' quick \
  'docs/setup-supabase.md#手順1-projectを作る' 'supabase link --project-ref <project-ref>'
check_supabase_link() {
  local ref
  if [ -f "$ROOT/supabase/.temp/project-ref" ]; then
    ref="$(cat "$ROOT/supabase/.temp/project-ref" 2>/dev/null || true)"
    detail "link済み: ${ref:-(project-refを読めません)}"
    return 0
  fi
  detail 'cloud projectとlinkしていません（先にDashboardでprojectを作ってください）'
  return 1
}

stage supabase-local 'localスタックの起動' 'local' quick \
  'docs/setup-supabase.md#32-ルートa-localで動かす' 'supabase start'
check_supabase_local() {
  have supabase || { detail 'supabase コマンドがありません'; return 1; }
  if (cd "$ROOT" && supabase status >/dev/null 2>&1); then
    detail 'localスタックが起動しています'
    return 0
  fi
  detail 'localスタックが起動していません（dockerの権限も確認してください）'
  return 1
}

stage env-app 'アプリの送信設定' 'local cloud' quick \
  'docs/setup-env.md#javafxアプリが読む変数' 'set -a; source .env; set +a'
check_env_app() {
  local status=0 key
  if [ "$ROUTE" = app ]; then
    detail '最短ルート（ローカル保存のみ）のため不要です'
    detail '送信を有効にするには REPORT_API_URL と SUPABASE_PUBLISHABLE_KEY を設定します'
    return 2
  fi
  check_env_stage env-app || status=1
  key="$(env_value SUPABASE_PUBLISHABLE_KEY)"
  if [ -n "$key" ] && looks_like_service_role "$key"; then
    detail '  ✖ SUPABASE_PUBLISHABLE_KEY にsecret/service-role相当の鍵が設定されています'
    detail '  → この鍵はデスクトップアプリに配布してはいけません。直ちに失効させてください'
    detail '  → docs/setup-env.md#26-鍵の種類を見分ける'
    hint '漏れた鍵をSupabaseで失効させ、sb_publishable_ 形式の鍵に置き換えてください'
    status=1
  fi
  return "$status"
}

stage functions 'Edge Functionsの配置' 'local cloud' network \
  'docs/setup-supabase.md#手順3-migrationとfunctionsを配置する' 'SUPABASE_PROJECT_REF=<ref> scripts/deploy-supabase.sh'
check_functions() {
  local url code
  url="$(env_value REPORT_API_URL)"
  [ -n "$url" ] || { detail 'REPORT_API_URL が未設定のため確認できません'; return 3; }
  [ "$MODE" != offline ] || { detail '未検査（--offline）'; return 3; }
  url="${url%/}"
  code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' -X OPTIONS "$url/functions/v1/create-report" 2>/dev/null || echo 000)"
  case "$code" in
    200) detail "create-report: HTTP $code（配置済み）"; return 0 ;;
    000) detail "$url へ到達できません"; hint_deploy_functions; return 1 ;;
    404) detail "create-report: HTTP $code（未配置）"; hint_deploy_functions; return 1 ;;
    *)   detail "create-report: HTTP $code（想定外。3.6 エラーコード早見表を参照）"; return 1 ;;
  esac
}

# link済みならproject-refが分かるので、そのまま実行できる形で提示します。
hint_deploy_functions() {
  local ref
  if [ "$ROUTE" = local ]; then
    hint 'supabase functions serve --env-file supabase/.env'
    return 0
  fi
  ref="$(cat "$ROOT/supabase/.temp/project-ref" 2>/dev/null || true)"
  [ -n "$ref" ] && hint "SUPABASE_PROJECT_REF=$ref scripts/deploy-supabase.sh"
}

# supabase secrets list の出力形式はCLIの版と端末の有無で変わります
# （非ttyではJSON、ttyでは罫線つきのテーブル）。名前だけを両方から拾います。
secret_listed() {
  local name="$1" listed="$2"
  grep -qE "\"name\"[[:space:]]*:[[:space:]]*\"${name}\"" <<<"$listed" && return 0
  grep -qE "(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|$)" <<<"$listed"
}

stage edge-secrets 'Edge secrets' 'local cloud' quick \
  'docs/setup-supabase.md#手順5-edge-secretsを設定する' 'supabase secrets set --env-file supabase/.env'
check_edge_secrets() {
  local listed name missing=()
  if [ "$ROUTE" = local ]; then
    if [ ! -f "$ROOT/supabase/.env" ]; then
      detail 'supabase/.env がありません（supabase functions serve --env-file で渡す値です）'
      hint 'cp supabase/.env.example supabase/.env'
      return 1
    fi
    check_env_stage edge-secrets
    return $?
  fi
  # cloudでは値はSupabase側にあり、ここからは読めません。名前が登録されているかだけを確認します。
  have supabase || { detail 'supabase コマンドがありません'; return 1; }
  [ "$MODE" != offline ] || { detail '未検査（--offline）'; return 3; }
  listed="$(cd "$ROOT" && supabase secrets list 2>/dev/null || true)"
  [ -n "$listed" ] || { detail 'secretsを取得できません（supabase link と認証を確認してください）'; return 3; }
  for name in GITHUB_APP_ID GITHUB_APP_PRIVATE_KEY_BASE64 GITHUB_REPOSITORY DISPATCHER_TOKEN; do
    secret_listed "$name" "$listed" || missing+=("$name")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    detail "Edge secretとして未登録（値は supabase/.env に入れて登録します）: ${missing[*]}"
    return 1
  fi
  detail '必要な4つのsecretが登録されています（値は取得していません）'
  # 登録済みの値はhashしか返らないので中身は見られません。代わりに、登録元になる
  # supabase/.env にtemplateのままの値が残っていないかを見ます。
  local key value stale=()
  for key in "${ENV_KEYS[@]}"; do
    [ "${META_STAGE[$key]:-}" = edge-secrets ] || continue
    [ "${META_SCOPE[$key]}" = server ] || continue
    [ "${META_REQUIRED[$key]}" = yes ] || continue
    name="${META_NAME[$key]}"
    # cloudのGitHub App認証値は専用スクリプトが直接Supabaseへ登録し、
    # private keyをsupabase/.envへ残さないため、登録名の確認だけで十分です。
    if [ "$name" = GITHUB_APP_ID ] || [ "$name" = GITHUB_APP_PRIVATE_KEY_BASE64 ]; then
      continue
    fi
    value="${DOTENV_SERVER[$name]:-}"
    if is_placeholder "$value"; then
      stale+=("$name（templateのまま）")
    elif [ -n "${META_FORMAT[$key]:-}" ] && ! [[ "$value" =~ ${META_FORMAT[$key]} ]]; then
      stale+=("$name（形式が不正。例: $(env_example "$key")）")
    fi
  done
  if [ ${#stale[@]} -gt 0 ]; then
    detail "supabase/.env の値が使えません: ${stale[*]}"
    detail '  登録済みの値はhashしか返らないため、登録元のこのファイルで判定しています'
    hint 'supabase/.env を直してから supabase secrets set --env-file supabase/.env をやり直してください'
    return 1
  fi
  return 0
}

stage storage-private 'Storageがprivate' 'local cloud' network \
  'docs/setup-supabase.md#34-疎通確認' 'supabase db push'
check_storage_private() {
  local url code
  url="$(env_value REPORT_API_URL)"
  [ -n "$url" ] || { detail 'REPORT_API_URL が未設定のため確認できません'; return 3; }
  [ "$MODE" != offline ] || { detail '未検査（--offline）'; return 3; }
  url="${url%/}"
  code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' \
    "$url/storage/v1/object/public/user-reports/reports/x/raw/screenshot.png" 2>/dev/null || echo 000)"
  if [ "$code" = 200 ]; then
    detail 'bucketの中身がpublicに読めています。migrationの適用状態を確認してください'
    return 1
  fi
  [ "$code" = 000 ] && { detail "$url へ到達できません"; return 1; }
  detail "public取得: HTTP $code（読めないことを確認）"
  return 0
}

stage github 'GitHubのlabelと保護' 'cloud' network \
  'docs/setup-supabase.md#手順6-repositoryのlabelとbranch保護' 'GITHUB_REPOSITORY=<owner/repo> scripts/configure-github.sh'
check_github() {
  local repo labels repo_info default_branch visibility protection
  local strict contexts enforce_admins approvals dismiss_stale allow_force_pushes allow_deletions
  have gh || { detail 'gh コマンドがありません'; return 1; }
  # この変数はEdge secret（supabase/.env）側にあります。シェルに無くてもそちらを見ます。
  repo="$(env_value GITHUB_REPOSITORY)"
  [ -n "$repo" ] || repo="$(file_value GITHUB_REPOSITORY server)"
  [ -n "$repo" ] || { detail 'GITHUB_REPOSITORY が未設定のため確認できません'; return 3; }
  if is_placeholder "$repo" || ! [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    detail "GITHUB_REPOSITORY が owner/repo の形ではありません: $repo"
    detail "  例: $(env_example 'server|GITHUB_REPOSITORY')"
    hint 'supabase/.env の GITHUB_REPOSITORY を owner/repo に直してください（cloneのURLではありません）'
    return 1
  fi
  [ "$MODE" != offline ] || { detail '未検査（--offline）'; return 3; }
  gh auth status >/dev/null 2>&1 || { detail 'gh が未認証です'; hint 'gh auth login'; return 1; }
  labels="$(gh label list --repo "$repo" --limit 100 2>/dev/null || true)"
  [ -n "$labels" ] || { detail "$repo のlabelを取得できません"; return 1; }
  local name missing=()
  for name in user-report triage agent-ready agent:codex agent:claude agent-running needs-info agent-failed pr-opened; do
    grep -q "^${name}[[:space:]]" <<<"$labels" || missing+=("$name")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    detail "不足しているlabel: ${missing[*]}"
    return 1
  fi
  detail "$repo: 必要な9つのlabelが揃っています"

  repo_info="$(gh repo view "$repo" --json defaultBranchRef,visibility \
    --jq '[.defaultBranchRef.name, .visibility] | @tsv' 2>/dev/null || true)"
  if [ -z "$repo_info" ]; then
    detail "$repo のdefault branchを確認できません"
    hint 'repositoryの参照権限を確認してください'
    return 1
  fi
  IFS=$'\t' read -r default_branch visibility <<<"$repo_info"
  protection="$(gh api "repos/$repo/branches/$default_branch/protection" --jq \
    '[.required_status_checks.strict,
      (.required_status_checks.contexts | join(",")),
      .enforce_admins.enabled,
      .required_pull_request_reviews.required_approving_review_count,
      .required_pull_request_reviews.dismiss_stale_reviews,
      .allow_force_pushes.enabled,
      .allow_deletions.enabled] | @tsv' 2>/dev/null || true)"
  IFS=$'\t' read -r strict contexts enforce_admins approvals dismiss_stale allow_force_pushes allow_deletions \
    <<<"$protection"
  if [ "$strict" != true ] || [[ ",$contexts," != *",verify,"* ]] \
     || [ "$enforce_admins" != true ] || ! [[ "$approvals" =~ ^[1-9][0-9]*$ ]] \
     || [ "$dismiss_stale" != true ] || [ "$allow_force_pushes" != false ] \
     || [ "$allow_deletions" != false ]; then
    detail "default branch ($default_branch) の保護が未設定または要件不足です"
    detail '次に行うこと:'
    detail '  1. GitHubのrepositoryを開き、Settings → Collaborators and teamsで自分のRoleがAdminか確認してください'
    if [ "$visibility" = PRIVATE ]; then
      detail 'GitHub Freeを利用中の場合、private repositoryではbranch protectionを利用できません'
      detail '  2. Settings → Billing and plansでbranch protection対応プランか確認してください'
      detail '     GitHub Freeのままなら、公開して問題のないrepositoryだけpublicに変更する方法もあります'
    else
      detail '  2. Settings → Branchesでbranch protectionを変更できることを確認してください'
    fi
    detail '  3. 下に表示するコマンドで保護を設定してください'
    hint "GITHUB_REPOSITORY=$repo scripts/configure-github.sh"
    return 1
  fi
  detail "default branch ($default_branch): required check verify、承認1件、force-push／削除禁止を確認しました"
  return 0
}

stage dispatcher-env 'dispatcherの設定' 'local cloud' quick \
  'docs/setup-env.md#dispatcherが読む変数' 'scripts/run-dispatcher.sh'
check_dispatcher_env() {
  local status=0 endpoint api repo
  check_env_stage dispatcher-env || status=1
  # 形式（絶対path）だけでは足りません。worktreeの親になるcloneが実在する必要があります。
  repo="$(env_value DISPATCHER_REPOSITORY)"
  if [ -n "$repo" ] && ! is_placeholder "$repo"; then
    if [ ! -d "$repo" ]; then
      detail "  ✖ DISPATCHER_REPOSITORY のpathがありません: $repo"
      hint "GITHUB_REPOSITORY のcloneを作り、その絶対pathを DISPATCHER_REPOSITORY に設定してください"
      status=1
    elif [ ! -e "$repo/.git" ]; then
      detail "  ✖ DISPATCHER_REPOSITORY がgit repositoryではありません: $repo"
      hint "GITHUB_REPOSITORY のcloneの絶対pathを DISPATCHER_REPOSITORY に設定してください"
      status=1
    fi
  fi
  endpoint="$(env_value DISPATCHER_ENDPOINT)"
  api="$(env_value REPORT_API_URL)"
  # DISPATCHER_ENDPOINT は REPORT_API_URL と同じprojectを指す必要があります。
  # templateの既定値はlocal向けなので、cloudでそのまま残ると認証まで到達しません。
  if [ -n "$endpoint" ] && [ -n "$api" ]; then
    if [ "$(origin_of "$endpoint")" != "$(origin_of "$api")" ]; then
      detail "  ✖ DISPATCHER_ENDPOINT が REPORT_API_URL と別のhostを指しています"
      detail "     REPORT_API_URL: $(origin_of "$api")"
      detail "     DISPATCHER_ENDPOINT: $(origin_of "$endpoint")"
      hint "$(origin_of "$api")/functions/v1/dispatcher-control を DISPATCHER_ENDPOINT に設定してください"
      status=1
    fi
  fi
  return "$status"
}

stage dispatcher-auth 'dispatcher tokenの認証' 'local cloud' network \
  'docs/setup-supabase.md#34-疎通確認' 'ルートの .env と Edge secret の DISPATCHER_TOKEN が完全一致しているか確認してください'
check_dispatcher_auth() {
  local endpoint token wrong right recovered
  endpoint="$(env_value DISPATCHER_ENDPOINT)"
  token="$(env_value DISPATCHER_TOKEN)"
  { [ -n "$endpoint" ] && [ -n "$token" ] && ! is_placeholder "$token"; } || {
    detail 'DISPATCHER_ENDPOINT / DISPATCHER_TOKEN が未設定のため確認できません'; return 3; }
  [ "$MODE" != offline ] || { detail '未検査（--offline）'; return 3; }
  wrong="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' -X POST \
    -H 'authorization: Bearer wrong' -H 'content-type: application/json' \
    -d '{"action":"recoverStale"}' "$endpoint" 2>/dev/null || echo 000)"
  if [ "$wrong" != 401 ]; then
    detail "誤ったtokenが 401 以外を返しました: HTTP $wrong"
    return 1
  fi
  detail '誤ったtoken: HTTP 401（拒否を確認）'
  # unknown_action は認証を通ったあとに 400 を返すため、DBを変更せずに認証成功だけを確かめられます。
  right="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' -X POST \
    -H "authorization: Bearer $token" -H 'content-type: application/json' \
    -d '{"action":"doctorProbe"}' "$endpoint" 2>/dev/null || echo 000)"
  if [ "$right" != 400 ]; then
    detail "正しいtokenが 400 unknown_action 以外を返しました: HTTP $right"
    return 1
  fi
  detail '正しいtoken: HTTP 400 unknown_action（認証通過を確認）'
  if [ "$MODE" = full ]; then
    recovered="$(curl -sS -m 8 -X POST -H "authorization: Bearer $token" \
      -H 'content-type: application/json' -d '{"action":"recoverStale"}' "$endpoint" 2>/dev/null || true)"
    detail "recoverStale: ${recovered:-応答なし}（DB到達まで確認）"
    case "$recovered" in *'"recovered"'*) ;; *) return 1 ;; esac
  else
    detail 'DB到達まで確かめるには --full（recoverStale を実行します）'
  fi
  return 0
}
