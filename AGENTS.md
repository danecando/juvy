# AGENTS.md

Guidance for coding agents working in this repository.

## Project Summary

- `juvy` is a dotfile backup tool written in Bash.
- It syncs configured files/directories into a backup directory with `rsync`.
- The backup directory is a git repo; backups commit only when changes exist.
- Primary artifact is `juvy.sh`, generated from `src/` modules.

## Core Constraints

- Bash compatibility target includes macOS default Bash (`3.2`).
- Avoid Bash 4+ features (especially associative arrays and `mapfile`).
- Keep behavior cross-platform for macOS and Linux.
- Prefer small, focused changes over broad rewrites.
- Do not edit generated `juvy.sh` directly; edit `src/*.sh` and rebuild.

## Repository Map

- `/src/00_header.sh` - globals, version, shared constants
- `/src/10_config.sh` - config paths/loading/defaults
- `/src/20_commands.sh` - command dispatch and user-facing command handlers
- `/src/30_backup.sh` - backup orchestration and rsync filter behavior
- `/src/40_utils.sh` - shared helpers (paths, logging, parsing, validation)
- `/src/50_restore.sh` - restore and safety-backup flow
- `/src/60_git_remote.sh` - remote setup/sync/rebase logic
- `/src/99_main.sh` - script entrypoint
- `/scripts/build.manifest` - module bundle order
- `/scripts/build.sh` - builds `juvy.sh` from manifest
- `/tests/bats/*.bats` - integration tests
- `/tests/run-docker-tests.sh` - primary test runner (Docker/local, Bash 3.2 option)

## Build and Test

- Build after source changes:
  - `./scripts/build.sh`
- Preferred test commands:
  - `./tests/run-docker-tests.sh`
  - `./tests/run-docker-tests.sh --bash32`
  - `./tests/run-docker-tests.sh --local` (if local `bats` is available)
- Targeted test run:
  - `./tests/run-docker-tests.sh backup.bats`

## Coding Conventions

- Prefix internal functions with `_juvy_`.
- Keep user-facing output concise and actionable.
- Preserve include/exclude semantics in backup rules (excludes must keep precedence).
- Preserve restore safety behavior (create safety backup before modifications).
- When changing CLI behavior, update help text and README in the same change.

## Safe Change Workflow

1. Read impacted modules in `src/` first.
2. Implement minimal change in source modules.
3. Rebuild with `./scripts/build.sh`.
4. Run relevant bats tests; run full suite for risky changes.
5. Ensure generated `juvy.sh` reflects the source edits.

## High-Risk Areas

- Path resolution and normalization (`~`, absolute paths, trailing slash behavior).
- Rsync filter generation/order and delete behavior.
- Restore logic and safety-backup restore paths.
- Git remote sync flow (fetch/rebase/push conflict handling).

## Definition of Done

- Source updates are in `src/` and bundled output is rebuilt.
- Tests pass for impacted behavior.
- Docs/help are updated when command UX changes.
- No Bash 4+ regressions introduced.
