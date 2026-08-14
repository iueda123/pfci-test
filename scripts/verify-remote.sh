#!/usr/bin/env bash
# docs/setup-supabase.md 3.4 の疎通確認①②を自動で行います。
# ③（アプリからの往復）は画面での目視確認が要るため scripts/smoke-test-report.sh を使ってください。
set -euo pipefail
exec "$(dirname "$0")/doctor.sh" --only functions,storage-private,edge-secrets,dispatcher-auth --full "$@"
