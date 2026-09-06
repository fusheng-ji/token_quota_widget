#!/bin/zsh
set -euo pipefail

installed_app="$HOME/Applications/BeaverMeter.app"
installed_widget="$installed_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex"
legacy_app="$HOME/Applications/CodexWeek.app"
legacy_widget="$legacy_app/Contents/PlugIns/CodexWeekWidgetExtension.appex"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if [[ ! -d "$installed_app" ]]; then
  print -u2 "BeaverMeter.app is not installed. Run ./scripts/install.sh first."
  exit 1
fi

# Removing this bundle ID first also clears stale Xcode DerivedData copies that
# otherwise appear as duplicate entries in the macOS Widget gallery.
if [[ -d "$legacy_widget" ]]; then
  pluginkit -r "$legacy_widget" >/dev/null 2>&1 || true
fi
pluginkit -r "$installed_widget" >/dev/null 2>&1 || true
"$lsregister" -f -R -trusted "$installed_app"
pluginkit -a "$installed_widget"
killall chronod >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true
open "$installed_app"
print "BeaverMeter widget registration and caches were refreshed."
