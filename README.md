# juvy

Simple dotfile backup utility that uses rsync + git for versioned backups with smart defaults

Targets zsh environments with automatic detection of common dotfiles. Default backup directory is in iCloud Drive for seamless cross-device sync.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh
```

After installation, restart your shell or run:

```bash
source ~/.zshrc
```

The installer will:

- Create `~/.config/juvy` directory for config files
- Download the latest version
- Add juvy to your `.zshrc`
- Detect existing configurations
- Optionally run initial setup

## Quick Start

```bash
juvy init    # Initialize and auto-detect common dotfiles
juvy backup  # Create your first backup
juvy list    # See what's being tracked
```

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

## Enhanced Path Specifications

juvy supports an advanced backup file format with powerful pattern matching and exclusion capabilities:

### Basic Path Formats

```bash
juvy add ~/.zshrc           # Explicit tilde path
juvy add /Users/you/.zshrc  # Absolute path
juvy add .zshrc             # Implicit home-relative
juvy add ~/.config/nvim/    # Directory (note trailing slash)
juvy add /etc/hosts         # Absolute system paths
```

### Path Pattern Notes

The backup file format is straightforward - each line specifies a literal path to include or exclude. Shell glob patterns are not expanded by juvy itself, but you can add multiple specific paths as needed:

```bash
~/.zshrc                    # Specific file
~/.bashrc                   # Another specific file  
~/.config/nvim/             # Entire directory (trailing slash)
~/.ssh/config               # Specific file in subdirectory
```

### Exclusion Patterns

Add exclusion patterns to your backup file with `!` prefix:

```bash
!~/.config/nvim/undo/       # Exclude undo directory from nvim config
!~/.config/nvim/swap/       # Exclude swap files directory
!~/.ssh/id_rsa              # Exclude SSH private key
!~/.ssh/id_ed25519          # Exclude SSH private key
```

### Inline Comments

```bash
~/.zshrc                    # Main shell configuration
~/.config/secrets/          # Local secrets (consider excluding)
!~/.config/nvim/swap/       # Exclude swap files
```

### Advanced Backup File Example

```bash
# Core shell configuration
~/.zshrc                    # Main zsh config
~/.bashrc                   # Bash fallback
~/.profile                  # Login profile

# Editor configurations  
~/.config/nvim/             # Neovim config directory
!~/.config/nvim/undo/       # Exclude volatile undo files
!~/.config/nvim/.netrwhist  # Exclude netrw history

# Development tools
~/.gitconfig                # Git global settings
~/.config/gh/               # GitHub CLI config
!~/.config/gh/logs/         # Exclude log files

# SSH configuration (sensitive)
~/.ssh/config               # SSH client config
~/.ssh/known_hosts          # Known hosts
!~/.ssh/id_rsa              # Exclude private key
!~/.ssh/id_ed25519          # Exclude private key
```

All files are stored using their absolute filesystem paths in the backup for straightforward restore operations (e.g., `/Users/you/.zshrc` → `{backup_dir}/Users/you/.zshrc`).

## Smart Features

### Automatic Detection

- Scans for common dotfiles during `juvy init`
- Categorizes files as recommended, sensitive, or optional
- Interactive selection with security warnings

### Validation & Safety

- Validates file existence before backup
- Warns about large directories (>100MB)
- Detects sensitive files (SSH keys, certificates, tokens)
- Creates safety backups before restore operations
- Interactive prompts for confirmation

### Advanced Backup & Restore

- **Efficient backup**: Two-operation strategy (HOME + SYSTEM) with pattern-based rsync inclusion
- **Bulk restore**: Single-operation restore with safety backup creation
- **Directory handling**: Proper hierarchical pattern generation for complete directory trees
- **Deletion management**: Maintains exact mirrors by removing files not in source
- **Error resilience**: Comprehensive retry logic for transient network/I/O failures

### Cross-Platform Storage

- Consistent backup format across different systems using absolute paths
- Simple restore operations thanks to preserved filesystem structure
- Git versioning with meaningful commit messages

### Remote Git Synchronization

- Optional git remote setup during initialization
- Automatic push to remote after each backup
- Manual remote management with `juvy remote` commands
- Support for GitHub, GitLab, and any git remote
- SSH and HTTPS authentication support

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

### Runtime Directories

- **`~/.config/juvy/safety-backup/`** - Timestamped backups created before restore operations

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

### Advanced Path Patterns

```bash
# Edit backup file directly for complex patterns
juvy add              # Opens $EDITOR with backup file

# Example advanced backup file content:
echo '# Development environment
~/.zshrc              # Shell config
~/.config/nvim/       # Editor config
!~/.config/nvim/undo/ # Exclude temporary files
~/.*rc                # All rc files (glob)
!*.log                # Exclude all logs
~/.ssh/config         # SSH config
!~/.ssh/id_*          # Exclude private keys' >> ~/.config/juvy/backup

# Validate patterns
juvy validate
```
