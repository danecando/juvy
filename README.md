# juvy

Simple dotfile backup utility that uses rsync + git for versioned backups with smart defaults

Targets zsh environments with automatic detection of common dotfiles. Default backup directory is in iCloud Drive for seamless cross-device sync.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh
source ~/.zshrc
```

The installer will:

- Download the latest version
- Add juvy to your `.zshrc`

## Quick Start

```bash
juvy init    # Initialize and auto-detect common dotfiles
juvy backup  # Create your first backup
juvy list    # See what's being tracked
```

## Compatibility

juvy works on both GNU/Linux and macOS. If `gdate` from coreutils is
available it will be used for date calculations; otherwise the
platform's `date` command is used.

## Commands

### Setup and Configuration

- **`juvy init`** - Initialize juvy configuration with smart dotfile detection. Re-running allows changing settings with current values as defaults.
- **`juvy add [files...]`** - Add files/directories to backup list. Without arguments, opens backup file in `$EDITOR`.
  - Files: `juvy add ~/.zshrc` or `juvy add /etc/hosts`
  - Directories: `juvy add ~/.config/nvim/` (trailing slash required)
  - Multiple files: `juvy add ~/.zshrc ~/.gitconfig`
- **`juvy validate`** - Validate backup configuration without running backup

### Backup Operations

- **`juvy backup`** - Backup all tracked files with git versioning
- **`juvy restore`** - Restore all files from latest backup (creates safety backup first)
- **`juvy list`** - Show all tracked files and directories
- **`juvy status [file]`** - Show changes since last backup
  - Without arguments: Shows summary of all changes
  - With file argument: Shows detailed diff for specific file

### Git Integration

- **`juvy git <args>`** - Run git commands in backup directory

  ```bash
  # View backup history
  juvy git log --oneline
  juvy git log --graph --oneline --all
  
  # See details of a specific backup
  juvy git show HEAD
  juvy git show <commit-hash>
  
  # Check current git status
  juvy git status
  
  # View differences between commits
  juvy git diff HEAD~1 HEAD
  
  # Create a branch for testing
  juvy git checkout -b experiment
  juvy git checkout main
  
  # Reset to a previous state (careful!)
  juvy git reset --hard <commit-hash>
  ```

### Remote Synchronization

- **`juvy remote <url>`** - Set remote URL and enable auto-sync
- **`juvy remote`** - Show current remote status
- **`juvy remote off`** - Disable remote synchronization
- **`juvy remote push`** - Manually push to remote

### Maintenance

- **`juvy update`** - Update juvy to the latest version
- **`juvy version`** - Show version information
- **`juvy uninstall`** - Remove juvy from system (preserves backups)
- **`juvy nuke`** - Completely destroy juvy and all backups

## Configuration

### Configuration Files

- **`~/.config/juvy/config`** - Main configuration file with key-value pairs:
  - `JUVY_BACKUP_DIR` - Directory where backups are stored
  - `JUVY_REMOTE_URL` - Git remote URL for synchronization (optional)
  - `JUVY_REMOTE_PUSH` - Auto-push after backup (`true`/`false`)
  - `JUVY_REMOTE_NAME` - Git remote name (usually `origin`)

- **`~/.config/juvy/backup`** - List of files/directories to backup with support for:
  - Include patterns: `~/.zshrc`, `~/.config/nvim/`
  - Exclude patterns: `!~/.config/nvim/undo/`
  - Inline comments: `~/.zshrc # Main shell config`

- **`~/.config/juvy/log`** - Error logging and operation history

## Backup Structure

```
backup_directory/
├── .git/                   # Git versioning metadata
├── Users/                  # User home directory files
│   └── username/
│       ├── .zshrc
│       ├── .gitconfig
│       └── .config/
│           └── nvim/
└── etc/                    # System files (if any)
    └── hosts
```

## Usage Examples

### Basic Workflow

```bash
# Initialize with auto-detection
juvy init

# Add specific files
juvy add ~/.vimrc ~/.tmux.conf

# Add a directory
juvy add ~/.config/alacritty/

# Create backup
juvy backup

# Check what's tracked
juvy list

# See changes since last backup
juvy status

# View detailed changes for specific file
juvy status ~/.zshrc
```

### Advanced Usage

```bash
# Add SSH config (with security prompt)
juvy add ~/.ssh/config

# View backup history and details
juvy git log --oneline          # Compact history
juvy git log --graph --oneline   # Visual branch history  
juvy git show HEAD              # Latest backup details
juvy git diff HEAD~1 HEAD       # Compare last two backups

# Restore from backup (creates safety backup first)
juvy restore

# Validate configuration
juvy validate
```

### Remote Git Synchronization

```bash
# Add a git remote for cloud sync
juvy remote git@github.com:username/dotfiles.git

# Check remote status
juvy remote

# Manual push operations
juvy remote push

# Disable remote synchronization
juvy remote off

# Use git commands directly for advanced operations
juvy git remote -v                # View configured remotes
juvy git pull origin main         # Manual pull
juvy git push origin main         # Manual push
```
