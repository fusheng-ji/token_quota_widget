#!/bin/zsh
set -euo pipefail
if [[ "${BM_TEST_FAIL:-}" == collector ]]; then
  print -r -- changed-by-failed-collection > "${1:h}/deepseek-platform-token"
  print -r -- changed-by-failed-collection > "${1:h}/new-scan-cache.json"
  exit 16
fi
printf '{"schemaVersion":5}\n' > "$1"
chmod 600 "$1"
