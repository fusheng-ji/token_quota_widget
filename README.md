<p align="center">
  <img src="Design/Logo/beaver-logo-head-only.png" alt="BeaverMeter beaver logo" width="180">
</p>

<h1 align="center">BeaverMeter</h1>

<p align="center">Codex、Cursor 与 DeepSeek 用量监控</p>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS 14+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-5.0%20%2F%206.0-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 5.0 / 6.0"></a>
  <a href="https://github.com/fusheng-ji/token_quota_widget"><img src="https://img.shields.io/badge/version-5.0.0-4C7CF3?style=flat-square" alt="Version 5.0.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2EA44F?style=flat-square" alt="MIT License"></a>
</p>

BeaverMeter is a native macOS menu-bar app and WidgetKit extension that keeps
Codex token activity and quota, Cursor model-call costs and Monthly allowance,
and DeepSeek monthly usage and wallet balance in one place.

See [CHANGELOG.md](CHANGELOG.md) for the problem addressed by every verifiable
release.

## Interface

The menu bar shows Codex tokens, Cursor's latest actual charge and DeepSeek's
wallet balance in one compact line. The popover expands this into Codex input,
cached input, output and reasoning totals; Cursor's daily actual charge and the
latest 20 model calls; and DeepSeek balance, current-month cost, tokens and
requests.

The Widget adapts the three provider panels to every supported family:

| Family | Layout |
| --- | --- |
| Small | Three compact Codex, Cursor and DeepSeek rows |
| Medium | Codex/Cursor side by side, DeepSeek across the bottom |
| Large | 2×2 layout with DeepSeek across the bottom |
| Extra Large | Large layout plus real model details when available |

<table>
  <tr>
    <th colspan="2">Menu-bar popover</th>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <img src="screenshots/menu-popover.png" alt="BeaverMeter menu-bar popover with Demo data" width="390">
    </td>
  </tr>
  <tr>
    <th>Small Widget</th>
    <th>Medium Widget</th>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/widget-small.png" alt="BeaverMeter Small Widget with Demo data" width="174">
    </td>
    <td align="center">
      <img src="screenshots/widget-medium.png" alt="BeaverMeter Medium Widget with Demo data" width="352">
    </td>
  </tr>
  <tr>
    <th>Large Widget</th>
    <th>Extra Large Widget</th>
  </tr>
  <tr>
    <td align="center">
      <img src="screenshots/widget-large.png" alt="BeaverMeter Large Widget with Demo data" width="352">
    </td>
    <td align="center">
      <img src="screenshots/widget-extra-large.png" alt="BeaverMeter Extra Large Widget with Demo data" width="430">
    </td>
  </tr>
</table>

Every screenshot is generated from the bundled preview snapshot and marked
`Demo`; none contains live account values or private Cursor activity.

Codex and Cursor show remaining allowance, reset countdown and a progress line.
Codex is teal and Cursor is indigo; values below 50% turn amber and values below
20% turn red. DeepSeek uses blue and reports its real wallet balance and monthly
activity. Because DeepSeek does not publish a quota limit or reset time,
BeaverMeter does not invent a percentage or progress bar.

## Data sources and semantics

### Codex tokens

The bundled collector uses
[CodexBarCore](https://github.com/steipete/CodexBar/) pinned to the 0.56.5 release
commit [`07f2a670229bca1a34bb7eda5284c89657b8df9a`](https://github.com/steipete/CodexBar/commit/07f2a670229bca1a34bb7eda5284c89657b8df9a).
Its local scanner aggregates the current local day across `~/.codex/sessions`,
including compressed sessions, duplicate events, file boundaries and newly
appended events in a still-running Codex task.

The displayed total is `input + output`. Cached input is part of input and
reasoning is part of output, so neither detail is counted twice.

### Cursor call costs and Monthly usage

The collector reads Cursor's existing local sign-in token from `state.vscdb`,
keeps it in process memory and requests the same official Dashboard data used
by [cursor.com/dashboard/usage](https://cursor.com/dashboard/usage):

```text
https://cursor.com/api/dashboard/get-filtered-usage-events
https://cursor.com/api/usage-summary
```

Each call uses `chargedCents`, the amount actually deducted by Cursor, rather
than the model provider list price. `$0.00` calls remain visible. If a valid
call has no valid actual charge, its charge is shown as unknown and the daily
total is withheld instead of understated.

Monthly usage prefers `individualUsage.plan`, then `individualUsage.overall`
when Cursor exposes an individual Enterprise allowance. Team pools and
administrator Team Caps are never presented as personal Monthly usage.

### Codex quota

The quota panel reuses the existing Codex sign-in from `~/.codex/auth.json` and
requests:

```text
https://chatgpt.com/backend-api/wham/usage
```

Windows are identified by `limit_window_seconds`; the window with the least
remaining allowance becomes the Widget summary. Credits-only responses show a
balance, unlimited or exhausted state without inventing a percentage.

### DeepSeek usage and balance

Choose **Connect in browser…** in the menu. BeaverMeter opens the official
DeepSeek Platform page and continues checking in the background, so closing the
popover does not interrupt sign-in.

For Chromium browsers (Chrome, Edge, Arc, Brave and compatible variants), the
collector reads only the `userToken` entry belonging to
`https://platform.deepseek.com`. With Safari, BeaverMeter requests macOS
Automation access to the official DeepSeek tab and reads the same key through
Safari's Apple Events interface. In Safari, first enable **Settings → Advanced
→ Show features for web developers**, then **Settings → Developer → Allow
JavaScript from Apple Events**.

The token is validated against DeepSeek and stored at
`~/Library/Application Support/BeaverMeter/deepseek-platform-token` with mode
`600`. The collector requests the same official data used by
[platform.deepseek.com/usage](https://platform.deepseek.com/usage):

```text
https://platform.deepseek.com/api/v0/users/get_user_summary
https://platform.deepseek.com/api/v0/usage/amount?month=<month>&year=<year>
https://platform.deepseek.com/api/v0/usage/cost?month=<month>&year=<year>
```

The range starts on the first day of the current local month. Token totals add
cache-hit input, cache-miss input and output exactly once. Costs and balances
retain DeepSeek's returned currency. DeepSeek failures do not interrupt Codex
or Cursor refreshes, and the last successful DeepSeek value remains visible as
stale.

## Refresh and fallback

BeaverMeter refreshes on launch, whenever the popover opens, on manual refresh
and every five minutes through its LaunchAgent. The Widget requests a matching
five-minute timeline, subject to WidgetKit scheduling.

Codex tokens, Cursor costs, Cursor quota, Codex quota and DeepSeek usage refresh
independently. If one source fails, its latest successful value stays visible
as stale while the others continue updating. Cache older than three hours gets
a strong warning; missing live data is never replaced with preview data.

The snapshot remains schema v5. Snapshots from schema v2-v4 are rejected and
regenerated by the next refresh.

## Privacy

- Cursor and Codex credentials come from existing local sessions and remain in
  collector memory. The validated DeepSeek browser token is stored locally with
  mode `600` for background refresh.
- The snapshot contains no tokens, cookies, user/team/conversation IDs, prompts
  or response content.
- Requests are limited to `cursor.com`, `chatgpt.com` and
  `platform.deepseek.com`, require successful HTTP responses, validate response
  shape and use finite timeouts.
- The snapshot is atomically replaced at
  `~/Library/Application Support/BeaverMeter/beaver-meter-snapshot.json`.
- The data directory is mode `700`; credentials and snapshots are mode `600`.
- Repository screenshots use deterministic `UsageSnapshot.preview` data only.

## Requirements and installation

- macOS 14 or newer
- Cursor signed in locally
- Codex desktop app or CLI used locally
- Full Xcode at `/Applications/Xcode.app`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Install or upgrade:

```bash
brew install xcodegen
chmod +x scripts/*.sh Tests/*.sh
./scripts/install.sh
```

The installer asks for an optional Apple Developer Team ID, a unique bundle
prefix, local data paths and a refresh interval. It builds
`~/Applications/BeaverMeter.app`, installs the
`io.github.beavermeter.refresh` LaunchAgent, registers the Widget and starts the
menu-bar app.

### Upgrading from 4.4.0

The 5.0.0 installer migrates `config.env`, the DeepSeek token and a valid schema
v5 snapshot from `~/Library/Application Support/CodexWeek/` into the new
BeaverMeter data directory. Existing destination files always win. It keeps a
rollback copy while validating the replacement; after a successful install it
removes the old app, LaunchAgent, data and logs. If validation fails, the old
installation is restored and the legacy data remains available.

The App and Widget now have new bundle IDs and the Widget kind changed. macOS
cannot convert an existing desktop Widget automatically: remove the old Widget,
then add **BeaverMeter** from **Edit Widgets**.

The new build settings and script overrides are `BEAVERMETER_*` and
`BEAVER_METER_CONFIG`. Version 5.0.0 also accepts the legacy `CODEXWEEK_*` and
`CODEX_WEEK_CONFIG` names as lower-priority aliases.

## Development and tests

Generate the project and run Swift tests:

```bash
xcodegen generate
xcodebuild \
  -project BeaverMeter.xcodeproj \
  -scheme BeaverMeter \
  -derivedDataPath /tmp/beavermeter-derived \
  test
```

Run the network-free integration and migration tests:

```bash
./Tests/collector_test.sh \
  /tmp/beavermeter-derived/Build/Products/Debug/BeaverMeterCollector
./Tests/migration_test.sh
```

The `BeaverMeterPreviewRenderer` target regenerates README screenshots from
`UsageSnapshot.preview`; it never reads the production snapshot.

Collector fixture overrides:

```text
CODEX_TOKEN_FIXTURE
CODEX_USAGE_FIXTURE
CURSOR_EVENTS_FIXTURE
CURSOR_SUMMARY_FIXTURE
DEEPSEEK_USAGE_FIXTURE
DEEPSEEK_SUMMARY_FIXTURE
CURSOR_STATE_DB
CODEX_TOKEN_CACHE_ROOT
```

Coverage includes schema v5 round trips, v2-v4 rejection, percent clamping,
live-rollout token growth, quota-window selection, tolerant Cursor number
decoding, actual-charge totals, Monthly usage precedence, independent stale
fallback, migration precedence, file permissions and snapshot privacy.

## Troubleshooting

- **Cursor says Sign in:** open Cursor, confirm the intended account is active,
  then refresh.
- **Codex has no token data:** run at least one local Codex session and refresh.
- **DeepSeek says Connect:** choose **Connect in browser…** and finish signing in
  on the official page. Safari may request Automation permission; enable both
  developer settings described above, then use **Check now**.
- **Data is stale:** inspect `~/Library/Logs/BeaverMeter/` and verify access to
  `cursor.com`, `chatgpt.com` and `platform.deepseek.com`.
- **Widget is missing or duplicated:** run `./scripts/repair_widget.sh`, then add
  BeaverMeter again from **Edit Widgets** if upgrading from 4.4.0.

## Project structure

- `App/` — app entry, state and menu popover
- `Collector/` — Codex, Cursor and DeepSeek clients and snapshot writer
- `Widget/` — timeline provider, adaptive panels and previews
- `Shared/` — schema v5 models, loading and formatters
- `Tests/` — Swift tests, migration test and network-free fixtures
- `PreviewRenderer/` — deterministic screenshot generator
- `Design/Logo/` — BeaverMeter logo master
- `scripts/` — install, refresh, migration, Widget repair and uninstall helpers

## License

BeaverMeter is released under the MIT License. CodexBarCore and adapted
CodexBar code are used under CodexBar's MIT License; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
