#!/usr/bin/env bash
set -euo pipefail
: "${DISPATCHER_TOKEN:?required}"
: "${DISPATCHER_REPOSITORY:?required}"
: "${DISPATCHER_ENDPOINT:?required}"
exec "$(dirname "$0")/../gradlew" :dispatcher:run
