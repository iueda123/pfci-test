#!/usr/bin/env bash
set -euo pipefail
if rg -n --hidden --glob '!**/build/**' --glob '!**/src/test/**' --glob '!.git/**' --glob '!dev-notes/**' --glob '!supabase/.env.example' '(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{32,}|SUPABASE_SERVICE_ROLE_KEY=[A-Za-z0-9._-]{20,})' .; then
  echo 'Potential committed secret found' >&2
  exit 1
fi
if rg -n --hidden --glob '!**/build/**' --glob '!.git/**' --glob '!dev-notes/**' --glob '!scripts/security-gate.sh' '(danger-full-access|dangerously-skip-permissions|--yolo)' .; then
  echo 'Forbidden agent bypass flag found' >&2
  exit 1
fi
echo 'Security gate passed'
