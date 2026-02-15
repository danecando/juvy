# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [2.0.0] - 2026-02-15

### Added
- Reliable multi-machine remote sync workflow for `juvy backup` and `juvy remote sync`.
- Automatic remote reconciliation (`fetch` + `rebase`) before push in common divergence scenarios.
- Remote divergence diagnostics in `juvy status`, `juvy remote`, and `juvy doctor` with actionable guidance.
- Bats tests covering multi-machine sync reconciliation and divergence reporting.
- Automatic remote branch selection for sync operations:
  - local tracking branch when available
  - remote default branch (`origin/HEAD`) otherwise
  - fallback to `main`

### Changed
- `juvy remote sync` is now the manual sync command (fetch/rebase/push).
- Updated help text and README remote-sync docs to reflect reconciliation behavior.

### Removed
- `juvy remote push` command. Use `juvy remote sync`.

## [1.2.0] - 2026-02-15

### Added
- Added restore support for safety backup paths via `juvy restore --from-safety <path>` (and positional safety path support used by the undo command).
- Added backup locking to prevent overlapping backup runs from concurrent shells.
- Added regression tests for restore safety flows, rsync error handling, path handling, and backup locking.
- Added project changelog.

### Changed
- Restore now handles backup entries with inline comments consistently during preview and safety backup creation.
- Tightened rsync partial transfer behavior to avoid false-success reporting for generic exit code 23 failures.
- Improved `juvy add` path handling for quoted tilde paths and current-directory relative paths.
- Updated command help and README documentation for new restore and locking behavior.

### Fixed
- Fixed Docker test runner empty argument handling with `set -u`.
- Fixed mismatch between restore undo guidance and supported CLI behavior.
