#!/bin/zsh
set -euo pipefail

installed_app="$HOME/Applications/BeaverMeter.app"
installed_widget="$installed_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex"
legacy_app="$HOME/Applications/CodexWeek.app"
legacy_widget="$legacy_app/Contents/PlugIns/CodexWeekWidgetExtension.appex"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

unregister_other_beavermeter_apps() {
  local registered_app
  "$lsregister" -dump 2>/dev/null \
    | sed -En 's/^[[:space:]]*path:[[:space:]]*(.*BeaverMeter\.app)[[:space:]]+\(0x[0-9A-Fa-f]+\)$/\1/p' \
    | while IFS= read -r registered_app; do
        if [[ "$registered_app" != "$installed_app" ]]; then
          pluginkit -r "$registered_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex" >/dev/null 2>&1 || true
          "$lsregister" -u "$registered_app" >/dev/null 2>&1 || true
        fi
      done
}

if [[ ! -d "$installed_app" ]]; then
  print -u2 "BeaverMeter.app is not installed. Run ./scripts/install.sh first."
  exit 1
fi

# Removing this bundle ID first also clears stale Xcode DerivedData copies that
# otherwise appear as duplicate entries in the macOS Widget gallery.
if [[ -d "$legacy_widget" ]]; then
  pluginkit -r "$legacy_widget" >/dev/null 2>&1 || true
fi
unregister_other_beavermeter_apps
pluginkit -r "$installed_widget" >/dev/null 2>&1 || true
"$lsregister" -f -R -trusted "$installed_app"
pluginkit -a "$installed_widget"
"$lsregister" -gc >/dev/null 2>&1 || true
pkill -x BeaverMeter >/dev/null 2>&1 || true
for _ in {1..20}; do
  pgrep -x BeaverMeter >/dev/null 2>&1 || break
  sleep 0.1
done
killall chronod >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true
launched=0
for _ in {1..10}; do
  if open "$installed_app"; then
    launched=1
    break
  fi
  sleep 0.5
done
if (( launched == 0 )); then
  print -u2 "Could not relaunch BeaverMeter after refreshing WidgetKit."
  exit 1
fi
print "BeaverMeter widget registration and caches were refreshed."
