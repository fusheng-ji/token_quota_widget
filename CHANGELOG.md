# Changelog

This file records the user problem addressed by each verifiable release in the
repository. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[4.4.0]: https://github.com/fusheng-ji/token_quota_widget/compare/v4.3...v4.4.0
[4.3]: https://github.com/fusheng-ji/token_quota_widget/compare/v4.0...v4.3
[4.0]: https://github.com/fusheng-ji/token_quota_widget/tree/v4.0
