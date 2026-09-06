#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
user_root="${BEAVERMETER_USER_ROOT_OVERRIDE:-$HOME}"
app_name="BeaverMeter.app"
install_dir="$user_root/Applications"
installed_app="$install_dir/$app_name"
agent_label="io.github.beavermeter.refresh"
agent_path="$user_root/Library/LaunchAgents/$agent_label.plist"
config_dir="$user_root/Library/Application Support/BeaverMeter"
config_path="$config_dir/config.env"
snapshot_path="$config_dir/beaver-meter-snapshot.json"
log_dir="$user_root/Library/Logs/BeaverMeter"
legacy_app="$user_root/Applications/CodexWeek.app"
legacy_agent_label="io.github.codexweek.refresh"
legacy_agent_path="$user_root/Library/LaunchAgents/$legacy_agent_label.plist"
legacy_config_dir="$user_root/Library/Application Support/CodexWeek"
legacy_log_dir="$user_root/Library/Logs/CodexWeek"
migration_script="$project_dir/scripts/migrate_beavermeter_data.sh"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

for command_name in xcodegen sqlite3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing dependency: $command_name"
    print -u2 "Install prerequisites with: brew install xcodegen"
    exit 1
  fi
done

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
  print -u2 "Full Xcode is required at /Applications/Xcode.app."
  exit 1
fi

existing_config="$config_path"
if [[ ! -r "$existing_config" && -r "$legacy_config_dir/config.env" ]]; then
  existing_config="$legacy_config_dir/config.env"
fi
if [[ -r "$existing_config" ]]; then
  source "$existing_config"
fi

print "BeaverMeter setup"
print "Existing CodexWeek settings and DeepSeek credentials are migrated automatically."
print "Cursor and Codex continue to reuse their local sessions."
print

default_team_id="${BEAVERMETER_DEVELOPMENT_TEAM:-${CODEXWEEK_DEVELOPMENT_TEAM:-}}"
read "team_id?Apple Developer Team ID [${default_team_id:-local-only signing}]: "
team_id="${team_id:-$default_team_id}"
if [[ -n "$team_id" && ! "$team_id" =~ '^[A-Z0-9]{10}$' ]]; then
  print -u2 "Team ID must be blank or the 10-character value shown in Xcode → Settings → Accounts."
  exit 1
fi

default_prefix="${BEAVERMETER_BUNDLE_PREFIX:-${CODEXWEEK_BUNDLE_PREFIX:-com.${USER//[^A-Za-z0-9]/}}}"
read "bundle_prefix?Unique bundle prefix [$default_prefix]: "
bundle_prefix="${bundle_prefix:-$default_prefix}"
if [[ ! "$bundle_prefix" =~ '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$' ]]; then
  print -u2 "Bundle prefix must look like com.yourname."
  exit 1
fi

default_codex_root="${CODEX_ROOT:-$user_root/.codex}"
read "codex_root?Codex data directory [$default_codex_root]: "
codex_root="${codex_root:-$default_codex_root}"

default_cursor_state_db="${CURSOR_STATE_DB:-$user_root/Library/Application Support/Cursor/User/globalStorage/state.vscdb}"
read "cursor_state_db?Cursor account database [$default_cursor_state_db]: "
cursor_state_db="${cursor_state_db:-$default_cursor_state_db}"

read "refresh_minutes?Refresh interval in minutes [5]: "
refresh_minutes="${refresh_minutes:-5}"
if [[ ! "$refresh_minutes" =~ '^[0-9]+$' ]] || (( refresh_minutes < 5 || refresh_minutes > 1440 )); then
  print -u2 "Refresh interval must be between 5 and 1440 minutes."
  exit 1
fi

export BEAVERMETER_DEVELOPMENT_TEAM="$team_id"
export BEAVERMETER_BUNDLE_PREFIX="$bundle_prefix"

signing_overrides=()
if [[ -z "$team_id" ]]; then
  signing_overrides=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
  )
  print "No Apple signing identity selected; using local ad-hoc signing."
fi

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/beavermeter-build.XXXXXX")"
rollback_dir="$(mktemp -d "${TMPDIR:-/tmp}/beavermeter-rollback.XXXXXX")"
built_app="$derived_data/Build/Products/Release/$app_name"
prior_app_backup="$rollback_dir/$app_name"
prior_agent_backup="$rollback_dir/$agent_label.plist"
installed_new_app=0
install_committed=0

cleanup() {
  local status=$?
  if [[ -d "$built_app" ]]; then
    "$lsregister" -u "$built_app" >/dev/null 2>&1 || true
    pluginkit -r "$built_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex" >/dev/null 2>&1 || true
  fi
  if (( status != 0 && install_committed == 0 )); then
    print -u2 "BeaverMeter installation failed; restoring the previous installation."
    launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true
    if (( installed_new_app == 1 )); then
      rm -rf "$installed_app"
    fi
    if [[ -d "$prior_app_backup" ]]; then
      mv "$prior_app_backup" "$installed_app"
    fi
    if [[ -f "$prior_agent_backup" ]]; then
      mv "$prior_agent_backup" "$agent_path"
      launchctl bootstrap "gui/$(id -u)" "$agent_path" >/dev/null 2>&1 || true
    elif [[ -f "$legacy_agent_path" ]]; then
      launchctl bootstrap "gui/$(id -u)" "$legacy_agent_path" >/dev/null 2>&1 || true
    fi
  fi
  [[ -d "$derived_data" ]] && rm -rf "$derived_data"
  [[ -d "$rollback_dir" ]] && rm -rf "$rollback_dir"
  return "$status"
}
trap cleanup EXIT

cd "$project_dir"
xcodegen generate
DEVELOPER_DIR="$developer_dir" xcodebuild \
  -project BeaverMeter.xcodeproj \
  -scheme BeaverMeter \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=YES \
  "${signing_overrides[@]}" \
  build

launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/$legacy_agent_label" >/dev/null 2>&1 || true
for process_name in BeaverMeter CodexWeek; do
  pkill -x "$process_name" >/dev/null 2>&1 || true
done
for process_name in BeaverMeter CodexWeek; do
  for _ in {1..20}; do
    pgrep -x "$process_name" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -x "$process_name" >/dev/null 2>&1; then
    print -u2 "Could not stop $process_name. Quit it manually and run the installer again."
    exit 1
  fi
done

mkdir -p "$install_dir" "$user_root/Library/LaunchAgents" "$user_root/.Trash"
if [[ -d "$installed_app" ]]; then
  mv "$installed_app" "$prior_app_backup"
fi
if [[ -f "$agent_path" ]]; then
  mv "$agent_path" "$prior_agent_backup"
fi

BEAVERMETER_USER_ROOT_OVERRIDE="$user_root" zsh "$migration_script"
mkdir -p "$config_dir" "$log_dir"
chmod 700 "$config_dir"
ditto "$built_app" "$installed_app"
installed_new_app=1

{
  printf 'CODEX_ROOT=%q\n' "$codex_root"
  printf 'CURSOR_STATE_DB=%q\n' "$cursor_state_db"
} > "$config_path"
chmod 600 "$config_path"

/usr/libexec/PlistBuddy -c "Add :Label string $agent_label" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string /bin/zsh" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string $installed_app/Contents/Resources/collect_beaver_meter.sh" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :StartInterval integer $((refresh_minutes * 60))" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $log_dir/refresh.out.log" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $log_dir/refresh.err.log" "$agent_path"

legacy_widget="$legacy_app/Contents/PlugIns/CodexWeekWidgetExtension.appex"
installed_widget="$installed_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex"
if [[ -d "$legacy_widget" ]]; then
  pluginkit -r "$legacy_widget" >/dev/null 2>&1 || true
fi
pluginkit -r "$installed_widget" >/dev/null 2>&1 || true
"$lsregister" -f -R -trusted "$installed_app"
pluginkit -a "$installed_widget"
launchctl bootstrap "gui/$(id -u)" "$agent_path"
"$installed_app/Contents/Resources/collect_beaver_meter.sh" "$snapshot_path" >/dev/null

schema_version="$(/usr/bin/plutil -extract schemaVersion raw -o - "$snapshot_path" 2>/dev/null || true)"
if [[ "$schema_version" != "5" ]]; then
  print -u2 "BeaverMeter did not produce a schema v5 snapshot."
  exit 1
fi
codesign --verify --deep --strict "$installed_app"
launchctl kickstart -k "gui/$(id -u)/$agent_label"
open "$installed_app"
install_committed=1

if [[ -d "$legacy_app" ]]; then
  "$lsregister" -u "$legacy_app" >/dev/null 2>&1 || true
fi
rm -rf "$legacy_app" "$legacy_config_dir" "$legacy_log_dir"
rm -f "$legacy_agent_path"

print
print "Installed: $installed_app"
print "Refresh interval: $refresh_minutes minutes"
print "CodexWeek data and credentials were migrated to BeaverMeter."
print "The Widget has a new identity: remove the old Widget and add BeaverMeter again."
