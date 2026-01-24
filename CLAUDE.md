# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

juvy is a simple dotfile backup utility written in Bash (3.2 compatible) that uses rsync + git for versioned backups with smart defaults. It works with both bash and zsh environments, features automatic detection of common dotfiles, and supports macOS and Linux. Default backup directory is in iCloud Drive on macOS for cross-device sync.

## Architecture

### Core Structure

- **Module + bundle architecture**: Source modules live in `src/` and are bundled into `juvy.sh` via `scripts/build.sh`
- **Function-based design**: All functionality is implemented as bash functions with `_juvy_` prefix
- **Configuration-driven**: Uses files in `~/.config/juvy/` for configuration and state
- **Git-based versioning**: Each backup creates a git commit for version history
- **Bash 3.2 compatible**: No associative arrays or namerefs - uses individual global variables

### Global State Variables

```bash
_JUVY_VERSION=""
_JUVY_CONFIG_DIR=""
_JUVY_CONFIG_FILE=""
_JUVY_BACKUP_FILE=""
_JUVY_LOG_FILE=""
_JUVY_BACKUP_DIR=""
_JUVY_REMOTE_URL=""
_JUVY_REMOTE_PUSH=""
_JUVY_REMOTE_NAME=""
_JUVY_PLATFORM=""  # "macos" or "linux"

# Global arrays for backup entry collection
_JUVY_INCLUDE_PATHS=()
_JUVY_EXCLUDE_PATTERNS=()
```

### Key Components

**Main Entry Point**: `juvy()` function acts as a command dispatcher that routes to specific sub-functions based on the first argument.

**Path Resolution System**:

- `_juvy_entry_to_source_path()` - Converts backup entries to filesystem paths
- `_juvy_entry_to_backup_path()` - Maps entries to backup storage locations
- `_juvy_entry_to_relative_path()` - Converts entries to relative paths for rsync filters

**Backup Processing**:

- `_juvy_process_backup_entries()` - Main backup orchestration with include/exclude filter support
- `_juvy_build_rsync_filter_file()` - Generates ordered rsync filter rules for include/exclude handling
- `_juvy_rsync_backup_with_filters()` - Rsync backup with delete semantics and filter rules
- `_juvy_parse_backup_entry()` - Parses backup file entries supporting comments and exclusions

**Restore Processing**:

- `_juvy_perform_restore()` - Main restore orchestration with safety backup creation
- `_juvy_rsync_restore_with_filters()` - Rsync restore using the same filter rules as backup
- `_juvy_create_safety_backup()` - Creates timestamped safety backups before restore operations

**Git Remote Integration**:

- `_juvy_remote_*()` functions handle git remote configuration and synchronization
- Auto-push capability after each backup when configured

**Cross-Platform Support**:

- `_juvy_detect_platform()` - Detects macOS vs Linux
- `_juvy_default_backup_dir()` - Returns platform-appropriate default backup directory
- `_juvy_get_file_mtime()` / `_juvy_get_file_size()` - Cross-platform stat wrappers

## Configuration Files

- `~/.config/juvy/config` - Shell variables for configuration (JUVY_BACKUP_DIR, remote settings)
- `~/.config/juvy/backup` - List of files/directories to backup with support for:
  - Include patterns: `~/.zshrc`, `~/.config/nvim/`
  - Exclude patterns: `!~/.config/nvim/undo/`
  - Inline comments: `~/.zshrc # Main shell config`
- `~/.config/juvy/log` - Operation logging (backup results, errors)

## Development Commands

### Testing

```bash
# Run all integration tests
bash tests/run-tests.sh

# Run a single test
bash tests/integration/test-single-backup.sh

# Tests create isolated environments with:
# - Temp HOME directory
# - Temp backup directory with git initialized
# - JUVY_CONFIG_DIR override
# No risk of affecting real user data.
```

### Manual Testing

```bash
# Test core workflow:
juvy init      # Initialize with auto-detection
juvy doctor    # Validate juvy configuration and backup file
juvy backup    # Create backup
juvy list      # Verify tracked files
juvy status    # Check for changes

# Test git integration:
juvy git log --oneline       # View backup history
```

### Installation

```bash
# Install from repository
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | bash

# Local development installation
./install.sh
```

### Building

```bash
# Bundle src/ modules into juvy.sh
./scripts/build.sh
```

### Version Management

- Version is hardcoded in `_JUVY_VERSION` variable in src/00_header.sh
- Update mechanism downloads from GitHub main branch

## Important Implementation Details

### Path Handling

The system supports two path formats:

- Tilde paths: `~/.zshrc` (home-relative)
- Absolute paths: `/etc/hosts`

All paths are stored in backup using their absolute filesystem structure (e.g., `/Users/user/.zshrc` → `{backup_dir}/Users/user/.zshrc`) for clean organization and simple restore operations.

### Backup File Format

Supports advanced patterns:

```bash
# Core files
~/.zshrc                    # Single file
~/.config/nvim/             # Directory (trailing slash required)

# Exclusion patterns
!~/.config/nvim/undo/       # Exclude undo directory
!*.log                      # Exclude all .log files

# Inline comments supported
~/.gitconfig                # Git configuration
```

### Security Features

- Automatic detection and warnings for sensitive files (SSH keys, certificates, tokens)
- Interactive prompts for security warnings
- Large directory detection (>100MB) with user prompts
- Safety backups created before restore operations

### Backup and Restore Implementation

**Backup Strategy (Two-Operation Approach)**:
- **HOME directory sync**: Single rsync operation for all home directory files using filter rules
- **SYSTEM directory sync**: Single rsync operation for all system files using filter rules
- **Filter-based inclusion/exclusion**: Ordered rsync filter rules (excludes take precedence over includes)
- **Deletion management**: Uses `--delete` and `--delete-excluded` to maintain exact mirrors
- **Directory handling**: Generates hierarchical parent-dir rules plus recursive `/***` includes for directory contents

**Restore Strategy (Two-Operation Approach)**:
- **Targeted restore**: Restores only tracked paths via the same filter rules used for backup
- **Safety backups**: Creates timestamped backup of current files before restore
- **Git exclusion**: Excludes `.git` directory from restore to avoid restoring backup metadata
- **Permission handling**: Uses `--ignore-errors` and treats partial transfers as success when data is transferred

### Error Handling

- Operation logging to `~/.config/juvy/log` with timestamps
- User-friendly error messages with actionable suggestions
- Special handling for permission issues during restore operations
- Single-attempt rsync operations (no retry logic)

## Testing Strategy

Integration tests exist in `tests/integration/`. Current coverage:
- `test-single-backup.sh` - Basic backup and restore cycle
- `test-filter-excludes.sh` - Include/exclude pattern filtering
- `test-symlinks.sh` - Symlink preservation during backup/restore
- `test-missing-files.sh` - Graceful handling of missing source files
- `test-special-chars.sh` - Filenames with spaces and special characters
- `test-safety-backup.sh` - Safety backup creation before restore
- `test-restore-dry-run.sh` - Dry-run restore functionality
- `test-remove.sh` - Remove command functionality

When adding new functionality, add a corresponding test. Test structure:
1. Create temp directory with `mktemp -d`
2. Override `HOME` and `JUVY_CONFIG_DIR` for isolation
3. Initialize git in backup directory
4. Source `juvy.sh`
5. Run operations and assertions
6. Clean up with `cleanup_dir`

## Git Remote Features

The tool supports optional git remote synchronization:

- Prompted during `juvy init` but can be skipped
- Supports SSH and HTTPS git URLs
- Auto-push after each backup when enabled
- Manual remote management via `juvy remote` commands

## Common Development Patterns

- All user-facing functions follow the `_juvy_<command>` naming pattern
- Configuration updates use `_juvy_update_config` and `_juvy_remove_config` utilities
- Path validation happens before any operations via `_juvy_validate_path`
- Rsync operations use specialized functions with error handling and user-friendly messages

## Bash 3.2 Compatibility Notes

This codebase targets Bash 3.2 (macOS default) which means:

- **No associative arrays**: Use individual global variables instead
- **No namerefs**: Use `eval` with proper quoting for indirect array access
- **No negative array indices**: Use `${arr[${#arr[@]}-1]}` instead of `${arr[-1]}`
- **Safe array expansion**: Use `${arr[@]+"${arr[@]}"}` pattern for empty arrays with `set -u`

## Bash Best Practices & Patterns

### Variable Handling

- **Always quote variables**: `"$VAR"` not `$VAR`
- **Quote assignments**: `VAR="$HOME/.config"` not `VAR=$HOME/.config`
- **Use local variables in functions**: `local var` for function scope
- **Parameter expansion**: Use `${VAR:-default}` for defaults
- **Command existence**: Use `command -v cmd >/dev/null 2>&1`

### Conditional Expressions

- **Prefer readable order**: `[[ ! -f file ]]` not `! [[ -f file ]]`
- **Use [[ ]] for tests**: More powerful than `[ ]`
- **File tests**: `-f` (regular file), `-d` (directory), `-e` (exists)
- **String tests**: `-z` (empty), `-n` (non-empty)
- **Pattern matching**: `[[ $var == pattern* ]]`

### Function Definitions

- **Use local variables**: Declare `local var` at function start
- **Parameter handling**: Use `"$@"` for all arguments, `"$1"` for first
- **Return values**: Use `return 0` (success) or `return 1` (failure)
- **Error handling**: Check return values and handle appropriately

### Case Statements (Bash Style)

```bash
case $var in
  pattern1)
    command1
    ;;
  pattern2|pattern3)
    command2
    ;;
  *)
    default_command
    ;;
esac
```

### Array Handling (Bash 3.2)

```bash
# Declaration
local arr=()
arr=("item1" "item2" "item3")

# Safe expansion with set -u
for item in ${arr[@]+"${arr[@]}"}; do
  echo "$item"
done

# Array length
echo "${#arr[@]}"

# Last element (Bash 3.2 compatible)
echo "${arr[${#arr[@]}-1]}"

# Append
arr+=("new_item")
```

### Command Substitution & Quoting

- **Use direct commands when possible**: `grep -q pattern file` not `[[ -n $(grep pattern file) ]]`
- **Quote command substitution**: `"$(command)"`
- **Group commands**: Use `{ command1; command2; }` for grouping
- **Proper quoting in loops**: `for file in "$@"; do`

### Error Handling Patterns

- **Check file existence**: `[[ -f "$file" ]] || { echo "Error" >&2; return 1; }`
- **Command success**: `command || { echo "Failed" >&2; return 1; }`
- **Directory creation**: `mkdir -p "$dir" || return 1`
- **File operations**: Always check return values

### Cross-Platform Patterns

```bash
# Platform detection
case "$(uname -s)" in
  Darwin) platform="macos" ;;
  Linux)  platform="linux" ;;
esac

# Cross-platform stat
case "$platform" in
  macos) stat -f '%m' "$file" ;;  # mtime
  *)     stat -c '%Y' "$file" ;;
esac
```

### Security Patterns

- **Quote all user input**: Prevent injection attacks
- **Use printf %q**: For shell-safe quoting `printf %q "$user_input"`
- **Validate paths**: Check for expected patterns
- **Avoid eval where possible**: Use parameter expansion instead

### Common Anti-Patterns to Avoid

- `$@` → `"$@"`
- `${arr[-1]}` → `${arr[${#arr[@]}-1]}` (Bash 3.2)
- `${arr[@]}` with set -u → `${arr[@]+"${arr[@]}"}`
- Unquoted variables → `"$variable"`
- `echo` for data → `printf '%s\n'`

### Critical: Avoid Special Variable Names

**NEVER use `path` as a variable name** in scripts that may be sourced in zsh, as `path` is a special array tied to `PATH`. Use `p`, `file_path`, `input_path`, etc. instead.

Other names to avoid: `cdpath`, `fpath`, `mailpath`, `manpath` (zsh special), `BASH_VERSINFO`, `BASH_VERSION`, `PIPESTATUS` (bash special).
