#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
scan_paths=(Package.swift README.md ROADMAP.md CHANGELOG.md DISTRIBUTION.md docs LICENSE PRIVACY.md SECURITY.md Scripts apps core .env.example .gitignore)

if grep -RInIE \
  --exclude='check-public.sh' \
  '(AIza[0-9A-Za-z_-]{35}|sk-or-|sk-proj-|sk-[A-Za-z0-9_-]{20,}|/Users/[^/]+/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|api[_ -]?key[[:space:]]*=[[:space:]]*[^[:space:]]+)' \
  "${scan_paths[@]}"; then
  echo "Potential secret or personal path found."
  failed=1
fi

if grep -RInIE --exclude='check-public.sh' '(Himanshu|himanshu|Mittal|mittal)' "${scan_paths[@]}"; then
  echo "Potential personal name found."
  failed=1
fi

for path in .build dist .env; do
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    echo "Generated/private path is tracked: $path"
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo "Public-source check passed."
