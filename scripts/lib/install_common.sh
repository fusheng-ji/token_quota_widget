#!/bin/zsh
# Shared lifecycle operations for the installer, repair and uninstall commands.
# Source this file after enabling `set -euo pipefail`.

bm_initialize() {
  user_root="${BEAVERMETER_USER_ROOT_OVERRIDE:-$HOME}"
  app_name="BeaverMeter.app"
  install_dir="$user_root/Applications"
  installed_app="$install_dir/$app_name"
  installed_widget="$installed_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex"
  agent_label="io.github.beavermeter.refresh"
  agent_path="$user_root/Library/LaunchAgents/$agent_label.plist"
  config_dir="$user_root/Library/Application Support/BeaverMeter"
  config_path="$config_dir/config.env"
  snapshot_path="$config_dir/beaver-meter-snapshot.json"
  log_dir="$user_root/Library/Logs/BeaverMeter"
  legacy_app="$install_dir/CodexWeek.app"
  legacy_agent_label="io.github.codexweek.refresh"
  legacy_agent_path="$user_root/Library/LaunchAgents/$legacy_agent_label.plist"
  legacy_config_dir="$user_root/Library/Application Support/CodexWeek"
  legacy_log_dir="$user_root/Library/Logs/CodexWeek"
  launch_domain="gui/$(id -u)"

  # Tests must provide every system command explicitly and use an isolated root.
  # A missing fake never falls through to a real launchctl, pkill or registration.
  if [[ -n "${BEAVERMETER_SYSTEM_COMMANDS:-}" ]]; then
    if [[ -z "${BEAVERMETER_USER_ROOT_OVERRIDE:-}" || "$user_root" == "$HOME" || "$user_root" != /* || "$user_root" == / ]]; then
      print -u2 "Test system commands require an isolated absolute user root."
      return 1
    fi
  fi
}

bm_run() {
  local command_name="$1"
  shift
  if [[ -n "${BEAVERMETER_SYSTEM_COMMANDS:-}" ]]; then
    local executable="$BEAVERMETER_SYSTEM_COMMANDS/$command_name"
    if [[ ! -x "$executable" ]]; then
      print -u2 "Missing test system command: $command_name"
      return 127
    fi
    "$executable" "$@"
    return
  fi
  case "$command_name" in
    lsregister)
      /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister "$@"
      ;;
    plistbuddy) /usr/libexec/PlistBuddy "$@" ;;
    *) command "$command_name" "$@" ;;
  esac
}

bm_widget_path() {
  local application="$1"
  print -r -- "$application/Contents/PlugIns/${application:t:r}WidgetExtension.appex"
}

bm_unregister_app() {
  local application="$1"
  [[ -d "$application" ]] || return 0
  bm_run pluginkit -r "$(bm_widget_path "$application")" >/dev/null 2>&1 || true
  bm_run lsregister -u "$application" >/dev/null 2>&1 || true
}

bm_unregister_other_apps() {
  local registered_app
  local registrations
  registrations="$(bm_run lsregister -dump 2>/dev/null)" || return 0
  while IFS= read -r registered_app; do
    if [[ -n "$registered_app" && "$registered_app" != "$installed_app" ]]; then
      bm_unregister_app "$registered_app"
    fi
  done < <(print -r -- "$registrations" | sed -En 's/^[[:space:]]*path:[[:space:]]*(.*BeaverMeter\.app)[[:space:]]+\(0x[0-9A-Fa-f]+\)$/\1/p')
}

bm_register_app() {
  local application="$1"
  bm_run lsregister -f -R -trusted "$application"
  bm_run pluginkit -a "$(bm_widget_path "$application")"
}

bm_stop_processes() {
  local process_name attempt
  for process_name in "$@"; do
    bm_run pkill -x "$process_name" >/dev/null 2>&1 || true
  done
  for process_name in "$@"; do
    for attempt in {1..20}; do
      bm_run pgrep -x "$process_name" >/dev/null 2>&1 || break
      sleep 0.1
    done
    if bm_run pgrep -x "$process_name" >/dev/null 2>&1; then
      bm_run pkill -KILL -x "$process_name" >/dev/null 2>&1 || true
      sleep 0.2
      if bm_run pgrep -x "$process_name" >/dev/null 2>&1; then
        print -u2 "Could not stop $process_name. Quit it manually and try again."
        return 1
      fi
    fi
  done
}

bm_stop_applications() {
  bm_unregister_app "$installed_app"
  bm_unregister_app "$legacy_app"
  bm_run killall chronod >/dev/null 2>&1 || true
  bm_stop_processes BeaverMeter BeaverMeterWidgetExtension BeaverMeterCollector CodexWeek CodexWeekWidgetExtension
}

bm_refresh_widget_services() {
  bm_run lsregister -gc >/dev/null 2>&1 || true
  bm_run killall chronod >/dev/null 2>&1 || true
  bm_run killall NotificationCenter >/dev/null 2>&1 || true
}

bm_open_app() {
  local application="$1" attempt
  for attempt in {1..10}; do
    if bm_run open "$application"; then
      return 0
    fi
    sleep 0.5
  done
  print -u2 "Could not relaunch ${application:t}."
  return 1
}
