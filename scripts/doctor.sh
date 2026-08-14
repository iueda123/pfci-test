#!/usr/bin/env bash
# セットアップの現在地を実測して、次の1手だけを出します。読み取り専用で、値の書き換えはしません。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=quick
ROUTE=''
ONLY=''

usage() {
  cat <<'USAGE'
使い方: scripts/doctor.sh [--full] [--offline] [--route app|local|cloud] [--only id,id] [--list]

  --full     build/test、headless capture、DB到達確認まで実走します（時間がかかります）
  --offline  network到達確認を行いません
  --route    routeの自動推定を上書きします（app=ローカル保存のみ / local / cloud）
  --only     指定したstageだけを検査します（idは --list で確認できます）
  --list     stage一覧を表示して終了します
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --full) MODE=full ;;
    --offline) MODE=offline ;;
    --route) ROUTE="${2:-}"; shift ;;
    --route=*) ROUTE="${1#--route=}" ;;
    --only) ONLY="${2:-}"; shift ;;
    --only=*) ONLY="${1#--only=}" ;;
    --list) LIST=1 ;;
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

if [ -n "${LIST:-}" ]; then
  broken=0
  for id in "${STAGE_IDS[@]}"; do
    if ! declare -F "check_${id//-/_}" >/dev/null; then
      echo "stage $id に check_${id//-/_} がありません" >&2
      broken=1
    fi
    printf '%-16s route=%-16s tier=%-8s %s\n' "$id" "${STAGE_ROUTES[$id]}" "${STAGE_TIER[$id]}" "${STAGE_TITLE[$id]}"
  done
  exit "$broken"
fi

# routeが未指定なら REPORT_API_URL から推定します（保存された状態には依存しません）。
route_source='--route'
if [ -z "$ROUTE" ]; then
  ROUTE="$(detect_route)"
  if [ "$ROUTE" = app ]; then route_source='REPORT_API_URL が未設定のため'; else route_source='REPORT_API_URL から推定'; fi
fi
case "$ROUTE" in
  app|local|cloud) ;;
  *) echo "route は app / local / cloud のいずれかです: $ROUTE" >&2; exit 2 ;;
esac

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
else
  BOLD=''; DIM=''; GREEN=''; RED=''; YELLOW=''; OFF=''
fi

printf '%s継続的改善PoC — セットアップ現在地%s\n\n' "$BOLD" "$OFF"
printf '  route : %s  %s(%s)%s\n' "$ROUTE" "$DIM" "$route_source" "$OFF"
case "$MODE" in
  quick) printf '  mode  : quick %s(--full で build/test と疎通確認まで実走)%s\n' "$DIM" "$OFF" ;;
  full)  printf '  mode  : full\n' ;;
  offline) printf '  mode  : offline %s(network到達確認は行いません)%s\n' "$DIM" "$OFF" ;;
esac
if [ -f "$ROOT/.env" ]; then
  perm="$(stat -c '%a' "$ROOT/.env" 2>/dev/null || echo '?')"
  case "$perm" in
    600|400) printf '  .env  : あり (%s)\n' "$perm" ;;
    *) printf '  .env  : あり (%s) %s← chmod 600 .env を推奨%s\n' "$perm" "$YELLOW" "$OFF" ;;
  esac
else
  printf '  .env  : なし %s(cp .env.example .env で作れます)%s\n' "$DIM" "$OFF"
fi
printf '\n'

ok=0; failed=0; unknown=0; skipped=0
first_fail=''

for id in "${STAGE_IDS[@]}"; do
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$id,"* ]]; then continue; fi
  title="${STAGE_TITLE[$id]}"
  status=0
  evaluate_stage "$id" || status=$?

  case "$status" in
    0) printf ' %s✔%s %-16s %s\n' "$GREEN" "$OFF" "$id" "$title"; ok=$(( ok + 1 )) ;;
    1) printf ' %s✖%s %-16s %s\n' "$RED" "$OFF" "$id" "$title"; failed=$(( failed + 1 ))
       [ -z "$first_fail" ] && first_fail="$id" ;;
    2) printf ' %s−  %-16s %s%s\n' "$DIM" "$id" "$title" "$OFF"; skipped=$(( skipped + 1 )) ;;
    *) printf ' %s·  %-16s %s%s\n' "$DIM" "$id" "$title" "$OFF"; unknown=$(( unknown + 1 )) ;;
  esac

  if [ "$status" != 2 ] && [ "${#STAGE_DETAILS[@]}" -gt 0 ]; then
    for line in "${STAGE_DETAILS[@]}"; do
      printf '   %s  %s%s\n' "$DIM" "$line" "$OFF"
    done
  fi

  if [ "$status" = 1 ] && [ "$first_fail" = "$id" ]; then
    NEXT_HINT="${STAGE_HINT:-${STAGE_NEXT[$id]}}"
    NEXT_DOC="${STAGE_DOC[$id]}"
  fi
done

printf '\n  到達 %d / 未到達 %d / 未検査 %d / 対象外 %d\n\n' "$ok" "$failed" "$unknown" "$skipped"

if [ -n "$first_fail" ]; then
  printf '%s次の1手 (%s):%s\n' "$BOLD" "$first_fail" "$OFF"
  printf '  %s\n' "$NEXT_HINT"
  printf '  詳細 → %s\n' "$NEXT_DOC"
  exit 1
fi

if [ "$unknown" -gt 0 ]; then
  case "$MODE" in
    quick)
      printf '%s判定: quick検査の範囲では、見つかった設定不足はありません。%s\n\n' "$BOLD" "$OFF"
      printf '%s次の1手（初回セットアップの検証を完了）:%s\n' "$BOLD" "$OFF"
      printf '  scripts/doctor.sh --full\n\n'
      printf '  これは build/test、JavaFXのheadless capture、DBまでの疎通を実際に検査します。\n'
      if [ "$ROUTE" != app ]; then
        printf '  注意: DB疎通で recoverStale を実行し、45分以上放置されたAgent runがあれば timed_out に整理します。\n'
      fi
      printf '  成功すると、報告 → Issue → Agent → draft PR の実験手順が表示されます。\n'
      ;;
    offline)
      printf '%s判定: offline検査の範囲では、見つかった設定不足はありません。%s\n\n' "$BOLD" "$OFF"
      printf '%s次の1手（networkを含む検証）:%s\n' "$BOLD" "$OFF"
      printf '  scripts/doctor.sh --full\n'
      ;;
    full)
      printf '%sfull検査後も未検査のstageが %d 件残っています。%s\n' "$BOLD" "$unknown" "$OFF"
      printf '  上の「未検査」に表示された理由を解消し、scripts/doctor.sh --full を再実行してください。\n'
      ;;
  esac
else
  printf 'すべてのstageに到達しています。\n\n'
  printf '%s次に進める実験:%s\n' "$BOLD" "$OFF"
  if [ "$ROUTE" = app ]; then
    printf '  現在はローカル保存のみのrouteです。\n'
    printf '  報告 → Issue → Agent → draft PR まで試すには、scripts/setup.sh を実行し、\n'
    printf '  local または cloud route を選んでください。\n'
    printf '  詳細 → docs/setup-supabase.md\n'
  else
    printf '  1. set -a; source .env; set +a; scripts/smoke-test-report.sh\n'
    printf '  2. previewを確認して送信し、作成されたIssueに生path・署名URL・secretが無いことを人が確認\n'
    printf '  3. GitHub上で agent:codex または agent:claude と agent-ready を人が付与\n'
    printf '  4. scripts/run-dispatcher.sh\n'
    printf '  5. draft PRのtest・CI・diffを人がreview（人の承認なしにmergeしない）\n'
    printf '  詳細 → docs/setup-supabase.md#34-疎通確認\n'
  fi
fi
