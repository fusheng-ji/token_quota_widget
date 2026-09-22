#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/install_common.sh"
bm_initialize
timestamp="$(date '+%Y%m%d-%H%M%S')"

bm_run launchctl bootout "$launch_domain/$agent_label" >/dev/null 2>&1 || true
bm_run launchctl bootout "$launch_domain/$legacy_agent_label" >/dev/null 2>&1 || true
bm_stop_applications
mkdir -p "$user_root/.Trash"

move_to_trash() {
  local target="$1"
  local label="$2"
  if [[ -e "$target" ]]; then
    mv "$target" "$user_root/.Trash/${label}-beavermeter-$timestamp"
  fi
}

move_to_trash "$installed_app" "BeaverMeter.app"
move_to_trash "$agent_path" "$agent_label.plist"
move_to_trash "$config_dir" "BeaverMeter-data"
move_to_trash "$log_dir" "BeaverMeter-logs"
move_to_trash "$legacy_app" "CodexWeek.app"
move_to_trash "$legacy_agent_path" "$legacy_agent_label.plist"
move_to_trash "$legacy_config_dir" "CodexWeek-data"
move_to_trash "$legacy_log_dir" "CodexWeek-logs"

bm_refresh_widget_services
print "BeaverMeter and any remaining CodexWeek files were moved to Trash and can be recovered there."
