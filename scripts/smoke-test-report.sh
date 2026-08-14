#!/usr/bin/env bash
set -euo pipefail
: "${REPORT_API_URL:?required}"
: "${SUPABASE_PUBLISHABLE_KEY:?required}"
echo 'Launch the JavaFX app, review preview, and submit the fixture report.'
exec "$(dirname "$0")/../gradlew" :app:run
