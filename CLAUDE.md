# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

juvy is a simple dotfile backup utility written in Zsh that uses rsync + git for versioned backups with smart defaults. It targets zsh environments with automatic detection of common dotfiles and stores backups in iCloud Drive by default for cross-device sync.

## Architecture

### Core Structure

- **Module + bundle architecture**: Source modules live in `src/` and are bundled into `juvy.zsh` via `scripts/build.sh`
- **Function-based design**: All functionality is implemented as zsh functions with `_juvy_` prefix
- **Configuration-driven**: Uses files in `~/.config/juvy/` for configuration and state
- **Git-based versioning**: Each backup creates a git commit for version history

### Key Components

**Main Entry Point**: `juvy()` function acts as a command dispatcher that routes to specific sub-functions based on the first argument.

**Path Resolution System**:

- `_juvy_entry_to_source_path()` - Converts backup entries to filesystem paths
- `_juvy_entry_to_backup_path()` - Maps entries to backup storage locations  
- `_juvy_backup_path_to_entry()` - Reverse mapping from backup to entry format

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
for t in tests/integration/*.zsh; do zsh "$t"; done

# Run a single test
zsh tests/integration/test-single-backup.zsh

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
juvy validate  # Validate backup configuration
juvy backup    # Create backup
juvy list      # Verify tracked files
juvy status    # Check for changes

# Test git integration:
juvy git log --oneline       # View backup history
```

### Installation

```bash
# Install from repository
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh

# Local development installation
./install.sh
```

### Building

```bash
# Bundle src/ modules into juvy.zsh
./scripts/build.sh
```

### Version Management

- Version is hardcoded in `JUVY_VERSION` variable in juvy.zsh
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
- `test-single-backup.zsh` - Basic backup and restore cycle
- `test-filter-excludes.zsh` - Include/exclude pattern filtering
- `test-symlinks.zsh` - Symlink preservation during backup/restore
- `test-missing-files.zsh` - Graceful handling of missing source files
- `test-special-chars.zsh` - Filenames with spaces and special characters
- `test-safety-backup.zsh` - Safety backup creation before restore
- `test-restore-dry-run.zsh` - Dry-run restore functionality
- `test-remove.zsh` - Remove command functionality

When adding new functionality, add a corresponding test. Test structure:
1. Create temp directory with `mktemp -d`
2. Override `HOME` and `JUVY_CONFIG_DIR` for isolation
3. Initialize git in backup directory
4. Source `juvy.zsh`
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
- User prompts follow consistent emoji-based formatting for better UX

## Zsh Manual Reference

The complete zsh manual is available in the `zsh_html/` directory. When modifying or creating zsh scripts:

1. **Always reference the manual** for proper syntax and behavior verification
2. **Key sections to consult**:
   - `Shell-Grammar.html` - Basic shell syntax and structure
   - `Functions.html` - Function definition and scoping
   - `Parameters.html` - Variable handling and parameter expansion
   - `Shell-Builtin-Commands.html` - Built-in command usage
   - `Conditional-Expressions.html` - Test conditions and logic
   - `Options.html` - Shell options and emulation modes
3. **Use proper zsh idioms** rather than bash/POSIX equivalents when available
4. **Verify syntax** against the manual before implementing new features
5. **Check parameter expansion** syntax in `Parameter-Expansion.html`

## Zsh Best Practices & Patterns

### Variable Handling

- **Always quote variables**: `"$VAR"` not `$VAR`
- **Quote assignments**: `VAR="$HOME/.config"` not `VAR=$HOME/.config`
- **Use local variables in functions**: `local var` for function scope
- **Parameter expansion**: Use `${VAR:-default}` for defaults
- **Command existence**: Use `(( $+commands[cmd] ))` not `command -v cmd`

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

### Case Statements (Zsh Style)

```zsh
case $var in
  (pattern1)
    command1
    ;;
  (pattern2|pattern3)
    command2
    ;;
  (*)
    default_command
    ;;
esac
```

### Command Substitution & Quoting

- **Use direct commands when possible**: `grep -q pattern file` not `[[ -n $(grep pattern file) ]]`
- **Quote command substitution**: `"$(command)"`
- **Group commands**: Use `{ command1; command2; }` for grouping
- **Proper quoting in loops**: `for file in "$@"; do`

### Zsh-Specific Features

- **Commands array**: `$+commands[name]` to check if command exists
- **Enhanced globbing**: Enable with `setopt EXTENDED_GLOB`
- **Parameter flags**: `${(flags)parameter}` for transformations
- **Array handling**: `array=(item1 item2)`, `${array[@]}`
- **Associative arrays**: `typeset -A assoc_array`

### Error Handling Patterns

- **Check file existence**: `[[ -f "$file" ]] || { print "Error" >&2; return 1; }`
- **Command success**: `command || { print "Failed" >&2; return 1; }`
- **Directory creation**: `mkdir -p "$dir" || return 1`
- **File operations**: Always check return values

### Performance Patterns

- **Avoid unnecessary subshells**: Use built-ins when possible
- **Minimize external commands**: Use zsh built-ins over external tools
- **Efficient loops**: Use zsh array operations
- **Proper quoting**: Prevents word splitting overhead

### Security Patterns

- **Quote all user input**: Prevent injection attacks
- **Use printf %q**: For shell-safe quoting `printf %q "$user_input"`
- **Validate paths**: Check for expected patterns
- **Avoid eval**: Use parameter expansion instead

### Common Anti-Patterns to Avoid

- ❌ `$@` → ✅ `"$@"`
- ❌ `! [[ condition ]]` → ✅ `[[ ! condition ]]`
- ❌ `"string")` in case → ✅ `(string)` in case
- ❌ `command -v cmd` → ✅ `(( $+commands[cmd] ))`
- ❌ `$(grep pattern file)` tests → ✅ `grep -q pattern file`
- ❌ Unquoted variables → ✅ `"$variable"`

### Critical: Zsh Special Variables

**NEVER use `path` as a variable name.** In zsh, `path` is a special array tied to `PATH`. Using it as a loop variable (`for path in ...`) overwrites PATH and breaks external command execution. Use `p`, `file_path`, `input_path`, etc. instead.

Other special lowercase variables to avoid: `cdpath`, `fpath`, `mailpath`, `manpath`.
