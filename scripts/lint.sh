#!/usr/bin/env bash
set -euo pipefail
if rg -n '[[:blank:]]+$' --glob '*.java' --glob '*.kt' --glob '*.kts' --glob '*.ts' --glob '*.json' --glob '*.md' --glob '*.sh' --glob '*.sql' --glob '!**/dev-notes/**' --glob '!**/.md-back*/**' --glob '!**/.md-log*/**' .; then
  echo 'Trailing whitespace found' >&2
  exit 1
fi
for script in scripts/*.sh scripts/*/*.sh; do bash -n "$script"; done
node -e 'const fs=require("fs"); for (const f of fs.readdirSync("schemas")) JSON.parse(fs.readFileSync(`schemas/${f}`,"utf8"))'
node "$(dirname "$0")/check-doc-links.mjs"
"$(dirname "$0")/doctor.sh" --list >/dev/null
echo 'Lint passed'
