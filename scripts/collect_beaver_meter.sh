#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
output_path="${1:-$HOME/Library/Application Support/BeaverMeter/beaver-meter-snapshot.json}"
config_path="${BEAVER_METER_CONFIG:-${CODEX_WEEK_CONFIG:-$HOME/Library/Application Support/BeaverMeter/config.env}}"

if [[ -r "$config_path" ]]; then
  source "$config_path"
fi
if [[ -n "${CODEX_ROOT:-}" ]]; then
  export CODEX_HOME="$CODEX_ROOT"
fi
if [[ -n "${CURSOR_STATE_DB:-}" ]]; then
  export CURSOR_STATE_DB
fi

collector_override="${BEAVERMETER_COLLECTOR:-${CODEXWEEK_COLLECTOR:-}}"
if [[ -n "$collector_override" && -x "$collector_override" ]]; then
  exec "$collector_override" --output "$output_path"
fi

for collector in \
  "$script_dir/../Helpers/BeaverMeterCollector" \
  "$script_dir/BeaverMeterCollector" \
  "$script_dir/../MacOS/BeaverMeterCollector"; do
  if [[ -x "$collector" ]]; then
    exec "$collector" --output "$output_path"
  fi
done

print -u2 "BeaverMeterCollector is missing. Reinstall BeaverMeter."
exit 1
