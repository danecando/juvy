# juvy Project Notes

## Project Vision
Transform juvy from a personal script into a simple but reliable dotfile backup tool that others can use on macOS with zsh. The goal is to maintain zero external dependencies while providing a trustworthy, easy-to-use solution for backing up configuration files.

## Core Philosophy
- **Minimal and focused** - does one thing well
- **Zero dependencies** - pure zsh with no external requirements
- **Simple but robust** - easy to use, hard to break
- **User controlled** - no daemons or automatic scheduling
- **Transparent** - users understand what's happening

## How juvy Currently Works

### Architecture Overview
juvy uses rsync for efficient file copying and git for version control. This provides enterprise-grade backup capabilities with a simple shell script interface.

### Configuration Structure

**Config Files:**
- `$HOME/.config/juvy/config` - Settings (currently just `JUVY_BACKUP_DIR`)
- `$HOME/.config/juvy/backup` - List of files to backup (one path per line)

**Default Setup:**
- Backup directory: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy` (iCloud)
- Initial backup list: `/.zshrc` and `/.gitconfig` (relative to $HOME)

### Operational Flow

1. **Initialization (`juvy init`):**
   - Creates config directory at `$HOME/.config/juvy/`
   - Creates backup list with default files
   - Prompts for backup location (or uses iCloud default)
   - Initializes a git repo in the backup directory

2. **Backup Process (`juvy backup`):**
   - Uses rsync with `--files-from` to copy files listed in backup file
   - Source: `$HOME`, Destination: `$JUVY_BACKUP_DIR`
   - If changes detected (via `git status --porcelain`), commits with timestamp

3. **File Storage Structure:**
   ```
   $JUVY_BACKUP_DIR/
   ├── .git/
   ├── .zshrc
   └── .gitconfig
   ```
   Files maintain their relative paths from $HOME

### Example Workflow
```bash
# After init, your backup list has:
/.zshrc
/.gitconfig

# Running backup executes:
rsync -a --files-from="$HOME/.config/juvy/backup" "$HOME" "$JUVY_BACKUP_DIR"
# This copies $HOME/.zshrc → $JUVY_BACKUP_DIR/.zshrc
# And $HOME/.gitconfig → $JUVY_BACKUP_DIR/.gitconfig

# Git commit with message: "Backup: 2024-12-06 14:30:45"
```

## Current State (December 2024)

### ✅ Completed Features
- **Installation system** - Working curl installer with update support
- **Version management** - `juvy update` with version checking
- **File management** - `juvy add` command with editor integration
- **Git integration** - `juvy git` wrapper for backup repository operations
- **Clean removal** - `juvy uninstall` (preserves backups) and `juvy nuke` (destroys everything)
- **Help system** - Comprehensive command documentation
- **Zsh best practices** - Code follows manual-verified patterns with proper quoting
- **Error handling** - Input validation and user confirmation prompts

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

### Strengths
- Minimal and focused - does one thing well
- No dependencies, pure zsh with proper error handling
- Git integration for versioning with commit automation
- Simple rsync approach with efficient incremental backups
- Clean function namespace with `_juvy_` prefix
- Proper use of `emulate -L zsh` and zsh idioms
- Professional installation/update system
- Self-contained with version management

## Critical Issues & Areas for Improvement

### 🚨 High Priority Issues (GitHub Issues #2-5)

1. **No Restore Functionality** (Issue #5)
   - Critical missing feature - users cannot restore backed up files
   - Need `juvy restore` with safety backups and permission preservation

2. **Limited Error Handling** (Issue #2)
   - rsync failures can occur silently, potentially corrupting backups
   - Need to catch and interpret rsync exit codes
   - Add operation logging for debugging

3. **Path Validation Missing** (Issue #3)
   - Users can accidentally add huge directories or non-existent files
   - Need size warnings and existence validation
   - Prevent backup corruption from bad inputs

4. **Sensitive File Exposure** (Issue #4)
   - No warnings about backing up SSH keys, credentials to cloud storage
   - Need detection patterns and security warnings
   - Major privacy/security risk

### 📋 Medium Priority Issues (GitHub Issues #6-8)

5. **Directory Structure Limitations** (Issue #6)
   - Current `rsync --files-from` only handles individual files
   - Many configs are directories (nvim, ssh) that need recursive handling
   - Empty directories get lost

6. **No User Visibility** (Issue #7)
   - Users don't know what's tracked or what changed
   - Need `juvy list`, `juvy status`, `juvy diff` commands
   - Transparency is crucial for trust

7. **Basic Restore Only** (Issue #8)
   - Need selective restore, dry-run, point-in-time restore
   - Current plan too simple for real-world use

### 🔮 Advanced Features (GitHub Issues #9-11)

8. **Enhanced Path Specifications** (Issue #9)
   - Support absolute paths, exclusions, permission hints
   - More flexible backup file format

9. **Smart Defaults** (Issue #10)
   - New users don't know what to backup
   - Detect common dotfiles and suggest them

10. **Operation Logging** (Issue #11)
    - Basic logging for troubleshooting without complex state management

## Design Decisions & Architecture

### Key Design Choices
1. **rsync over cp:** Efficient incremental copies, handles permissions/symlinks
2. **Git for versioning:** Provides history without implementing versioning
3. **Simple text files for config:** Easy to edit and debug
4. **No daemon/scheduling:** User controls when backups happen
5. **Relative paths from $HOME:** Maintains directory structure consistency

### Why rsync + git Works
- **rsync** handles the heavy lifting: incremental backups, permission preservation, symlink handling
- **git** provides version control: history, branching, remote sync capabilities
- **Zero dependencies** - both tools are standard on Unix systems
- **Battle-tested** - used by enterprise backup solutions worldwide

### Performance Characteristics

**Current Efficiency:**
- `rsync -a` only copies changed files (very efficient)
- Git commits only when changes exist (good use of `--porcelain`)
- No unnecessary file scanning or processing
- Simple file list reading

**Potential Issues at Scale:**
1. **Large Binary Files** - Git stores full copies, could slow down
2. **Many Small Files** - Git can slow with thousands of files
3. **Symlink Handling** - Restore might break if target doesn't exist

**Performance Verdict:** For typical dotfile use cases (<100 files, mostly text), current approach is appropriately simple and efficient.

## Security Considerations

### Current Risks
1. **Sensitive Data in Cloud** - SSH keys, credentials backed up to iCloud
2. **Permission Loss** - Restored files might not have correct permissions
3. **No Encryption** - All backup data stored in plaintext
4. **No Validation** - Users can backup anything without warnings

### Mitigation Strategies
1. **Sensitive File Detection** - Warn about private keys, credentials
2. **Permission Preservation** - Maintain file permissions in backups
3. **Local-only Option** - Alternative to cloud storage for sensitive data
4. **User Education** - Clear security guidance in documentation

## Implementation Strategy

### Phase 1: Core Safety & Reliability
**Goal:** Make juvy trustworthy for production use
- Enhanced error handling with proper rsync exit code checking
- Path validation and size warnings for large directories
- Sensitive file detection with security warnings
- Basic restore functionality with safety backups

### Phase 2: Essential Features
**Goal:** Provide missing core functionality
- Full directory support for recursive backups
- List/status/diff commands for user visibility
- Enhanced restore options (selective, dry-run, point-in-time)

### Phase 3: Advanced Features
**Goal:** Polish and power-user features
- Enhanced path specifications (absolute paths, exclusions)
- Smart defaults for common dotfiles
- Operation logging for troubleshooting

## Technical Debt & Future Considerations

### Platform Flexibility
Currently macOS/iCloud specific, but designed to be easily portable:
- Use `${XDG_CONFIG_HOME:-$HOME/.config}` for Linux compatibility
- Auto-detect cloud storage providers
- Abstract platform-specific operations

### Backup Format Evolution
Current simple text format works but could be enhanced:
```bash
# Current format
/.zshrc
/.gitconfig

# Future enhanced format
/.zshrc                      # File relative to $HOME
/.config/nvim/               # Directory (recursive)
/.ssh/config -> 600          # With permission hints
@/etc/hosts                  # Absolute path
!*.log                       # Exclusion pattern
```

### Metadata Management
Leverage git for most metadata rather than maintaining separate state:
- Git log provides backup history
- Git status shows changes
- Git diff shows file differences
- Only add minimal logging for troubleshooting

## Long-term Vision

### Core Principles (Unchanged)
- Remain simple and focused
- Maintain zero external dependencies
- Keep installation and usage friction minimal
- Prioritize reliability over features

### Future Possibilities
- **Homebrew tap** when stable
- **Plugin ecosystem** for advanced features
- **Cross-platform support** (Linux, Windows WSL)
- **Integration** with shell frameworks (oh-my-zsh, etc.)

### Success Metrics
- **Reliability** - No data loss, clear error messages
- **Usability** - New users can start backing up in < 5 minutes
- **Trust** - Users confident in backup/restore process
- **Simplicity** - Maintains single-purpose focus

## Implementation Status

**GitHub Issues Created:** #2-13 covering all planned improvements
**Current Priority:** Core Safety & Reliability (Issues #2-5)
**Timeline:** 6 weeks to complete all phases
**Next Action:** Implement enhanced error handling (Issue #2)

This document serves as the complete reference for juvy's current state, design philosophy, identified issues, and development roadmap.