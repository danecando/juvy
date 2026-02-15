# Changelog

## 1.2.0 - 2026-02-15

### Added
- Reliable multi-machine remote sync workflow for `juvy backup` and `juvy remote push`.
- Automatic remote reconciliation (`fetch` + `rebase`) before push in common divergence scenarios.
- Remote divergence diagnostics in `juvy status`, `juvy remote`, and `juvy doctor` with actionable guidance.
- Bats tests covering multi-machine sync reconciliation and divergence reporting.

### Changed
- `juvy remote push` now performs sync-aware push behavior (fetch/rebase/push) rather than push-only behavior.
- Updated help text and README remote-sync docs to reflect reconciliation behavior.
