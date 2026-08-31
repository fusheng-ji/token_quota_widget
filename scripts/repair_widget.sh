#!/bin/zsh
set -euo pipefail

installed_app="$HOME/Applications/CodexWeek.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if [[ ! -d "$installed_app" ]]; then
  print -u2 "CodexWeek.app is not installed. Run ./scripts/install.sh first."
  exit 1
fi

"$lsregister" -f -R -trusted "$installed_app"
pluginkit -a "$installed_app/Contents/PlugIns/CodexWeekWidgetExtension.appex"
killall chronod >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true
open "$installed_app"
print "Cursor + Codex widget registration and caches were refreshed."
