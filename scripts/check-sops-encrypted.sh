#!/usr/bin/env bash
# Fail if any YAML file under a secrets/ directory is not SOPS-encrypted.
# *.example files and .sops.yaml are exempt.
set -euo pipefail

cd "$(dirname "$0")/.."
status=0
while IFS= read -r -d '' f; do
  if ! grep -q '^sops:' "$f"; then
    echo "NOT SOPS-ENCRYPTED: $f" >&2
    status=1
  fi
done < <(find . -path ./.git -prune -o -type f -path '*/secrets/*' \
            \( -name '*.yaml' -o -name '*.yml' \) \
            ! -name '*.example' ! -name '.sops.yaml' -print0)

if [ "$status" -eq 0 ]; then
  echo "ok: all files under secrets/ are encrypted (or templates)"
fi
exit "$status"
