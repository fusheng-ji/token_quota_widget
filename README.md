# AI Token Quota Widget

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 5.0 / 6.0](https://img.shields.io/badge/Swift-5.0%20%2F%206.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org/)
[![Version 4.3](https://img.shields.io/badge/version-4.3-4C7CF3?style=flat-square)](https://github.com/fusheng-ji/token_quota_widget)
[![MIT License](https://img.shields.io/badge/license-MIT-2EA44F?style=flat-square)](LICENSE)

AI Token Quota Widget is a native macOS menu-bar utility and WidgetKit
extension that keeps Codex token activity and account quota alongside Cursor
model-call costs and monthly allowance. The menu-bar popover also reads the
current month's DeepSeek API tokens, requests, model costs and account balance,
so routine usage checks do not require opening the Dashboard.

The installed app and Widget use the public name `AI Token Quota`. Internal
`CodexWeek` target names, bundle IDs, the app path, LaunchAgent label and
snapshot path remain unchanged so existing installations upgrade in place.

## Interface

The menu bar shows Codex tokens, Cursor's latest actual charge and DeepSeek's
wallet balance in one compact line. Its popover adds Codex
input, cached input, output and reasoning totals; Cursor's daily actual charge;
and the latest 20 model calls with time, model, optional token count and charge.
The DeepSeek section emphasizes wallet balance, with current-month cost, tokens,
requests and an optional per-model breakdown.

The Widget has no overall title and adapts three provider panels to each family:

| Family | Layout |
| --- | --- |
| Small | Three compact Codex, Cursor and DeepSeek rows |
| Medium | Codex/Cursor side by side, DeepSeek spanning the bottom row |
| Large | 2×2 layout with DeepSeek spanning the bottom row |
| Extra Large | Large layout plus real model details when available |

<table>
  <tr>
    <th colspan="2">Menu-bar popover</th>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <img src="screenshots/menu-popover.png" alt="AI Token Quota Widget menu-bar popover with Demo data" width="390">
    </td>
  </tr>
  <tr>
    <th>Small Widget</th>
    <th>Medium Widget</th>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/widget-small.png" alt="AI Token Quota Widget Small layout with Demo data" width="174">
    </td>
    <td align="center">
      <img src="screenshots/widget-medium.png" alt="AI Token Quota Widget Medium layout with Demo data" width="352">
    </td>
  </tr>
  <tr>
    <th>Large Widget</th>
    <th>Extra Large Widget</th>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/widget-large.png" alt="AI Token Quota Widget Large layout with Demo data" width="352">
    </td>
    <td align="center">
      <img src="screenshots/widget-extra-large.png" alt="AI Token Quota Widget Extra Large layout with Demo data" width="430">
    </td>
  </tr>
</table>

Every image above is generated from the bundled Preview snapshot and visibly
marked as `Demo`. No screenshot contains live account values or personal Cursor
usage.

Codex and Cursor panels include a remaining value, reset countdown and progress
line. Codex is teal and Cursor is indigo; values below 50% turn amber and values
below 20% turn red. DeepSeek uses blue and shows its real wallet balance plus
monthly activity. DeepSeek does not publish a quota limit or reset time, so the
Widget deliberately does not invent a percentage or progress bar. Numeric
values and status text remain visible, and stale, signed-out and error states
are called out explicitly.

## Data sources and semantics

### Codex tokens

The bundled collector uses
[CodexBarCore](https://github.com/steipete/CodexBar/) pinned to commit
[`5d7c1f29fd11ecbf697b3532340f75b25319f811`](https://github.com/steipete/CodexBar/commit/5d7c1f29fd11ecbf697b3532340f75b25319f811).
Its local scanner aggregates the current local day across `~/.codex/sessions`,
including compressed sessions, duplicate events and file boundaries.

The displayed total is `input + output`. Cached input is a subset of input and
reasoning is a subset of output, so those counters are details and are not
added a second time.

### Cursor call costs and Monthly usage

The collector reads Cursor's existing local sign-in token from `state.vscdb`,
keeps it in process memory, and requests the same official Dashboard data used
by [cursor.com/dashboard/usage](https://cursor.com/dashboard/usage):

```text
https://cursor.com/api/dashboard/get-filtered-usage-events
https://cursor.com/api/usage-summary
```

Each call uses `chargedCents`, the amount actually deducted by Cursor. It does
not substitute `tokenUsage.totalCents`, which is the model provider's list
price. Calls charged at `$0.00` remain visible. If an otherwise valid call has
no valid actual charge, that row says the charge is unknown and the daily total
is withheld rather than understated.

Monthly usage uses `individualUsage.plan`, then `individualUsage.overall` when
Cursor exposes an individual Enterprise allowance. `teamUsage.pooled` and
administrator Team Caps are never used as personal Monthly usage.

### Codex quota

The quota panel reads the existing Codex sign-in from `~/.codex/auth.json` and
requests:

```text
https://chatgpt.com/backend-api/wham/usage
```

Windows are identified by `limit_window_seconds`; the window with the least
remaining allowance becomes the Widget summary. Credits-only responses show a
balance, unlimited or exhausted state without inventing a percentage.

### DeepSeek usage and balance

Choose **Connect in browser…** in the menu. The app opens the official DeepSeek
Platform page in the system default browser and keeps checking for the completed
sign-in in the background, so closing the menu popover does not interrupt login.
For Chromium browsers (Chrome, Edge, Arc, Brave and compatible variants), the
collector reads only the `userToken` entry belonging to
`https://platform.deepseek.com`. With Safari, the app asks macOS Automation for
access to the official DeepSeek tab and reads that same key through Safari's
Apple Events interface. In Safari, first enable **Settings → Advanced → Show
features for web developers**, then enable **Settings → Developer → Allow
JavaScript from Apple Events**. In both cases the token is validated against
DeepSeek before it is stored in
`~/Library/Application Support/CodexWeek/` with mode `600`.
The collector then requests the same official data used by
[platform.deepseek.com/usage](https://platform.deepseek.com/usage):

```text
https://platform.deepseek.com/api/v0/users/get_user_summary
https://platform.deepseek.com/api/v0/usage/amount?month=<month>&year=<year>
https://platform.deepseek.com/api/v0/usage/cost?month=<month>&year=<year>
```

The displayed range starts at the first day of the current local month. Token
totals combine cache-hit input, cache-miss input and output tokens exactly once.
Costs and balances retain the currency returned by DeepSeek. DeepSeek is an
independent data segment: an expired session or network failure leaves Codex
and Cursor refreshes unaffected and preserves the last successful DeepSeek
snapshot as stale.

## Refresh and fallback

The app refreshes on launch, when the popover opens, on manual refresh and
every five minutes through the existing LaunchAgent. The Widget requests a
matching five-minute timeline, subject to WidgetKit scheduling.

Codex tokens, Cursor costs, Cursor quota, Codex quota and DeepSeek usage refresh
independently.
If one source fails, its most recent successful value remains visible as stale
while the other sources keep updating. Cache older than three hours receives a
strong warning. Missing live data is never replaced with preview data.

## Privacy

- Credentials come from existing local Cursor and Codex sessions and remain in
  collector memory. DeepSeek opens its official page in the default browser;
  the collector inspects only that origin's `userToken` in Chromium local
  storage, or the app reads the same key from the open official Safari tab via
  macOS Automation. It validates the token and stores it locally with mode
  `600` for background refresh.
- The snapshot contains no access tokens, cookies, user/team/conversation IDs,
  prompts or response content.
- Requests are restricted to `cursor.com`, `chatgpt.com` and
  `platform.deepseek.com`, require successful
  HTTP status codes, validate their response shape and use finite timeouts.
- The snapshot is atomically replaced at
  `~/Library/Application Support/CodexWeek/codex-week-snapshot.json`.
- Its directory is mode `700` and the snapshot is mode `600`.
- All repository screenshots use deterministic `Demo` data from
  `UsageSnapshot.preview`; they never contain live account values or personal
  Cursor usage.

## Requirements and installation

- macOS 14 or newer
- Cursor signed in locally
- Codex desktop app or CLI used locally
- Full Xcode in `/Applications/Xcode.app`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Install or upgrade:

```bash
brew install xcodegen
chmod +x scripts/*.sh Tests/collector_test.sh
./scripts/install.sh
```

The installer asks for an optional Apple Developer Team ID, a unique bundle
prefix, local data paths and a refresh interval (five minutes by default). It
builds a Release app at `~/Applications/CodexWeek.app`, updates the existing
`io.github.codexweek.refresh` LaunchAgent, registers the Widget and starts the
menu-bar app.

## Development and tests

Generate the project and run the Swift tests:

```bash
xcodegen generate
xcodebuild \
  -project CodexWeek.xcodeproj \
  -scheme CodexWeek \
  -derivedDataPath /tmp/codexweek-derived \
  test
```

Run the network-free collector integration test against that build:

```bash
./Tests/collector_test.sh \
  /tmp/codexweek-derived/Build/Products/Debug/CodexWeekCollector
```

The `CodexWeekPreviewRenderer` target regenerates the README screenshots from
`UsageSnapshot.preview`; it never reads the production snapshot.

The collector accepts these fixture overrides:

```text
CODEX_TOKEN_FIXTURE
CODEX_USAGE_FIXTURE
CURSOR_EVENTS_FIXTURE
CURSOR_SUMMARY_FIXTURE
DEEPSEEK_AMOUNT_FIXTURE
DEEPSEEK_COST_FIXTURE
DEEPSEEK_SUMMARY_FIXTURE
CURSOR_STATE_DB
```

Coverage includes schema v4 decoding, v3/v2 migration, percent clamping,
Codex token subset semantics, single and multiple quota windows, tolerant
Cursor number decoding, zero-cost events, pagination boundaries, actual-charge
totals, personal Monthly usage precedence, independent fallback, snapshot
permissions and privacy. SwiftUI previews cover all four Widget families plus
ready, stale, signed-out, error, long-value, empty-model and missing-reset states.

## Troubleshooting

- **Cursor says Sign in:** open Cursor, confirm the intended account is active,
  then click refresh.
- **Codex has no token data:** run at least one local Codex session and refresh.
- **DeepSeek says Connect:** choose **Connect in browser…** and finish signing
  in on the official page. The app continues checking after the menu closes.
  Safari may ask for Automation permission. Enable **Settings → Advanced →
  Show features for web developers**, followed by **Settings → Developer →
  Allow JavaScript from Apple Events**. Use **Check now** after enabling it, or
  **Reconnect in browser…** if the session expires.
- **Data is stale:** inspect `~/Library/Logs/CodexWeek/` and verify access to
  `cursor.com`, `chatgpt.com` and `platform.deepseek.com`.
- **Widget is missing or appears more than once:** run
  `./scripts/repair_widget.sh`. It removes stale Xcode build registrations,
  registers only the installed copy, and refreshes WidgetKit.

## Project structure

- `App/` — application entry, asynchronous state and menu popover components
- `Collector/` — Codex, Cursor and DeepSeek clients, fallback and snapshot writing
- `Widget/` — timeline entry, adaptive quota panels and state previews
- `Shared/` — schema v4, v3/v2 migration, snapshot loading and formatters
- `Tests/` — Swift tests and network-free collector fixtures
- `PreviewRenderer/` — deterministic menu and Widget screenshot generator
- `scripts/` — install, refresh, Widget repair and uninstall helpers

## License

This project is released under the MIT License. CodexBarCore and adapted
CodexBar code are used under CodexBar's MIT License; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
