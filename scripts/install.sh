#!/bin/zsh
set -euo pipefail
umask 077

project_dir="${0:A:h:h}"
source "$project_dir/scripts/lib/install_common.sh"
source "$project_dir/scripts/lib/install_transaction.sh"
bm_initialize

for command_name in xcodegen sqlite3; do
  if [[ -z "${BEAVERMETER_SYSTEM_COMMANDS:-}" ]] && ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 "Missing dependency: $command_name"
    print -u2 "Install prerequisites with: brew install xcodegen"
    exit 1
  fi
done

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -z "${BEAVERMETER_SYSTEM_COMMANDS:-}" && ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
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

# Empty is an explicit disabled setting, including on subsequent upgrades.
default_remote_host="${CODEX_REMOTE_SSH_HOST:-}"
read "remote_codex_host?Remote Codex SSH host [${default_remote_host:-disabled}, - to disable]: "
remote_codex_host="${remote_codex_host:-$default_remote_host}"
[[ "$remote_codex_host" != "-" ]] || remote_codex_host=""
if [[ -n "$remote_codex_host" && ( "$remote_codex_host" == -* || ! "$remote_codex_host" =~ '^[A-Za-z0-9._@-]+$' ) ]]; then
  print -u2 "Remote Codex SSH host contains unsupported characters."
  exit 1
fi

# Retain saved paths while disabled so enabling the source again is convenient.
remote_codex_root="${CODEX_REMOTE_ROOT:-}"
remote_codex_python="${CODEX_REMOTE_PYTHON:-}"
if [[ -n "$remote_codex_host" ]]; then
  read "entered_remote_root?Remote Codex data directory [$remote_codex_root]: "
  remote_codex_root="${entered_remote_root:-$remote_codex_root}"
  read "entered_remote_python?Remote Python path [$remote_codex_python]: "
  remote_codex_python="${entered_remote_python:-$remote_codex_python}"
  if [[ "$remote_codex_root" != /* || "$remote_codex_python" != /* || "$remote_codex_root" == *$'\n'* || "$remote_codex_python" == *$'\n'* ]]; then
    print -u2 "An enabled remote source requires absolute Codex and Python paths."
    exit 1
  fi
fi

default_cursor_state_db="${CURSOR_STATE_DB:-$user_root/Library/Application Support/Cursor/User/globalStorage/state.vscdb}"
read "cursor_state_db?Cursor account database [$default_cursor_state_db]: "
cursor_state_db="${cursor_state_db:-$default_cursor_state_db}"

default_refresh_minutes="${BEAVERMETER_REFRESH_MINUTES:-5}"
if [[ -f "$agent_path" ]]; then
  prior_interval="$(bm_run plistbuddy -c 'Print :StartInterval' "$agent_path" 2>/dev/null || true)"
  if [[ "$prior_interval" == <-> ]] && (( prior_interval >= 300 && prior_interval <= 86400 && prior_interval % 60 == 0 )); then
    default_refresh_minutes=$((prior_interval / 60))
  fi
fi
read "refresh_minutes?Refresh interval in minutes [$default_refresh_minutes]: "
refresh_minutes="${refresh_minutes:-$default_refresh_minutes}"
if [[ ! "$refresh_minutes" =~ '^[0-9]+$' ]] || (( refresh_minutes < 5 || refresh_minutes > 1440 )); then
  print -u2 "Refresh interval must be between 5 and 1440 minutes."
  exit 1
fi

export BEAVERMETER_DEVELOPMENT_TEAM="$team_id"
export BEAVERMETER_BUNDLE_PREFIX="$bundle_prefix"

signing_overrides=()
if [[ -z "$team_id" ]]; then
  signing_overrides=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
  print "No Apple signing identity selected; using local ad-hoc signing."
fi

# Reusing DerivedData keeps dependency builds incremental. Never unregister this
# copy after the installed bundle has been registered: WidgetKit shares its ID.
derived_data="${BEAVERMETER_DERIVED_DATA:-$project_dir/.build/install}"
derived_data="${derived_data:A}"
built_app="$derived_data/Build/Products/Release/$app_name"
if [[ "$built_app" == "$installed_app" ]]; then
  print -u2 "Build output must be separate from the installed application."
  exit 1
fi
mkdir -p "$derived_data"
cd "$project_dir"
bm_run xcodegen generate
DEVELOPER_DIR="$developer_dir" bm_run xcodebuild \
  -project BeaverMeter.xcodeproj \
  -scheme BeaverMeter \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=YES \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS="$(uname -m)" \
  "${signing_overrides[@]}" \
  build
bm_run codesign --verify --deep --strict "$built_app"

# No live services, registrations or settings are changed until all backups
# exist. Build/preflight failures therefore leave the running version alone.
rollback_dir=""
transaction_started=0
install_committed=0
trap bm_install_cleanup ZERR EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bm_prepare_transaction
transaction_started=1
bm_run launchctl bootout "$launch_domain/$agent_label" >/dev/null 2>&1 || true
bm_run launchctl bootout "$launch_domain/$legacy_agent_label" >/dev/null 2>&1 || true
bm_stop_applications

mkdir -p "$install_dir" "$user_root/Library/LaunchAgents"
rm -rf "$installed_app"
rm -f "$agent_path"
BEAVERMETER_USER_ROOT_OVERRIDE="$user_root" zsh "$project_dir/scripts/migrate_beavermeter_data.sh"
mkdir -p "$config_dir" "$log_dir"
chmod 700 "$config_dir"
/usr/bin/ditto "$built_app" "$installed_app"

{
  printf 'CODEX_ROOT=%q\n' "$codex_root"
  printf 'CODEX_REMOTE_SSH_HOST=%q\n' "$remote_codex_host"
  printf 'CODEX_REMOTE_ROOT=%q\n' "$remote_codex_root"
  printf 'CODEX_REMOTE_PYTHON=%q\n' "$remote_codex_python"
  printf 'CURSOR_STATE_DB=%q\n' "$cursor_state_db"
  printf 'BEAVERMETER_DEVELOPMENT_TEAM=%q\n' "$team_id"
  printf 'BEAVERMETER_BUNDLE_PREFIX=%q\n' "$bundle_prefix"
  printf 'BEAVERMETER_REFRESH_MINUTES=%q\n' "$refresh_minutes"
} > "$config_path"
chmod 600 "$config_path"

bm_run plistbuddy -c "Add :Label string $agent_label" "$agent_path"
bm_run plistbuddy -c "Add :ProgramArguments array" "$agent_path"
bm_run plistbuddy -c "Add :ProgramArguments:0 string /bin/zsh" "$agent_path"
bm_run plistbuddy -c "Add :ProgramArguments:1 string $installed_app/Contents/Resources/collect_beaver_meter.sh" "$agent_path"
bm_run plistbuddy -c "Add :RunAtLoad bool true" "$agent_path"
bm_run plistbuddy -c "Add :StartInterval integer $((refresh_minutes * 60))" "$agent_path"
bm_run plistbuddy -c "Add :StandardOutPath string $log_dir/refresh.out.log" "$agent_path"
bm_run plistbuddy -c "Add :StandardErrorPath string $log_dir/refresh.err.log" "$agent_path"

bm_unregister_app "$built_app"
bm_unregister_other_apps
bm_register_app "$installed_app"
"$installed_app/Contents/Resources/collect_beaver_meter.sh" "$snapshot_path" >/dev/null
schema_version="$(/usr/bin/plutil -extract schemaVersion raw -o - "$snapshot_path" 2>/dev/null || true)"
if [[ "$schema_version" != "5" ]]; then
  print -u2 "BeaverMeter did not produce a schema v5 snapshot."
  exit 1
fi
bm_run codesign --verify --deep --strict "$installed_app"
bm_run launchctl bootstrap "$launch_domain" "$agent_path"
bm_refresh_widget_services
bm_open_app "$installed_app"
install_committed=1

# Legacy files stay untouched until the new installation has been verified.
rm -rf "$legacy_app" "$legacy_config_dir" "$legacy_log_dir"
rm -f "$legacy_agent_path"

print
print "Installed: $installed_app"
print "Refresh interval: $refresh_minutes minutes"
print "Build cache: $derived_data"
if [[ -d "$rollback_dir/app" ]]; then
  print "BeaverMeter and its Widget were updated."
else
  print "Add BeaverMeter from the macOS Widget gallery."
fi
