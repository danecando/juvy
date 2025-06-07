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