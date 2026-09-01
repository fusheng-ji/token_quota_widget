#!/bin/zsh
set -euo pipefail

agent_label="io.github.codexweek.refresh"
agent_path="$HOME/Library/LaunchAgents/$agent_label.plist"
installed_app="$HOME/Applications/CodexWeek.app"
config_dir="$HOME/Library/Application Support/CodexWeek"
timestamp="$(date '+%Y%m%d-%H%M%S')"

launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true

for target in "$installed_app" "$agent_path" "$config_dir"; do
  if [[ -e "$target" ]]; then
    name="${target:t}"
    mv "$target" "$HOME/.Trash/${name}-codexweek-$timestamp"
  fi
done

killall chronod >/dev/null 2>&1 || true
print "AI Token Quota was moved to Trash and can be recovered there."
