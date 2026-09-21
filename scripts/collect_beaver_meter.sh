#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
output_path="$HOME/Library/Application Support/BeaverMeter/beaver-meter-snapshot.json"
collector_arguments=()
while (( $# > 0 )); do
  case "$1" in
    --codex-only)
      collector_arguments+=("--codex-only")
      shift
      ;;
    --output)
      if (( $# < 2 )); then
        print -u2 "--output requires a path."
        exit 2
      fi
      output_path="$2"
      shift 2
      ;;
    -* )
      print -u2 "Unknown BeaverMeter collector option: $1"
      exit 2
      ;;
    *)
      output_path="$1"
      shift
      ;;
  esac
done
collector_arguments+=("--output" "$output_path")
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
[[ -n "${CODEX_REMOTE_SSH_HOST:-}" ]] && export CODEX_REMOTE_SSH_HOST
[[ -n "${CODEX_REMOTE_ROOT:-}" ]] && export CODEX_REMOTE_ROOT
[[ -n "${CODEX_REMOTE_PYTHON:-}" ]] && export CODEX_REMOTE_PYTHON
export BEAVERMETER_REMOTE_SCRIPT="$script_dir/remote_codex_usage.py"

collector_override="${BEAVERMETER_COLLECTOR:-${CODEXWEEK_COLLECTOR:-}}"
if [[ -n "$collector_override" && -x "$collector_override" ]]; then
  exec "$collector_override" "${collector_arguments[@]}"
fi

for collector in \
  "$script_dir/../Helpers/BeaverMeterCollector" \
  "$script_dir/BeaverMeterCollector" \
  "$script_dir/../MacOS/BeaverMeterCollector"; do
  if [[ -x "$collector" ]]; then
    exec "$collector" "${collector_arguments[@]}"
  fi
done

print -u2 "BeaverMeterCollector is missing. Reinstall BeaverMeter."
exit 1
