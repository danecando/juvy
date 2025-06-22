# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Rules

- Use temporary files in `tmp/` directory for testing. Never modify user's real config files.

## Project Overview

juvy is a dotfile backup utility written in Zsh using rsync + git for versioned backups. Single file architecture in `juvy/juvy.zsh` (~2700 lines).

## Architecture

**Entry Point**: `juvy()` function dispatches to `_juvy_*` functions based on first argument.

**Key Functions**:
- `_juvy_entry_to_source_path()` - Converts backup entries to filesystem paths
- `_juvy_entry_to_backup_path()` - Maps entries to backup storage locations  
- `_juvy_process_backup_entries()` - Main backup orchestration
- `_juvy_perform_restore()` - Main restore orchestration

**Backup Strategy**: Two rsync operations (HOME vs SYSTEM files) with pattern-based inclusion
**Restore Strategy**: Single bulk rsync operation with safety backups
**Git Integration**: Auto-commits after backup, optional remote sync
**Retry Logic**: 3-retry mechanism with exponential backoff for rsync operations

**Config Files**:
- `~/.config/juvy/config` - Shell variables (JUVY_BACKUP_DIR, remote settings)
- `~/.config/juvy/backup` - List of files/directories to backup
- `~/.config/juvy/log` - Error logging

## Path Handling

Three formats supported:
- Explicit tilde: `~/.zshrc`
- Absolute: `/etc/hosts`  
- Implicit home-relative: `.zshrc` (treated as `~/.zshrc`)

Backup storage uses absolute filesystem structure: `/Users/user/.zshrc` → `{backup_dir}/Users/user/.zshrc`

## Backup File Format

```bash
~/.zshrc                    # Single file
~/.config/nvim/             # Directory (trailing slash required)
!~/.config/nvim/undo/       # Exclude directory
~/.gitconfig                # Git configuration
```

## Testing

**Test Framework**: 
- `tests/test-framework.zsh` - Basic test utilities
- `tests/juvy-test-setup.zsh` - Isolated test environment setup

**Test Environment Setup**:
```bash
# Setup with fixture set
setup_juvy_test_env "test-name" "testuser" "fixture-set"
load_test_fixtures
create_backup_entries_from_fixtures
load_juvy_for_test

# Cleanup
cleanup_test_env
```

**Fixture Organization**:
```
tests/fixtures/
├── single-backup/
│   ├── home/.zshrc
│   └── backup-entries
└── complex-workflow/
    ├── home/.config/nvim/
    ├── etc/hosts
    └── backup-entries
```

**Unit Tests**: Test individual functions in isolation using temp files
**Integration Tests**: Use full test environment with fixture sets

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

## Development Commands

```bash
# Core workflow testing
juvy init && juvy backup && juvy status && juvy restore

# Run tests
./tests/run-tests.sh
./tests/integration/test-single-backup.zsh
```