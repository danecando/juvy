# juvy Future Planning & Improvements

## Analysis of Current Design & Edge Cases

This document outlines critical issues, edge cases, and improvements identified during project review. These considerations will help evolve juvy into a more robust and trustworthy dotfile backup tool.

## Critical Design Issues

### 1. Path Structure Limitations

**Current Problem**: Only handles files relative to `$HOME`
```bash
# Current approach only supports:
/.zshrc  # → $HOME/.zshrc

# But users might need:
/etc/hosts                    # System files
/usr/local/etc/nginx.conf    # Local configs outside $HOME
~/.config/nvim/              # Entire directories
```

**Solution**: Enhanced path specification format in backup file:
```bash
# Proposed ~/.config/juvy/backup format:
/.zshrc                      # File relative to $HOME
/.config/nvim/               # Directory (recursive)
/.ssh/config -> 600          # With permission preservation  
!/Downloads/                 # Exclusion pattern
@/etc/hosts                  # Absolute path (requires sudo)
```

### 2. Directory Structure Gap

**Current Problem**: `rsync --files-from` only backs up individual files, not directory structures
- Breaks for configs like `~/.config/nvim/` (multiple files and subdirectories)
- SSH directory needs specific permissions preserved
- Empty directories that might be required are lost

**Solution**: Detect directory entries and handle recursively:
```bash
# If backup entry ends with /, treat as directory
if [[ "$line" == */ ]]; then
    rsync -a "$HOME/$line" "$JUVY_BACKUP_DIR/$line"
else
    rsync -a "$HOME/$line" "$JUVY_BACKUP_DIR/$line"
fi
```

### 3. Data Integrity & Safety Concerns

**Missing Verification**: No way to verify backups are complete or intact
- No checksums or integrity checks
- Silent rsync failures could corrupt backups
- No verification before restore operations

**Dangerous Edge Cases**:
- User accidentally adds `~/Downloads` or `~/Documents` - Git struggles with large files
- `juvy nuke` destroys only backup with no recovery option
- Network interruption during `juvy update` leaves broken installation

**Solutions**:
```bash
# Add integrity tracking
~/.config/juvy/
├── backup          # File list  
├── config          # Settings
├── checksums       # File integrity hashes
├── state           # Last backup metadata
└── log             # Operation history

# Size warnings
juvy add ~/Downloads
# → "⚠️  This directory contains 2.3GB. Large files can slow down backups. Continue? [y/N]"

# Pre-operation verification
juvy restore
# → "✓ Verifying backup integrity..."
# → "⚠️  Creating safety backup of current files..."
# → "Ready to restore 12 files. Continue? [Y/n]"
```

## Security & Privacy Issues

### Sensitive File Exposure

**Problems**:
- No warnings about backing up SSH keys, AWS credentials, etc.
- Cloud storage (iCloud) means sensitive data leaves the machine
- No encryption option for sensitive files

**Solutions**:
```bash
# Sensitive file detection patterns
SENSITIVE_PATTERNS=(
    "*id_rsa*"
    "*id_ed25519*" 
    "*.pem"
    "*credentials*"
    "*secrets*"
    "*.env"
)

# Warning system
juvy add ~/.ssh/id_rsa
# → "🔒 This appears to be a private key. Backing up to cloud storage may be a security risk."
# → "Consider: 1) Exclude this file, 2) Use local backup only, 3) Continue anyway"
```

### Permission Problems

**Issues**:
- SSH keys need 600 permissions or they won't work
- Some configs need specific ownership
- Symlinks might point to sensitive locations

**Solution**: Permission metadata storage:
```bash
# Store permissions alongside files
~/.config/juvy/permissions
# Format: path:mode:owner:group
/.ssh/config:600:dane:staff
/.ssh/id_rsa:600:dane:staff
```

## Enhanced Command Set Needed

### Status & Discovery Commands

**Missing transparency**:
```bash
juvy status         # What's changed since last backup?
juvy list           # List backed up files with sizes/dates
juvy list <file>    # Show history of specific file  
juvy diff [file]    # Compare current vs backed up
juvy check          # Verify backup integrity
juvy history        # Show backup operation log
```

### Improved File Management

**Current limitation**: Only basic file addition
```bash
# Enhanced file management needed:
juvy add "~/.config/nvim/**/*.vim"  # Glob patterns
juvy add ~/.ssh --exclude "*.key"   # Exclusions  
juvy add ~/.zshrc --as "shell/zsh"  # Organize backups
juvy remove <file>                  # Remove from tracking
juvy ignore <pattern>               # Add to ignore list
```

### Enhanced Restore Features

**Current plan too simple**:
```bash
juvy restore                    # Restore all files
juvy restore <file>             # Restore specific file
juvy restore --dry-run          # Preview what would be restored
juvy restore --list             # Show available files to restore

# Missing critical features:
juvy restore --at <date>        # Restore from specific commit
juvy restore --backup           # Backup current before overwriting
juvy restore --check            # Verify before restore
juvy restore --diff             # Show what will change
juvy restore --selective        # Choose which files to restore
```

## Implementation Priorities (Revised)

### Phase 1: Safety & Reliability
1. **Enhanced error handling** - Catch and report rsync failures properly
2. **Path validation** - Verify files exist before backup
3. **Size warnings** - Prevent accidental large file backups
4. **Integrity checking** - Add checksums for verification

### Phase 2: Core Usability  
5. **Status/list commands** - Give users visibility into backups
6. **Directory support** - Handle full directory structures
7. **Permission preservation** - Maintain file permissions and ownership
8. **Sensitive file detection** - Warn about private keys, credentials

### Phase 3: Advanced Features
9. **Enhanced restore** - With safety backups and selective options
10. **Pattern support** - Globs, exclusions, organized backup structure
11. **History/diff** - Compare current vs backed up states
12. **Local backup option** - Alternative to cloud storage for sensitive data

## Platform Considerations

### Current macOS/iCloud Assumptions
- Hardcoded iCloud path: `~/Library/Mobile Documents/com~apple~CloudDocs/juvy`
- Assumes zsh shell and specific directory structures
- Uses macOS-specific permission handling

### Future Platform Flexibility
```bash
# Abstract platform-specific operations
detect_cloud_storage() {
    # Try iCloud, Dropbox, Google Drive, OneDrive
    # Fall back to ~/.juvy-backup
}

get_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/juvy"
}

preserve_permissions() {
    case "$OSTYPE" in
        darwin*) 
            # macOS permission handling
            ;;
        linux*)
            # Linux permission handling  
            ;;
    esac
}
```

## Metadata & State Management

### Enhanced State Tracking
```bash
# ~/.config/juvy/state format:
{
    "last_backup": "2024-12-06T20:15:00Z",
    "total_files": 15,
    "total_size": "2.3MB", 
    "backup_location": "/Users/dane/Library/Mobile Documents/...",
    "juvy_version": "1.0.1",
    "integrity_check": "2024-12-06T20:15:00Z"
}

# ~/.config/juvy/log format:
2024-12-06 20:15:00 [BACKUP] Started backup of 15 files
2024-12-06 20:15:02 [BACKUP] ✓ Completed backup (2.3MB)
2024-12-06 20:15:02 [GIT] ✓ Committed changes: "Backup: 2024-12-06 20:15:00"
2024-12-06 20:16:30 [ADD] Added ~/.vimrc to backup list
```

## Risk Mitigation Strategies

### Data Loss Prevention
1. **Always backup before restore** - Create snapshot of current state
2. **Verify operations** - Check file integrity before and after operations
3. **Atomic operations** - Ensure operations complete fully or not at all
4. **Recovery points** - Maintain multiple backup states
5. **User confirmation** - Require explicit confirmation for destructive operations

### Security Best Practices
1. **Sensitive file warnings** - Alert users to potential security risks
2. **Local-only option** - Alternative to cloud storage for sensitive data
3. **Permission preservation** - Maintain secure file permissions
4. **Exclusion patterns** - Built-in patterns for common sensitive files

This document should guide the evolution of juvy from a simple backup script to a robust, trustworthy dotfile management system.