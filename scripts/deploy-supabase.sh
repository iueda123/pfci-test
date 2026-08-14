#!/usr/bin/env bash
set -euo pipefail
: "${SUPABASE_PROJECT_REF:?required}"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push
for function in create-report finalize-report get-redacted-artifacts purge-expired-artifacts dispatcher-control; do
  supabase functions deploy "$function" --project-ref "$SUPABASE_PROJECT_REF"
done
echo 'Set Edge secrets from a protected operator environment; never commit them.'
