#!/bin/zsh
set -euo pipefail
setopt NO_BG_NICE

project_dir="${0:A:h:h}"
fixtures="$project_dir/Tests/Fixtures"
collector="${1:-${BEAVERMETER_COLLECTOR:-/private/tmp/beavermeter-derived/Build/Products/Debug/BeaverMeterCollector}}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cursor-codex-tests.XXXXXX")"

cleanup() {
  [[ -d "$test_dir" ]] && rm -rf "$test_dir"
}
trap cleanup EXIT

if [[ ! -x "$collector" ]]; then
  print -u2 "Collector executable not found: $collector"
  exit 1
fi

snapshot="$test_dir/snapshot.json"
CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
CODEX_TOKEN_FIXTURE="$fixtures/codex-token-totals.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
  "$collector" --output "$snapshot" >/dev/null

jq -e '
  .schemaVersion == 5 and
  .codexTokens.status == "ready" and
  .codexTokens.value.totalTokens == 1000 and
  .codexTokens.value.inputTokens == 900 and
  .codexTokens.value.outputTokens == 100 and
  .cursorCosts.status == "ready" and
  .cursorCosts.value.todayCostUSD == 0.15 and
  (.cursorCosts.value.recentEvents | length) == 3 and
  .cursorCosts.value.recentEvents[0].costUSD == 0.03 and
  .cursorCosts.value.recentEvents[0].tokenCount == 1630 and
  .cursorQuota.value.used == 42.5 and
  .cursorQuota.value.limit == 100 and
  .cursorQuota.value.remaining == 57.5 and
  .codexQuota.value.remainingPercent == 63
  and .deepseekUsage.status == "ready"
  and .deepseekUsage.value.monthTokens == 1400000
  and .deepseekUsage.value.monthRequests == 16
  and .deepseekUsage.value.monthCosts[0].amount == 1.24
  and .deepseekUsage.value.balances[0].amount == 18.76
  and (.deepseekUsage.value | has("models") | not)
' "$snapshot" >/dev/null

[[ "$(stat -f '%Lp' "$snapshot")" == "600" ]]
if rg -q 'accessToken|access_token|WorkosCursorSessionToken|owningUser|owningTeam|conversation|userToken|Bearer|DEEPSEEK_PLATFORM_TOKEN' "$snapshot"; then
  print -u2 "Snapshot leaked a credential or private identifier."
  exit 1
fi

# A live Codex rollout keeps growing while a task is active. Verify that a
# second refresh consumes the newly appended token-count tail instead of
# returning the cached prefix forever.
today_path="$(date '+%Y/%m/%d')"
timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
codex_home="$test_dir/codex-home"
token_cache="$test_dir/codex-token-cache"
session_dir="$codex_home/sessions/$today_path"
session_file="$session_dir/rollout-live-growth.jsonl"
mkdir -p "$session_dir"
print -rl -- \
  "{\"type\":\"session_meta\",\"timestamp\":\"$timestamp\",\"payload\":{\"id\":\"live-growth\",\"session_id\":\"live-growth\",\"timestamp\":\"$timestamp\"}}" \
  "{\"type\":\"turn_context\",\"timestamp\":\"$timestamp\",\"payload\":{\"model\":\"openai/gpt-5.4\"}}" \
  "{\"type\":\"event_msg\",\"timestamp\":\"$timestamp\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":20,\"output_tokens\":10},\"total_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":20,\"output_tokens\":10}}}}" \
  > "$session_file"

CODEX_HOME="$codex_home" \
CODEX_TOKEN_CACHE_ROOT="$token_cache" \
CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
  "$collector" --output "$snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 110' "$snapshot" >/dev/null

print -r -- \
  "{\"type\":\"event_msg\",\"timestamp\":\"$timestamp\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":75,\"cached_input_tokens\":10,\"output_tokens\":15},\"total_token_usage\":{\"input_tokens\":175,\"cached_input_tokens\":30,\"output_tokens\":25}}}}" \
  >> "$session_file"

CODEX_HOME="$codex_home" \
CODEX_TOKEN_CACHE_ROOT="$token_cache" \
CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
  "$collector" --output "$snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 200' "$snapshot" >/dev/null

# Codex Desktop can keep appending to a rollout under the task's original date
# directory after midnight. Its new token_usage_record entries are authoritative
# per-response deltas and must be counted even when CodexBar cannot materialize
# the accompanying legacy token_count events into today's report.
cross_day_home="$test_dir/cross-day-codex-home"
cross_day_cache="$test_dir/cross-day-token-cache"
yesterday_path="$(date -v-1d '+%Y/%m/%d')"
cross_day_dir="$cross_day_home/sessions/$yesterday_path"
cross_day_file="$cross_day_dir/rollout-cross-day.jsonl"
mkdir -p "$cross_day_dir"
print -rl -- \
  "{\"type\":\"session_meta\",\"timestamp\":\"$timestamp\",\"payload\":{\"id\":\"cross-day\",\"session_id\":\"cross-day\",\"timestamp\":\"$timestamp\"}}" \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"response-one\",\"session_id\":\"cross-day\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":20,\"output_tokens\":10,\"reasoning_output_tokens\":3,\"total_tokens\":110}}}" \
  > "$cross_day_file"

CODEX_HOME="$cross_day_home" \
CODEX_TOKEN_CACHE_ROOT="$cross_day_cache" \
CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
  "$collector" --output "$snapshot" >/dev/null
jq -e '
  .codexTokens.status == "ready" and
  .codexTokens.value.totalTokens == 110 and
  .codexTokens.value.inputTokens == 100 and
  .codexTokens.value.cachedInputTokens == 20 and
  .codexTokens.value.outputTokens == 10 and
  .codexTokens.value.reasoningTokens == 3 and
  .codexTokens.value.sessionCount == 1
' "$snapshot" >/dev/null

print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"response-two\",\"session_id\":\"cross-day\",\"usage\":{\"input_tokens\":75,\"cached_input_tokens\":10,\"output_tokens\":15,\"reasoning_output_tokens\":2,\"total_tokens\":90}}}" \
  >> "$cross_day_file"

CODEX_HOME="$cross_day_home" \
CODEX_TOKEN_CACHE_ROOT="$cross_day_cache" \
CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
  "$collector" --output "$snapshot" >/dev/null
jq -e '
  .codexTokens.value.totalTokens == 200 and
  .codexTokens.value.inputTokens == 175 and
  .codexTokens.value.cachedInputTokens == 30 and
  .codexTokens.value.outputTokens == 25 and
  .codexTokens.value.reasoningTokens == 5
' "$snapshot" >/dev/null

# The live App refresh updates only Codex. It must preserve the other provider
# payloads byte-for-byte and avoid rewriting the snapshot when no usage changed.
live_home="$test_dir/live-only-codex-home"
live_dir="$live_home/sessions/$(date -v-9d '+%Y/%m/%d')"
live_file="$live_dir/rollout-live-only.jsonl"
live_snapshot="$test_dir/live-only-snapshot.json"
live_cache="$test_dir/beaver-meter-codex-scan-v2.json"
mkdir -p "$live_dir"

CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
CODEX_TOKEN_FIXTURE="$fixtures/codex-token-totals.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
  "$collector" --output "$live_snapshot" >/dev/null
jq '
  .codexTokens.value = {
    totalTokens: 0,
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0,
    sessionCount: 0
  }
' "$live_snapshot" > "$test_dir/live-zero-snapshot.json"
mv "$test_dir/live-zero-snapshot.json" "$live_snapshot"
jq '{cursorCosts,cursorQuota,codexQuota,deepseekUsage}' "$live_snapshot" > "$test_dir/providers-before.json"

print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"private-response-one\",\"session_id\":\"private-session\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":20,\"output_tokens\":10,\"reasoning_output_tokens\":3,\"total_tokens\":110}}}" \
  > "$live_file"
CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 110 and .codexTokens.value.sessionCount == 1' "$live_snapshot" >/dev/null
jq '{cursorCosts,cursorQuota,codexQuota,deepseekUsage}' "$live_snapshot" > "$test_dir/providers-after.json"
cmp "$test_dir/providers-before.json" "$test_dir/providers-after.json"
[[ "$(stat -f '%Lp' "$live_cache")" == "600" ]]
if rg -q 'private-response|private-session|rollout-live-only|codex-home' "$live_cache"; then
  print -u2 "Codex scan cache leaked an unhashed private identifier."
  exit 1
fi

snapshot_checksum="$(shasum -a 256 "$live_snapshot" | cut -d' ' -f1)"
CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
[[ "$(shasum -a 256 "$live_snapshot" | cut -d' ' -f1)" == "$snapshot_checksum" ]]

# Repeated response IDs are ignored even if the appended copy reports different totals.
print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"private-response-one\",\"session_id\":\"private-session\",\"usage\":{\"input_tokens\":900,\"cached_input_tokens\":800,\"output_tokens\":90,\"reasoning_output_tokens\":30,\"total_tokens\":990}}}" \
  >> "$live_file"
CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 110' "$live_snapshot" >/dev/null

print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"private-response-two\",\"session_id\":\"private-session\",\"usage\":{\"input_tokens\":75,\"cached_input_tokens\":10,\"output_tokens\":15,\"reasoning_output_tokens\":2,\"total_tokens\":90}}}" \
  >> "$live_file"
CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 200' "$live_snapshot" >/dev/null

# The bundled shell wrapper forwards Codex-only mode and the configured root.
print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"through-wrapper\",\"session_id\":\"private-session\",\"usage\":{\"input_tokens\":8,\"cached_input_tokens\":0,\"output_tokens\":2,\"reasoning_output_tokens\":0,\"total_tokens\":10}}}" \
  >> "$live_file"
BEAVER_METER_CONFIG=/dev/null \
BEAVERMETER_COLLECTOR="$collector" \
CODEX_ROOT="$live_home" \
  zsh "$project_dir/scripts/collect_beaver_meter.sh" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 210' "$live_snapshot" >/dev/null
[[ "$(stat -f '%Lp' "$live_snapshot.lock")" == "600" ]]

# Optional remote records are merged with local records by response hash. The
# remote protocol contains only hashed identifiers and numeric usage fields.
remote_home="$test_dir/remote-merge-home"
remote_dir="$remote_home/archived_sessions/old-task"
remote_local_file="$remote_dir/rollout-local.jsonl"
remote_snapshot="$test_dir/remote-merge-snapshot.json"
remote_fixture="$test_dir/remote-response.json"
mkdir -p "$remote_dir"
shared_hash="$(printf %s 'shared-response' | shasum -a 256 | cut -d' ' -f1)"
shared_session_hash="$(printf %s 'shared-session' | shasum -a 256 | cut -d' ' -f1)"
unique_hash="$(printf %s 'remote-unique' | shasum -a 256 | cut -d' ' -f1)"
unique_session_hash="$(printf %s 'remote-session' | shasum -a 256 | cut -d' ' -f1)"
epoch_now="$(date '+%s')"
print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"shared-response\",\"session_id\":\"shared-session\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":20,\"output_tokens\":10,\"reasoning_output_tokens\":3}}}" \
  > "$remote_local_file"
cat > "$remote_fixture" <<EOF
{"activeFiles":["remote-file"],"files":{"remote-file":{"offset":500,"reset":false,"records":[{"responseHash":"$shared_hash","sessionHash":"$shared_session_hash","timestamp":$epoch_now,"inputTokens":900,"cachedInputTokens":800,"outputTokens":90,"reasoningTokens":30},{"responseHash":"$unique_hash","sessionHash":"$unique_session_hash","timestamp":$epoch_now,"inputTokens":200,"cachedInputTokens":50,"outputTokens":20,"reasoningTokens":4}]}}}
EOF
CODEX_HOME="$remote_home" \
CODEX_REMOTE_SSH_HOST="fixture-host" \
CODEX_REMOTE_ROOT="/fixture/codex" \
CODEX_REMOTE_PYTHON="/fixture/python3" \
CODEX_REMOTE_RESPONSE_FIXTURE="$remote_fixture" \
  "$collector" --codex-only --output "$remote_snapshot" >/dev/null
jq -e '
  .codexTokens.status == "ready" and
  .codexTokens.value.totalTokens == 330 and
  .codexTokens.value.inputTokens == 300 and
  .codexTokens.value.outputTokens == 30 and
  .codexTokens.value.sessionCount == 2
' "$remote_snapshot" >/dev/null
remote_cache="$test_dir/beaver-meter-codex-remote-scan-v1.json"
[[ "$(stat -f '%Lp' "$remote_cache")" == "600" ]]
if rg -q 'shared-response|shared-session|remote-unique|remote-session|fixture/codex' "$remote_cache"; then
  print -u2 "Remote Codex cache leaked an unhashed identifier."
  exit 1
fi

# A failed remote refresh retains the current-day remote cache and marks the
# otherwise fresh local total as incomplete. A subsequent success clears it.
CODEX_HOME="$remote_home" \
CODEX_REMOTE_SSH_HOST="fixture-host" \
CODEX_REMOTE_ROOT="/fixture/codex" \
CODEX_REMOTE_PYTHON="/fixture/python3" \
CODEX_REMOTE_RESPONSE_FIXTURE="$test_dir/missing-remote-response.json" \
  "$collector" --codex-only --output "$remote_snapshot" >/dev/null
jq -e '
  .codexTokens.status == "stale" and
  .codexTokens.value.totalTokens == 330 and
  (.codexTokens.message | contains("last remote reading"))
' "$remote_snapshot" >/dev/null
print -r -- '{"activeFiles":["remote-file"],"files":{}}' > "$remote_fixture"
CODEX_HOME="$remote_home" \
CODEX_REMOTE_SSH_HOST="fixture-host" \
CODEX_REMOTE_ROOT="/fixture/codex" \
CODEX_REMOTE_PYTHON="/fixture/python3" \
CODEX_REMOTE_RESPONSE_FIXTURE="$remote_fixture" \
  "$collector" --codex-only --output "$remote_snapshot" >/dev/null
jq -e '.codexTokens.status == "ready" and .codexTokens.value.totalTokens == 330' "$remote_snapshot" >/dev/null

# A truncated rollout and a corrupt cache both fall back to a full rescan
# without regressing an already measured same-day total.
print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"replacement\",\"session_id\":\"replacement-session\",\"usage\":{\"input_tokens\":40,\"cached_input_tokens\":5,\"output_tokens\":10,\"reasoning_output_tokens\":1,\"total_tokens\":50}}}" \
  > "$live_file"
CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 210' "$live_snapshot" >/dev/null
print -r -- '{not-valid-json' > "$live_cache"
print -r -- \
  "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"after-corruption\",\"session_id\":\"replacement-session\",\"usage\":{\"input_tokens\":8,\"cached_input_tokens\":0,\"output_tokens\":2,\"reasoning_output_tokens\":0,\"total_tokens\":10}}}" \
  >> "$live_file"
CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 210' "$live_snapshot" >/dev/null

# Full and Codex-only processes share the snapshot lock, so concurrent writes
# always leave a valid schema and never erase the other provider values.
for index in 1 2 3; do
  print -r -- \
    "{\"type\":\"token_usage_record\",\"timestamp\":\"$timestamp\",\"payload\":{\"response_id\":\"concurrent-$index\",\"session_id\":\"replacement-session\",\"usage\":{\"input_tokens\":1,\"cached_input_tokens\":0,\"output_tokens\":1,\"reasoning_output_tokens\":0,\"total_tokens\":2}}}" \
    >> "$live_file"
  CODEX_HOME="$live_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null &
  codex_pid=$!
  CURSOR_EVENTS_FIXTURE="$fixtures/cursor-events-v3.json" \
  CURSOR_SUMMARY_FIXTURE="$fixtures/cursor-summary-v3.json" \
  CODEX_TOKEN_FIXTURE="$fixtures/codex-token-totals.json" \
  CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
  DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
  DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage.json" \
    "$collector" --output "$live_snapshot" >/dev/null &
  full_pid=$!
  wait "$codex_pid" "$full_pid"
  jq -e '
    .schemaVersion == 5 and
    .cursorCosts.status == "ready" and
    .cursorQuota.status == "ready" and
    .codexQuota.status == "ready" and
    .deepseekUsage.status == "ready"
  ' "$live_snapshot" >/dev/null
done

# A new local day with no completed responses clears yesterday's total.
empty_home="$test_dir/empty-next-day-home"
mkdir -p "$empty_home/sessions"
jq '.dayStart = "2000-01-01T00:00:00Z"' "$live_cache" > "$test_dir/old-day-cache.json"
mv "$test_dir/old-day-cache.json" "$live_cache"
jq '
  .generatedAt = "2000-01-01T00:00:00Z" |
  .codexTokens.measuredAt = "2000-01-01T00:00:00Z" |
  .codexTokens.lastAttemptAt = "2000-01-01T00:00:00Z"
' "$live_snapshot" > "$test_dir/old-day-snapshot.json"
mv "$test_dir/old-day-snapshot.json" "$live_snapshot"
CODEX_HOME="$empty_home" "$collector" --codex-only --output "$live_snapshot" >/dev/null
jq -e '.codexTokens.value.totalTokens == 0 and .codexTokens.value.sessionCount == 0' "$live_snapshot" >/dev/null

CURSOR_STATE_DB="$test_dir/missing-cursor.vscdb" \
CODEX_TOKEN_FIXTURE="$fixtures/codex-token-totals.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
  "$collector" --output "$snapshot" >/dev/null

jq -e '
  .codexTokens.status == "ready" and
  .codexQuota.status == "ready" and
  .cursorCosts.status == "stale" and
  .cursorCosts.source == "cache" and
  .cursorCosts.value.todayCostUSD == 0.15 and
  .cursorQuota.status == "stale"
  and .deepseekUsage.status == "stale"
  and .deepseekUsage.source == "cache"
  and .deepseekUsage.value.monthTokens == 1400000
' "$snapshot" >/dev/null

CURSOR_STATE_DB="$test_dir/missing-cursor.vscdb" \
CODEX_TOKEN_FIXTURE="$fixtures/codex-token-totals.json" \
CODEX_USAGE_FIXTURE="$fixtures/codex-pro-week.json" \
DEEPSEEK_SUMMARY_FIXTURE="$fixtures/deepseek-summary.json" \
DEEPSEEK_USAGE_FIXTURE="$fixtures/deepseek-usage-invalid.json" \
  "$collector" --output "$snapshot" >/dev/null

jq -e '
  .codexTokens.status == "ready" and
  .codexQuota.status == "ready" and
  .deepseekUsage.status == "stale" and
  .deepseekUsage.source == "cache" and
  .deepseekUsage.value.monthTokens == 1400000 and
  (.deepseekUsage.message | contains("changed format"))
' "$snapshot" >/dev/null

print "Collector fixture tests passed."
