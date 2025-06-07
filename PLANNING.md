# juvy Planning Document

## Project Vision
Transform juvy from a personal script into a simple but reliable dotfile backup tool that others can use on macOS with zsh.

## Current State Analysis (Updated Dec 2024)

### ✅ Completed Features
- **Installation system** - Working curl installer with update support
- **Version management** - `juvy update` with version checking
- **File management** - `juvy add` command with editor integration
- **Git integration** - `juvy git` wrapper for backup repository operations
- **Clean removal** - `juvy uninstall` (preserves backups) and `juvy nuke` (destroys everything)
- **Help system** - Comprehensive command documentation
- **Zsh best practices** - Code follows manual-verified patterns with proper quoting
- **Error handling** - Input validation and user confirmation prompts

### Strengths
- Minimal and focused - does one thing well
- No dependencies, pure zsh with proper error handling
- Git integration for versioning with commit automation
- Simple rsync approach with efficient incremental backups
- Clean function namespace with `_juvy_` prefix
- Proper use of `emulate -L zsh` and zsh idioms
- Professional installation/update system
- Self-contained with version management

### ❌ Remaining Weaknesses
- **No restore functionality** - Critical missing feature (highest priority)
- **Limited error handling** - rsync failures not properly caught
- **No path validation** - Doesn't check if backup paths exist before backup
- **Platform-specific** - Hardcoded macOS/zsh paths with iCloud defaults
- **Missing preview features** - No dry-run, diff preview, or selective operations

## Installation Strategy

### ✅ Current Implementation
```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh
```

**Features:**
- Downloads latest version to `~/.juvy/juvy.zsh`
- Automatically adds to `.zshrc`
- Detects existing configurations
- Handles updates via `juvy update` command
- Version management and conflict resolution

### Future Installation Options
1. **Homebrew tap** (When stable)
```bash
brew tap danecando/juvy
brew install juvy
```

2. **Package managers** (asdf, zinit, oh-my-zsh plugins)

## Feature Priority List (Updated)

### ✅ Completed
- ~~**Add/remove commands**~~ - `juvy add` implemented with editor support
- ~~**Help system**~~ - Comprehensive help via `juvy` command
- ~~**Version info**~~ - `juvy version` and `juvy update` system

### 🚨 High Priority (Remaining)
1. **Restore functionality** - Recover backed up files to original locations
   - `juvy restore` - Restore all files
   - `juvy restore <file>` - Restore specific file
   - `juvy restore --dry-run` - Preview restore operations
2. **Enhanced error handling** - Catch rsync failures and provide clear messages
3. **Path validation** - Check files exist before backup operations

### 📋 Medium Priority
4. **List command** - Show currently tracked files (`juvy list`)
5. **Diff/preview command** - Show what changed before backup (`juvy diff`)
6. **Dry-run option** - Preview what backup would do (`juvy backup --dry-run`)

### 🔮 Low Priority
7. **Platform flexibility** - Support different cloud storage providers
8. **Selective operations** - Choose specific files to backup/restore
9. **Backup scheduling** - Integration with cron/launchd
10. **Configuration validation** - Verify backup directory accessibility

## Implementation Details

### Restore Feature Design (Next Major Feature)
```bash
juvy restore                    # Restore all files from latest backup
juvy restore <file>             # Restore specific file
juvy restore --dry-run          # Preview what would be restored
juvy restore --list             # Show available files to restore
```

**Implementation approach:**
- Use rsync to copy from backup directory back to `$HOME`
- Confirm before overwriting existing files
- Support partial path matching for convenience
- Handle symlinks and permissions correctly

### Enhanced Error Handling
- Check rsync exit codes and provide meaningful errors
- Validate paths exist before backup operations
- Verify backup directory is accessible and has git repo
- Handle missing source files gracefully
- Add rollback capabilities for failed operations

### Current Command Set
```bash
juvy init               # Initialize configuration
juvy add [files...]     # Add files to backup list (or edit with $EDITOR)
juvy backup             # Backup all tracked files
juvy git <args>         # Run git commands in backup directory
juvy update             # Update juvy to latest version
juvy version            # Show version information
juvy uninstall          # Remove juvy (preserve backups)
juvy nuke              # Destroy everything including backups
```

## Immediate Next Steps
1. **Update README.md** - Reflect current command set and features
2. **Implement restore functionality** - Core missing feature for usability
3. **Add error handling** - Make backup operations more reliable
4. **Add list command** - Show tracked files for user awareness

## Long-term Vision
- Remain a simple, focused dotfile backup tool
- Maintain zero external dependencies
- Keep installation and usage friction minimal  
- Consider plugin ecosystem for advanced features