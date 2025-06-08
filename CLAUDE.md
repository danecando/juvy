# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

juvy is a simple dotfile backup utility written in Zsh that uses rsync + git for versioned backups with smart defaults. It targets zsh environments with automatic detection of common dotfiles and stores backups in iCloud Drive by default for cross-device sync.

## Architecture

### Core Structure

- **Single file architecture**: The entire application is contained in `juvy/juvy.zsh` (~2700 lines)
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

- `_juvy_process_backup_entries()` - Main backup orchestration with include/exclude pattern support
- `_juvy_rsync_with_includes()` - Advanced rsync operations with pattern-based inclusion and retry logic
- `_juvy_add_directory_patterns()` and `_juvy_add_file_patterns()` - Generate rsync include patterns for proper directory/file handling
- `_juvy_parse_backup_entry()` - Parses backup file entries supporting comments and exclusions

**Restore Processing**:

- `_juvy_perform_restore()` - Main restore orchestration with safety backup creation
- `_juvy_rsync_restore()` - Single-operation bulk restore with error handling and retry logic
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
- `~/.config/juvy/log` - Error logging

## Development Commands

### Testing

```bash
# Manual testing - there's a manual_test/ directory but no automated tests
# Test basic functionality:
juvy init      # Initialize with auto-detection
juvy validate  # Validate backup configuration  
juvy backup    # Create backup
juvy list      # Verify tracked files
juvy status    # Check for changes

# Test git integration:
juvy git status              # Check git status
juvy git log --oneline       # View backup history
juvy git show HEAD           # View latest backup details
juvy git diff HEAD~1 HEAD    # Compare last two backups
```

### Installation

```bash
# Install from repository
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh

# Local development installation
./install.sh
```

### Version Management

- Version is hardcoded in `JUVY_VERSION` variable in juvy.zsh
- Update mechanism downloads from GitHub main branch

## Important Implementation Details

### Path Handling

The system supports three path formats:

- Explicit tilde paths: `~/.zshrc`
- Absolute paths: `/etc/hosts`
- Implicit home-relative: `.zshrc` (treated as `~/.zshrc`)

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
- **HOME directory sync**: Single rsync operation for all home directory files using include patterns
- **SYSTEM directory sync**: Single rsync operation for all system files using include patterns  
- **Pattern-based inclusion**: Uses `--include-from` with generated patterns for directories and files
- **Deletion management**: Uses `--delete` and `--delete-excluded` to maintain exact mirrors
- **Directory handling**: Generates hierarchical patterns (parent dirs + recursive `**` patterns) for proper directory inclusion

**Restore Strategy (Single-Operation Approach)**:
- **Bulk restore**: Single rsync operation copies entire backup structure back to filesystem
- **Safety backups**: Creates timestamped backup of current files before restore
- **Git exclusion**: Excludes `.git` directory from restore to avoid restoring backup metadata
- **Permission handling**: Uses `--ignore-errors` and treats partial transfers as success when data is transferred

### Error Handling

- Comprehensive rsync retry logic for transient errors (timeouts, I/O errors) 
- Both backup and restore operations include 3-retry mechanism with exponential backoff
- Detailed error logging to `~/.config/juvy/log`
- User-friendly error messages with actionable suggestions
- Special handling for permission issues during restore operations

## Testing Strategy

Since there are no automated tests, when making changes:

1. Test core workflow: `init` → `add` → `validate` → `backup` → `list` → `status` → `restore`
2. Test backup operations: 
   - Individual files and directories with trailing slashes
   - Include/exclude pattern filtering
   - Directory pattern generation and hierarchical inclusion
   - Deletion of files not in backup source
3. Test restore operations:
   - Bulk restore functionality with safety backup creation
   - Permission handling on system directories
   - Git metadata exclusion during restore
4. Test edge cases: missing files, large directories, sensitive files
5. Test git operations: commits, remote push/pull if configured
6. Test error conditions: invalid paths, permission issues, network failures, rsync failures
7. Verify path resolution works correctly for all three path formats
8. Test retry logic for both backup and restore operations

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
- Rsync operations use specialized functions with retry logic:
  - `_juvy_rsync_with_includes()` for backup operations with pattern-based inclusion
  - `_juvy_rsync_restore()` for restore operations with bulk copying
  - `_juvy_rsync_with_delete()` for legacy operations (deprecated)
- Pattern generation uses helper functions `_juvy_add_directory_patterns()` and `_juvy_add_file_patterns()`
- All rsync functions include comprehensive error handling and user-friendly messages
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

