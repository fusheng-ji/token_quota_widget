#!/bin/zsh
set -euo pipefail

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
