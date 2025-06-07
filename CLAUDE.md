# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

juvy is a simple dot/config file backup utility for macOS that uses rsync to backup files to a specified directory (default: iCloud Drive). The entire codebase consists of a single zsh script that provides commands for initialization, backup, and cleanup.

## Architecture

The project is a single zsh script (`juvy.zsh`) that:
- Maintains configuration in `$HOME/.config/juvy/`
- Uses rsync to backup files listed in `$HOME/.config/juvy/backup`
- Stores backups in a git repository (default: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy`)
- Automatically commits changes with timestamps

## Key Functions

- `juvy()`: Main entry point that dispatches to subcommands
- `_juvy_init()`: Sets up config directory and files
- `_juvy_backup()`: Performs rsync backup and git commit
- `_juvy_rm()`: Removes config and backup directories
- `_juvy_git()`: Wrapper for git commands in backup directory

## Development Notes

- The script uses `emulate -L zsh` for consistent zsh behavior
- Default backup location uses escaped spaces for iCloud path
- Git repository is initialized in the backup directory during first run
- Commits only occur when there are actual changes (checked via `git status --porcelain`)

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