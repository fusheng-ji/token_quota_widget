#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beavermeter-install-tests.XXXXXX")"
cleanup() {
  local exit_code=$?
  if (( exit_code )) && [[ -n "${case_root:-}" && -f "$case_root/output.log" ]]; then
    print -u2 "Installer output for failed test:"
    cat "$case_root/output.log" >&2
  fi
  rm -rf "$test_root"
  return "$exit_code"
}
trap cleanup EXIT
mock_dir="$test_root/commands"
mkdir -p "$mock_dir"
for command_name in xcodegen xcodebuild codesign plistbuddy launchctl pgrep pkill lsregister pluginkit killall open; do
  ln -s "$project_dir/Tests/Support/install_command_stub.sh" "$mock_dir/$command_name"
done

seed="$test_root/seed"
seed_data="$seed/Library/Application Support/BeaverMeter"
seed_app="$seed/Applications/BeaverMeter.app"
mkdir -p "$seed_data" "$seed_app/Contents/PlugIns/BeaverMeterWidgetExtension.appex" "$seed/Library/LaunchAgents"
print -r -- old > "$seed_app/version-marker"
print -r -- 'CODEX_ROOT=/custom/codex' 'CODEX_REMOTE_SSH_HOST=' 'CODEX_REMOTE_ROOT=/saved/codex' 'CODEX_REMOTE_PYTHON=/saved/python3' 'CURSOR_STATE_DB=/custom/cursor.db' > "$seed_data/config.env"
print -r -- original-test-credential > "$seed_data/deepseek-platform-token"
print -r -- '{"schemaVersion":5,"original":true}' > "$seed_data/beaver-meter-snapshot.json"
chmod 700 "$seed_data"
chmod 600 "$seed_data/"*
/usr/libexec/PlistBuddy -c 'Add :Label string io.github.beavermeter.refresh' "$seed/Library/LaunchAgents/io.github.beavermeter.refresh.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Add :StartInterval integer 600' "$seed/Library/LaunchAgents/io.github.beavermeter.refresh.plist"

prepare_case() {
  case_root="$test_root/$1"
  state="$case_root/state"
  task_user="$case_root/user"
  mkdir -p "$state" "$task_user"
  if [[ "${2:-existing}" == existing ]]; then
    /usr/bin/ditto "$seed" "$task_user"
    touch "$state/io.github.beavermeter.refresh.loaded" "$state/BeaverMeter.running"
  fi
  task_data="$task_user/Library/Application Support/BeaverMeter"
  task_app="$task_user/Applications/BeaverMeter.app"
  derived="$case_root/derived"
  # Disabled SSH asks six questions; extra blank lines also cover enabled SSH.
  printf '\ncom.test\n\n\n\n\n\n\n' > "$case_root/answers"
}

run_installer() {
  env -i PATH="$PATH" HOME="$HOME" USER=installer-test TMPDIR="$test_root/" \
    BEAVERMETER_USER_ROOT_OVERRIDE="$task_user" \
    BEAVERMETER_SYSTEM_COMMANDS="$mock_dir" \
    BEAVERMETER_DERIVED_DATA="$derived" \
    BM_TEST_STATE="$state" BM_TEST_PROJECT="$project_dir" BM_TEST_FAIL="${1:-}" \
    zsh "$project_dir/scripts/install.sh" < "$case_root/answers" > "$case_root/output.log" 2>&1
}

assert_original_installation() {
  diff -r "$seed_app" "$task_app"
  diff -r "$seed_data" "$task_data"
  diff -r "$seed/Library/LaunchAgents" "$task_user/Library/LaunchAgents"
  [[ ! -e "$task_user/Library/Logs/BeaverMeter" ]]
  [[ -f "$state/io.github.beavermeter.refresh.loaded" ]]
  [[ -f "$state/BeaverMeter.running" ]]
  [[ "$(stat -f '%Lp' "$task_data/deepseek-platform-token")" == 600 ]]
}

# Build/signing preflight failures must never touch the currently running app.
for failure in build preflight; do
  prepare_case "$failure"
  if run_installer "$failure"; then print -u2 "Expected $failure to fail"; exit 1; fi
  assert_original_installation
  if rg -q '^(launchctl|pkill|killall|lsregister|pluginkit|open) ' "$state/commands.log"; then
    print -u2 "A preflight failure mutated the running installation."
    exit 1
  fi
done

# Restore configuration, snapshots, caches and credentials after replacement,
# including a failure after the new LaunchAgent starts being installed.
for failure in collector verification bootstrap; do
  prepare_case "$failure"
  if run_installer "$failure"; then print -u2 "Expected $failure to fail"; exit 1; fi
  assert_original_installation
  rg -q '^pluginkit -a .*/Applications/BeaverMeter.app/Contents/PlugIns/' "$state/commands.log"
  [[ ! -e "$task_data/new-scan-cache.json" ]]
done

# A failed first installation removes only its new state; legacy data survives.
prepare_case first-failure fresh
legacy_data="$task_user/Library/Application Support/CodexWeek"
mkdir -p "$legacy_data"
print -r -- legacy-test-credential > "$legacy_data/deepseek-platform-token"
if run_installer collector; then print -u2 'Expected first installation to fail'; exit 1; fi
[[ ! -e "$task_app" && ! -e "$task_data" ]]
[[ "$(<"$legacy_data/deepseek-platform-token")" == legacy-test-credential ]]

# Upgrades preserve an explicit disabled host, saved paths and refresh interval.
prepare_case upgrade
run_installer
(
  source "$task_data/config.env"
  [[ -z "$CODEX_REMOTE_SSH_HOST" ]]
  [[ "$CODEX_REMOTE_ROOT" == /saved/codex && "$CODEX_REMOTE_PYTHON" == /saved/python3 ]]
  [[ "$BEAVERMETER_REFRESH_MINUTES" == 10 ]]
)
[[ "$(<"$task_data/deepseek-platform-token")" == original-test-credential ]]
[[ "$(<"$task_app/version-marker")" == new ]]
[[ -f "$state/io.github.beavermeter.refresh.loaded" && -f "$state/BeaverMeter.running" ]]
[[ -d "$derived/Build/Products/Release/BeaverMeter.app" ]]
# Cleanup must not unregister the build copy after the installed widget is live.
last_registration="$(rg '^(lsregister|pluginkit) ' "$state/commands.log" | tail -1)"
[[ "$last_registration" == 'lsregister -gc' ]]

prepare_case fresh fresh
run_installer
(
  source "$task_data/config.env"
  [[ -z "$CODEX_REMOTE_SSH_HOST" && -z "$CODEX_REMOTE_ROOT" && -z "$CODEX_REMOTE_PYTHON" ]]
)

prepare_case enabled
print -r -- 'CODEX_REMOTE_SSH_HOST=remote-box' >> "$task_data/config.env"
run_installer
(
  source "$task_data/config.env"
  [[ "$CODEX_REMOTE_SSH_HOST" == remote-box && "$CODEX_REMOTE_ROOT" == /saved/codex && "$CODEX_REMOTE_PYTHON" == /saved/python3 ]]
)

# Repair and uninstall use the same isolated lifecycle operations.
env -i PATH="$PATH" HOME="$HOME" BEAVERMETER_USER_ROOT_OVERRIDE="$task_user" \
  BEAVERMETER_SYSTEM_COMMANDS="$mock_dir" BM_TEST_STATE="$state" \
  zsh "$project_dir/scripts/repair_widget.sh" >/dev/null
[[ -f "$state/BeaverMeter.running" ]]
env -i PATH="$PATH" HOME="$HOME" BEAVERMETER_USER_ROOT_OVERRIDE="$task_user" \
  BEAVERMETER_SYSTEM_COMMANDS="$mock_dir" BM_TEST_STATE="$state" \
  zsh "$project_dir/scripts/uninstall.sh" >/dev/null
[[ ! -d "$task_app" && ! -d "$task_data" && ! -f "$state/BeaverMeter.running" ]]
[[ -d "$task_user/.Trash" ]]

print "BeaverMeter installation lifecycle tests passed."
