#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
fixtures="$project_dir/Tests/Fixtures"
collector="${1:-${CODEXWEEK_COLLECTOR:-/private/tmp/codexweek-derived/Build/Products/Debug/CodexWeekCollector}}"
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
  "$collector" --output "$snapshot" >/dev/null

jq -e '
  .schemaVersion == 3 and
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
' "$snapshot" >/dev/null

[[ "$(stat -f '%Lp' "$snapshot")" == "600" ]]
if rg -q 'accessToken|access_token|WorkosCursorSessionToken|owningUser|owningTeam|conversation' "$snapshot"; then
  print -u2 "Snapshot leaked a credential or private identifier."
  exit 1
fi

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
' "$snapshot" >/dev/null

print "Collector fixture tests passed."
