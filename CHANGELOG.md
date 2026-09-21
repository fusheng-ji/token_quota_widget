# Changelog

This file records the user problem addressed by each verifiable release in the
repository. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [5.0.5] - 2026-09-21

### Fixed

- Problem: Codex tasks running through the configured remote SSH host wrote
  token records under the remote Cursor server and were absent from today's
  menu-bar total.
- Resolution: incrementally scan the optional remote Codex directory over SSH,
  merge it with local usage by hashed response ID, and retain same-day remote
  cache data with a stale warning when the connection is unavailable.

- Problem: after replacing the app bundle, a Widget extension process from the
  previous build could remain alive while cleanup unregistered a DerivedData
  copy with the same bundle ID. WidgetKit then rejected every new timeline with
  a bundle-version mismatch.
- Resolution: stop and verify the App and Widget extension processes before
  replacement, register the installed extension only after removing other app
  copies, and avoid unregistering the build copy again after a successful
  installation. Widget repair now follows the same process-safe ordering.

## [5.0.4] - 2026-09-14

### Fixed

- Problem: the first completed Codex response of a day could remain at zero in
  the Widget until the next five-minute full-provider refresh.
- Resolution: run a local-only Codex refresh every 45 seconds while BeaverMeter
  is open, scan only newly appended rollout bytes, serialize concurrent
  collectors, and reload WidgetKit without increasing Cursor, DeepSeek or quota
  network traffic.

## [5.0.3] - 2026-09-11

### Fixed

- Problem: the LaunchAgent could write a newer Codex token total while the
  closed menu-bar popover kept the app's refresh timer inactive, leaving the
  desktop Widget on its previous timeline.
- Resolution: observe the shared snapshot for the lifetime of the menu-bar app,
  adopt newer schema v5 snapshots even while the popover is closed, and request
  a WidgetKit timeline reload only when the snapshot timestamp advances.

## [5.0.2] - 2026-09-08

### Fixed

- Problem: the desktop Widget could remain blank after an app upgrade because
  WidgetKit retained a timeline archived against an older bundle version.
- Resolution: unregister non-installed BeaverMeter bundle copies, compact the
  LaunchServices database, and restart the per-user WidgetKit cache processes
  after registering the new extension, then let BeaverMeter request a fresh
  timeline on launch.

## [5.0.1] - 2026-09-07

### Fixed

- Problem: today's Codex token total could remain at zero for a long-running
  Codex Desktop task when its rollout continued growing inside an older date
  directory after midnight.
- Resolution: scan recently modified rollouts for Codex Desktop's per-response
  `token_usage_record` entries, deduplicate responses, and retain the existing
  CodexBar scan as the fallback for older session formats.

## [5.0.0] - 2026-09-06

### Added

- Added the BeaverMeter beaver-head logo and a complete 16–1024 px macOS App
  Icon set.
- Added migration tests for first upgrade, destination precedence, credential
  permissions and rejection of pre-v5 snapshots.

### Changed

- Renamed the app, Widget, schemes, targets, Swift types, collector helper,
  bundle IDs, LaunchAgent and storage paths from AI Token Quota / CodexWeek to
  BeaverMeter.
- Moved new configuration to `BEAVERMETER_*` and `BEAVER_METER_CONFIG`, while
  accepting the old environment names as lower-priority 5.0.0 aliases.
- The installer now migrates existing configuration, DeepSeek credentials and
  valid schema v5 snapshots without overwriting newer destination files, and
  restores the previous installation if replacement validation fails.
- The Widget uses a new bundle ID and kind. Existing Widgets must be removed
  and added again as BeaverMeter after upgrading.

### Removed

- Removed the old app, LaunchAgent, data and log locations after a successful
  migration and installation.

## [4.4.0] - 2026-09-06

### Fixed

- Fixed Codex daily token totals getting stuck while the active rollout file
  continued growing, including after a usage-reset credit was redeemed.
- Updated CodexBarCore to 0.56.5 so cached session indexes consume newly
  appended token events instead of returning the cached prefix indefinitely.

### Changed

- Advanced the snapshot format to schema v5. Older cached snapshots are
  ignored and regenerated automatically on the next refresh.
- Consolidated Collector process execution, snapshot loading, error output and
  currency formatting to remove duplicate implementations.
- Replaced multiple DeepSeek test-only amount and cost parsers with one stable
  usage fixture matching the monthly totals exposed in production.

### Removed

- Removed v2-v4 snapshot migration code.
- Removed DeepSeek per-model data, views and previews that production never
  populated.

## [4.3] - 2026-09-01

### Added

- Added DeepSeek browser connection, wallet balance, monthly token and request
  totals, and monthly cost reporting.
- Added Chromium local-storage and Safari Automation session import with local
  credential validation and protected storage.

### Changed

- Moved snapshots to schema v4 and made DeepSeek refresh failures independent
  from Codex and Cursor data.
- Refined the menu-bar summary and all four Widget families for three-provider
  status, stale-data warnings and long values.

## [4.0] - 2026-09-01

### Added

- Introduced one macOS menu-bar app and Widget for Codex daily token activity,
  Codex quota, Cursor actual model-call charges and Cursor Monthly allowance.
- Added recent Cursor call details, local Codex session aggregation, independent
  stale-data fallback, deterministic previews and network-free fixtures.

[Unreleased]: https://github.com/fusheng-ji/token_quota_widget/compare/v5.0.4...HEAD
[5.0.4]: https://github.com/fusheng-ji/token_quota_widget/compare/v5.0.3...v5.0.4
[5.0.3]: https://github.com/fusheng-ji/token_quota_widget/compare/v5.0.2...v5.0.3
[5.0.2]: https://github.com/fusheng-ji/token_quota_widget/compare/v5.0.1...v5.0.2
[5.0.1]: https://github.com/fusheng-ji/token_quota_widget/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/fusheng-ji/token_quota_widget/compare/v4.4.0...v5.0.0
[4.4.0]: https://github.com/fusheng-ji/token_quota_widget/compare/v4.3...v4.4.0
[4.3]: https://github.com/fusheng-ji/token_quota_widget/compare/v4.0...v4.3
[4.0]: https://github.com/fusheng-ji/token_quota_widget/tree/v4.0
