#!/bin/zsh
set -euo pipefail

source "${0:A:h}/lib/install_common.sh"
bm_initialize
if [[ ! -d "$installed_app" ]]; then
  print -u2 "BeaverMeter.app is not installed. Run ./scripts/install.sh first."
  exit 1
fi

# Restore the installed registration even if stopping an old extension fails.
repair_complete=0
repair_cleanup() {
  local exit_code=$?
  if (( ! repair_complete )); then
    bm_register_app "$installed_app" >/dev/null 2>&1 || true
  fi
  return "$exit_code"
}
trap repair_cleanup EXIT
bm_stop_applications
bm_unregister_other_apps
bm_register_app "$installed_app"
bm_refresh_widget_services
bm_open_app "$installed_app"
repair_complete=1
print "BeaverMeter widget registration and caches were refreshed."
