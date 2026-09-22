#!/bin/zsh
# Installation transaction. All backups finish before live state is changed.

bm_prepare_transaction() {
  rollback_dir="$(mktemp -d "${TMPDIR:-/tmp}/beavermeter-rollback.XXXXXX")"
  chmod 700 "$rollback_dir"
  transaction_started=0
  install_committed=0
  prior_agent_loaded=0
  prior_legacy_agent_loaded=0
  prior_app_running=0
  prior_legacy_app_running=0

  local entry source_path
  for entry in app agent data logs; do
    case "$entry" in
      app) source_path="$installed_app" ;;
      agent) source_path="$agent_path" ;;
      data) source_path="$config_dir" ;;
      logs) source_path="$log_dir" ;;
    esac
    if [[ -e "$source_path" ]]; then
      /usr/bin/ditto "$source_path" "$rollback_dir/$entry"
    fi
  done
  bm_run launchctl print "$launch_domain/$agent_label" >/dev/null 2>&1 && prior_agent_loaded=1
  bm_run launchctl print "$launch_domain/$legacy_agent_label" >/dev/null 2>&1 && prior_legacy_agent_loaded=1
  bm_run pgrep -x BeaverMeter >/dev/null 2>&1 && prior_app_running=1
  bm_run pgrep -x CodexWeek >/dev/null 2>&1 && prior_legacy_app_running=1
  return 0
}

bm_restore_transaction() {
  local entry destination_path
  bm_run launchctl bootout "$launch_domain/$agent_label" >/dev/null 2>&1 || true
  bm_run launchctl bootout "$launch_domain/$legacy_agent_label" >/dev/null 2>&1 || true
  bm_unregister_app "$installed_app"
  bm_stop_processes BeaverMeter BeaverMeterWidgetExtension BeaverMeterCollector || return 1
  for entry in app agent data logs; do
    case "$entry" in
      app) destination_path="$installed_app" ;;
      agent) destination_path="$agent_path" ;;
      data) destination_path="$config_dir" ;;
      logs) destination_path="$log_dir" ;;
    esac
    rm -rf "$destination_path" || return 1
    if [[ -e "$rollback_dir/$entry" ]]; then
      mkdir -p "${destination_path:h}" || return 1
      /usr/bin/ditto "$rollback_dir/$entry" "$destination_path" || return 1
    fi
  done
  [[ ! -d "$installed_app" ]] || bm_register_app "$installed_app" || return 1
  [[ ! -d "$legacy_app" ]] || bm_register_app "$legacy_app" || return 1
  if (( prior_agent_loaded )); then
    bm_run launchctl bootstrap "$launch_domain" "$agent_path" || return 1
  fi
  if (( prior_legacy_agent_loaded )); then
    bm_run launchctl bootstrap "$launch_domain" "$legacy_agent_path" || return 1
  fi
  bm_refresh_widget_services
  if (( prior_app_running )); then
    bm_open_app "$installed_app" || return 1
  fi
  if (( prior_legacy_app_running )); then
    bm_open_app "$legacy_app" || return 1
  fi
}

bm_install_cleanup() {
  local exit_code=$?
  trap - ZERR EXIT INT TERM
  if (( transaction_started && ! install_committed )); then
    print -u2 "BeaverMeter installation failed; restoring the previous installation."
    if ! bm_restore_transaction; then
      print -u2 "Automatic restore was incomplete. Backups are retained at: $rollback_dir"
      return 1
    fi
  fi
  [[ ! -d "$rollback_dir" ]] || rm -rf "$rollback_dir"
  return "$exit_code"
}
