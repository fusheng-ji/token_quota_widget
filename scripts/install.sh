#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_name="CodexWeek.app"
install_dir="$HOME/Applications"
installed_app="$install_dir/$app_name"
agent_label="io.github.codexweek.refresh"
agent_path="$HOME/Library/LaunchAgents/$agent_label.plist"
config_dir="$HOME/Library/Application Support/CodexWeek"
config_path="$config_dir/config.env"
log_dir="$HOME/Library/Logs/CodexWeek"
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

print "Cursor + Codex Widget setup"
print "No Admin API key is required. Existing local sign-in sessions are used only for official usage endpoints."
print

read "team_id?Apple Developer Team ID (leave blank for local-only signing): "
if [[ -n "$team_id" && ! "$team_id" =~ '^[A-Z0-9]{10}$' ]]; then
  print -u2 "Team ID must be blank or the 10-character value shown in Xcode → Settings → Accounts."
  exit 1
fi

default_prefix="com.${USER//[^A-Za-z0-9]/}"
read "bundle_prefix?Unique bundle prefix [$default_prefix]: "
bundle_prefix="${bundle_prefix:-$default_prefix}"
if [[ ! "$bundle_prefix" =~ '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$' ]]; then
  print -u2 "Bundle prefix must look like com.yourname."
  exit 1
fi

default_codex_root="$HOME/.codex"
read "codex_root?Codex data directory [$default_codex_root]: "
codex_root="${codex_root:-$default_codex_root}"

default_cursor_state_db="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
read "cursor_state_db?Cursor account database [$default_cursor_state_db]: "
cursor_state_db="${cursor_state_db:-$default_cursor_state_db}"

read "refresh_minutes?Refresh interval in minutes [5]: "
refresh_minutes="${refresh_minutes:-5}"
if [[ ! "$refresh_minutes" =~ '^[0-9]+$' ]] || (( refresh_minutes < 5 || refresh_minutes > 1440 )); then
  print -u2 "Refresh interval must be between 5 and 1440 minutes."
  exit 1
fi

export CODEXWEEK_DEVELOPMENT_TEAM="$team_id"
export CODEXWEEK_BUNDLE_PREFIX="$bundle_prefix"

signing_overrides=()
if [[ -z "$team_id" ]]; then
  signing_overrides=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
  )
  print "No Apple signing identity selected; using local ad-hoc signing."
fi

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/codexweek-build.XXXXXX")"
built_app="$derived_data/Build/Products/Release/$app_name"

cleanup() {
  if [[ -d "$built_app" ]]; then
    "$lsregister" -u "$built_app" >/dev/null 2>&1 || true
    pluginkit -r "$built_app/Contents/PlugIns/CodexWeekWidgetExtension.appex" >/dev/null 2>&1 || true
  fi
  [[ -n "$derived_data" && -d "$derived_data" ]] && rm -rf "$derived_data"
}
trap cleanup EXIT

cd "$project_dir"
xcodegen generate
DEVELOPER_DIR="$developer_dir" xcodebuild \
  -project CodexWeek.xcodeproj \
  -scheme CodexWeek \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=YES \
  "${signing_overrides[@]}" \
  build

mkdir -p "$install_dir" "$config_dir" "$log_dir" "$HOME/Library/LaunchAgents"

if [[ -d "$installed_app" ]]; then
  backup_path="$HOME/.Trash/CodexWeek-backup-$(date '+%Y%m%d-%H%M%S').app"
  mv "$installed_app" "$backup_path"
  print "Previous app moved to: $backup_path"
fi
ditto "$built_app" "$installed_app"

{
  printf 'CODEX_ROOT=%q\n' "$codex_root"
  printf 'CURSOR_STATE_DB=%q\n' "$cursor_state_db"
} > "$config_path"
chmod 600 "$config_path"

launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true
rm -f "$agent_path"
/usr/libexec/PlistBuddy -c "Add :Label string $agent_label" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string /bin/zsh" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string $installed_app/Contents/Resources/collect_codex_week.sh" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :StartInterval integer $((refresh_minutes * 60))" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $log_dir/refresh.out.log" "$agent_path"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $log_dir/refresh.err.log" "$agent_path"

"$lsregister" -f -R -trusted "$installed_app"
pluginkit -a "$installed_app/Contents/PlugIns/CodexWeekWidgetExtension.appex"
launchctl bootstrap "gui/$(id -u)" "$agent_path"
launchctl kickstart -k "gui/$(id -u)/$agent_label"

codesign --verify --deep --strict "$installed_app"
open "$installed_app"

print
print "Installed: $installed_app"
print "Refresh interval: $refresh_minutes minutes"
print "Next: right-click the desktop → Edit Widgets → search for Cursor + Codex."
