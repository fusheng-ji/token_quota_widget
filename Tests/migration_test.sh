#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/beavermeter-migration-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

legacy_dir="$test_root/Library/Application Support/CodexWeek"
new_dir="$test_root/Library/Application Support/BeaverMeter"
mkdir -p "$legacy_dir"

printf 'CODEX_ROOT=/custom/codex\nCURSOR_STATE_DB=/custom/cursor.db\n' > "$legacy_dir/config.env"
printf 'legacy-deepseek-token\n' > "$legacy_dir/deepseek-platform-token"
printf '{"schemaVersion":5}\n' > "$legacy_dir/codex-week-snapshot.json"
chmod 644 "$legacy_dir/config.env" "$legacy_dir/deepseek-platform-token" "$legacy_dir/codex-week-snapshot.json"

BEAVERMETER_USER_ROOT_OVERRIDE="$test_root" zsh "$repo_dir/scripts/migrate_beavermeter_data.sh" >/dev/null

[[ "$(cat "$new_dir/config.env")" == $'CODEX_ROOT=/custom/codex\nCURSOR_STATE_DB=/custom/cursor.db' ]]
[[ "$(cat "$new_dir/deepseek-platform-token")" == "legacy-deepseek-token" ]]
[[ "$(/usr/bin/plutil -extract schemaVersion raw -o - "$new_dir/beaver-meter-snapshot.json")" == "5" ]]
[[ "$(stat -f '%Lp' "$new_dir")" == "700" ]]
for private_file in config.env deepseek-platform-token beaver-meter-snapshot.json; do
  [[ "$(stat -f '%Lp' "$new_dir/$private_file")" == "600" ]]
done

printf 'new-token-wins\n' > "$new_dir/deepseek-platform-token"
chmod 600 "$new_dir/deepseek-platform-token"
BEAVERMETER_USER_ROOT_OVERRIDE="$test_root" zsh "$repo_dir/scripts/migrate_beavermeter_data.sh" >/dev/null
[[ "$(cat "$new_dir/deepseek-platform-token")" == "new-token-wins" ]]
[[ -f "$legacy_dir/deepseek-platform-token" ]]

second_root="$test_root/invalid-snapshot"
second_legacy="$second_root/Library/Application Support/CodexWeek"
mkdir -p "$second_legacy"
printf '{"schemaVersion":4}\n' > "$second_legacy/codex-week-snapshot.json"
BEAVERMETER_USER_ROOT_OVERRIDE="$second_root" zsh "$repo_dir/scripts/migrate_beavermeter_data.sh" >/dev/null
[[ ! -e "$second_root/Library/Application Support/BeaverMeter/beaver-meter-snapshot.json" ]]
[[ -f "$second_legacy/codex-week-snapshot.json" ]]

print "BeaverMeter migration tests passed."
