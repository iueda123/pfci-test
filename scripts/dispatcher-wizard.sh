#!/usr/bin/env bash
# Issue作成後からdraft PRまでを、人間の承認を保ったまま対話で案内します。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTE=cloud
MODE=quick

usage() {
  cat <<'USAGE'
使い方: scripts/dispatcher-wizard.sh

  cloud routeで、接続診断 → Issue確認 → Agent選択 → dispatcher実行を対話で進めます。
  Issueの確認とagent-readyの付与は自動化しません。
USAGE
}

case "${1:-}" in
  '') ;;
  -h|--help) usage; exit 0 ;;
  *) echo "不明な引数: $1" >&2; usage >&2; exit 2 ;;
esac

if [ ! -t 0 ]; then
  echo 'dispatcher-wizard.shは対話端末で実行してください。' >&2
  exit 2
fi

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

# .envをshell codeとしてsourceせず、setupと同じparserで読んだ値だけをexportします。
load_client_environment() {
  local key name
  for key in "${ENV_KEYS[@]}"; do
    [ "${META_SCOPE[$key]:-}" = client ] || continue
    name="${META_NAME[$key]}"
    if [ -z "${!name:-}" ] && [ -n "${DOTENV[$name]:-}" ]; then
      export "$name=${DOTENV[$name]}"
    fi
  done
}

stop_with_retry() {
  printf '\n%sここで止まります。解消後、同じwizardを再実行してください。%s\n' "$BOLD" "$OFF"
  printf '  scripts/dispatcher-wizard.sh\n'
  exit 1
}

printf '%s継続的改善PoC — Issueからdraft PRまで%s\n\n' "$BOLD" "$OFF"

if [ ! -f "$ROOT/.env" ]; then
  echo '.envがありません。先に ./scripts/setup.sh --all --route cloud を実行してください。' >&2
  exit 1
fi
load_client_environment

printf '%s1. dispatcher設定を確認します%s\n' "$BOLD" "$OFF"
status=0
evaluate_stage dispatcher-env < /dev/null || status=$?
if [ "$status" != 0 ]; then
  for line in "${STAGE_DETAILS[@]}"; do printf '  %s\n' "$line"; done
  stop_with_retry
fi
printf '  ✓ 必須のdispatcher設定を読み込みました（secretの値は表示しません）。\n'

repository="$(env_value DISPATCHER_REPOSITORY)"
expected_repository="$(file_value GITHUB_REPOSITORY server)"
remote_url="$(git -C "$repository" remote get-url origin 2>/dev/null || true)"
remote_repository="$(github_repo_slug "$remote_url" 2>/dev/null || true)"
if [ -z "$expected_repository" ] || is_placeholder "$expected_repository"; then
  printf '  ✖ supabase/.envのGITHUB_REPOSITORYを確認できません。\n'
  stop_with_retry
fi
if [ "$remote_repository" != "$expected_repository" ]; then
  printf '  ✖ cloneのoriginが対象repositoryと一致しません。\n'
  printf '    期待: %s\n' "$expected_repository"
  printf '    実際: %s\n' "${remote_repository:-判定不能}"
  stop_with_retry
fi
printf '  ✓ cloneのorigin: %s\n' "$remote_repository"

scratch="$(env_value DISPATCHER_SCRATCH)"
[ -n "$scratch" ] || scratch="$(dispatcher_scratch_default)"
if [ ! -d "$scratch" ]; then
  printf '  dispatcherの作業directoryがまだありません: %q\n' "$scratch"
  if confirm '  作成しますか?'; then
    if ! mkdir -p -- "$scratch"; then
      printf '  ✖ 作成できません。.envのDISPATCHER_SCRATCHを、書き込み可能なrepository外のpathへ変更してください。\n'
      stop_with_retry
    fi
  else
    stop_with_retry
  fi
fi
if [ ! -w "$scratch" ]; then
  printf '  ✖ DISPATCHER_SCRATCHへ書き込めません: %q\n' "$scratch"
  printf '    .envで、現在のユーザーが書けるrepository外のpathへ変更してください。\n'
  stop_with_retry
fi
printf '  ✓ DISPATCHER_SCRATCHへ書き込めます。\n\n'

printf '%s2. GitHubとSupabaseへの接続を診断します%s\n' "$BOLD" "$OFF"
printf '  %s--fullはDB疎通のためrecoverStaleを実行し、45分以上放置されたrunをtimed_outに整理します。%s\n' "$DIM" "$OFF"
if confirm '  診断を実行しますか?'; then
  if ! "$ROOT/scripts/doctor.sh" --route cloud --only github,dispatcher-env,dispatcher-auth --full; then
    stop_with_retry
  fi
else
  stop_with_retry
fi

printf '\n%s3. 使用するAgentを確認します%s\n' "$BOLD" "$OFF"
printf '  1) Codex\n'
printf '  2) Claude\n'
agent_choice="$(ask '番号 [1] ')" || exit 1
case "$agent_choice" in
  2) agent=claude; agent_bin="$(env_value CLAUDE_BIN)"; [ -n "$agent_bin" ] || agent_bin=claude ;;
  *) agent=codex; agent_bin="$(env_value CODEX_BIN)"; [ -n "$agent_bin" ] || agent_bin=codex ;;
esac
if ! command -v gh >/dev/null 2>&1; then
  printf '  ✖ ghコマンドがありません。\n'
  stop_with_retry
fi
if ! command -v "$agent_bin" >/dev/null 2>&1; then
  printf '  ✖ Agent CLIが見つかりません: %q\n' "$agent_bin"
  stop_with_retry
fi
if confirm '  ghとAgent CLIのログイン状態を確認しますか?'; then
  gh auth status || stop_with_retry
  "$agent_bin" --version || stop_with_retry
else
  stop_with_retry
fi

printf '\n%s4. 処理するIssueを用意します%s\n' "$BOLD" "$OFF"
if ! confirm '  JavaFXアプリから送信済みのIssueがありますか?'; then
  printf '  previewを確認して報告を送信してください。アプリを閉じるとwizardへ戻ります。\n'
  if confirm '  いまアプリを起動しますか?'; then
    "$ROOT/scripts/smoke-test-report.sh" || stop_with_retry
  else
    printf '  次を実行してIssueを作成してください: scripts/smoke-test-report.sh\n'
    stop_with_retry
  fi
fi

cat <<'CHECKLIST'

  GitHubで対象Issueを開き、次を確認してください。
    1. 報告内容、期待動作、再現条件が分かる
    2. raw path、署名URL、secretが本文にない
    3. Report ID: `<uuid>` の行がある
    4. Agentに変更させてよい内容である
  不足情報はコメントではなくIssue本文へ補足します。
CHECKLIST
confirm '  上記を人間が確認しましたか?' || stop_with_retry

printf '\n%s5. 人間の承認ラベルを付けます%s\n' "$BOLD" "$OFF"
printf '  %sagent-readyは人間の承認gateなので、このwizardは付与を代行しません。ブラウザで操作してください。%s\n' \
  "$DIM" "$OFF"
printf '\n  ① 対象Issueを開きます（アプリが作ったIssueにはuser-reportが付いています）:\n'
printf '     https://github.com/%s/issues?q=is%%3Aissue+is%%3Aopen+label%%3Auser-report\n' "$expected_repository"
printf '\n  ② Issue画面の右sidebarで操作します:\n'
printf '     1. 「Labels」の見出しの右にある歯車アイコン（⚙）をクリックします\n'
printf '     2. 出てきた検索欄に agent:%s と入力し、一覧に現れた行をクリックします（左にチェックが付きます）\n' "$agent"
printf '     3. 検索欄を agent-ready に書き換え、同じように行をクリックします\n'
printf '        %s順番は agent:%s が先、agent-ready が最後です。%s\n' "$DIM" "$agent" "$OFF"
printf '     4. 一覧の外側をクリックして閉じます。閉じた時点で保存されます\n'
printf '     5. sidebarのLabelsに agent:%s と agent-ready が並べば完了です\n' "$agent"
printf '  %s検索しても候補が出ない場合はlabelが未作成です。別のターミナルで次を実行してください:%s\n' "$DIM" "$OFF"
printf '  %s  GITHUB_REPOSITORY=%s scripts/configure-github.sh%s\n' "$DIM" "$expected_repository" "$OFF"

while true; do
  issue_number="$(ask '
  ラベルを付けたIssueの番号（例: 12。空Enterで自動確認を省略）: ')" || exit 1
  issue_number="${issue_number#\#}"
  if [ -z "$issue_number" ]; then
    confirm "  agent:$agent と agent-ready の両方を付けましたか?" || stop_with_retry
    break
  fi
  if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
    printf '  ✖ Issue番号は数値です。Issue画面のタイトル横（#12）の数字です。\n'
    continue
  fi
  if ! issue_labels="$(gh issue view "$issue_number" --repo "$expected_repository" --json labels --jq '.labels[].name' 2>&1)"; then
    printf '  ✖ Issueを読み取れません: %s\n' "$issue_labels"
    continue
  fi
  missing=()
  grep -qx "agent:$agent" <<<"$issue_labels" || missing+=("agent:$agent")
  grep -qx 'agent-ready' <<<"$issue_labels" || missing+=('agent-ready')
  if [ "${#missing[@]}" -gt 0 ]; then
    printf '  ✖ まだ付いていないlabel: %s\n' "${missing[*]}"
    printf '    #%s の現在のlabel: %s\n' "$issue_number" "$(printf '%s' "$issue_labels" | tr '\n' ' ')"
    confirm '  付け直したら、もう一度確認しますか?' || stop_with_retry
    continue
  fi
  printf '  ✓ #%s に agent:%s と agent-ready が付いています。\n' "$issue_number" "$agent"
  break
done

printf '\n%s6. dispatcherを1回実行します%s\n' "$BOLD" "$OFF"
confirm '  承認済みIssueを最大1件処理しますか?' || stop_with_retry
output="$("$ROOT/scripts/run-dispatcher.sh")"
run_status=$?
printf '%s\n' "$output"
if [ "$run_status" != 0 ]; then
  printf '  dispatcher processがstatus %dで終了しました。\n' "$run_status"
  stop_with_retry
fi

case "$output" in
  *'"outcome":"PR_OPENED"'*)
    printf '\n%s完了: draft PRが作成されました。test、CI、diff、secret混入の有無を人間がreviewしてください。%s\n' "$BOLD" "$OFF"
    ;;
  *'"outcome":"IDLE"'*)
    printf '\n処理対象がありません。agent-ready、agent:%s、Report IDを確認してください。\n' "$agent"
    ;;
  *'"outcome":"LOST_CLAIM"'*)
    printf '\n別processが先にclaimしました。そのprocessの完了を待ってください。\n'
    ;;
  *'"outcome":"NEEDS_INFO"'*)
    printf '\nIssue本文へ情報を補足し、人間が再確認してagent-readyを付け直してください。\n'
    ;;
  *'"outcome":"FAILED"'*)
    printf '\n失敗原因を解消し、人間が再確認してagent-readyを付け直してください。\n'
    ;;
  *)
    printf '\noutcomeを判定できませんでした。上の出力とIssueのラベルを確認してください。\n'
    ;;
esac
