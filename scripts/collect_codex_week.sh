#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
output_path="${1:-$HOME/Library/Application Support/CodexWeek/codex-week-snapshot.json}"
config_path="${CODEX_WEEK_CONFIG:-$HOME/Library/Application Support/CodexWeek/config.env}"

if [[ -r "$config_path" ]]; then
  source "$config_path"
fi
if [[ -n "${CODEX_ROOT:-}" ]]; then
  export CODEX_HOME="$CODEX_ROOT"
fi
if [[ -n "${CURSOR_STATE_DB:-}" ]]; then
  export CURSOR_STATE_DB
fi

if [[ -n "${CODEXWEEK_COLLECTOR:-}" && -x "$CODEXWEEK_COLLECTOR" ]]; then
  exec "$CODEXWEEK_COLLECTOR" --output "$output_path"
fi

for collector in \
  "$script_dir/../Helpers/CodexWeekCollector" \
  "$script_dir/CodexWeekCollector" \
  "$script_dir/../MacOS/CodexWeekCollector"; do
  if [[ -x "$collector" ]]; then
    exec "$collector" --output "$output_path"
  fi
done

print -u2 "CodexWeekCollector is missing. Reinstall Cursor + Codex."
exit 1
