#!/bin/zsh
set -euo pipefail

agent_label="io.github.beavermeter.refresh"
legacy_agent_label="io.github.codexweek.refresh"
timestamp="$(date '+%Y%m%d-%H%M%S')"

launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/$legacy_agent_label" >/dev/null 2>&1 || true

move_to_trash() {
  local target="$1"
  local label="$2"
  if [[ -e "$target" ]]; then
    mv "$target" "$HOME/.Trash/${label}-beavermeter-$timestamp"
  fi
}

move_to_trash "$HOME/Applications/BeaverMeter.app" "BeaverMeter.app"
move_to_trash "$HOME/Library/LaunchAgents/$agent_label.plist" "$agent_label.plist"
move_to_trash "$HOME/Library/Application Support/BeaverMeter" "BeaverMeter-data"
move_to_trash "$HOME/Library/Logs/BeaverMeter" "BeaverMeter-logs"
move_to_trash "$HOME/Applications/CodexWeek.app" "CodexWeek.app"
move_to_trash "$HOME/Library/LaunchAgents/$legacy_agent_label.plist" "$legacy_agent_label.plist"
move_to_trash "$HOME/Library/Application Support/CodexWeek" "CodexWeek-data"
move_to_trash "$HOME/Library/Logs/CodexWeek" "CodexWeek-logs"

killall chronod >/dev/null 2>&1 || true
print "BeaverMeter and any remaining CodexWeek files were moved to Trash and can be recovered there."
