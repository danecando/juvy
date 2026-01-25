# juvy

Simple dotfile backup utility using rsync + git for versioned backups.

Works with bash and zsh on macOS and Linux. Automatically detects common dotfiles during setup. Default backup directory syncs via iCloud on macOS.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | bash
```

Then restart your shell or open a new terminal.

## Quick Start

```bash
juvy init    # Initialize and auto-detect common dotfiles
juvy backup  # Create your first backup
juvy list    # See what's being tracked
```

## Commands

### Setup

- `juvy init` - Initialize configuration with smart dotfile detection
- `juvy add [files...]` - Add files/directories to backup list
- `juvy remove [files...]` - Remove files/directories from backup list
- `juvy doctor [--fix]` - Validate configuration

### Backup & Restore

- `juvy backup` - Backup all tracked files with git versioning
- `juvy restore [--dry-run]` - Restore files from latest backup
- `juvy list` - Show tracked files
- `juvy status [file]` - Show changes since last backup

### Git Integration

```bash
juvy git log --oneline      # View backup history
juvy git show HEAD          # Latest backup details
juvy git diff HEAD~1 HEAD   # Compare last two backups
```

### Remote Sync

- `juvy remote <url>` - Set remote URL and enable auto-sync
- `juvy remote` - Show current remote status
- `juvy remote off` - Disable remote
- `juvy remote push` - Manual push

### Maintenance

- `juvy update` - Update to latest version
- `juvy version` - Show version
- `juvy uninstall` - Uninstall (preserves backups)
- `juvy nuke` - Uninstall and delete all data

## Configuration

### Files

| File | Purpose |
|------|---------|
| `~/.config/juvy/config` | Settings (backup dir, remote URL) |
| `~/.config/juvy/backup` | List of files/directories to backup |
| `~/.config/juvy/log` | Operation history |

### Backup File Format

```bash
~/.zshrc                    # Single file
~/.config/nvim/             # Directory (trailing slash)
!~/.config/nvim/undo/       # Exclude pattern
~/.gitconfig                # Inline comment
```

Excludes take precedence over includes.

### Default Backup Directory

Backups are stored per-hostname for multi-machine setups:

| Platform | Path |
|----------|------|
| macOS (iCloud) | `~/Library/Mobile Documents/com~apple~CloudDocs/juvy/<hostname>` |
| macOS (local) | `~/.local/share/juvy/<hostname>` |
| Linux | `~/.local/share/juvy/<hostname>` |

### Backup Structure

```
backup_directory/
├── .git/
└── Users/
    └── username/
        ├── .zshrc
        ├── .gitconfig
        └── .config/
            └── nvim/
```

Files are stored using their absolute filesystem paths.

## Development

### Building

```bash
./scripts/build.sh  # Bundle src/ modules into juvy.sh
```

### Testing

Tests use [bats](https://github.com/bats-core/bats-core) and run in Docker:

```bash
# Run all tests
docker compose run --rm test

# Run specific test file
docker compose run --rm test bats tests/bats/backup.bats

# Interactive shell for debugging
docker compose run --rm shell
```

Tests also run on macOS (Bash 3.2) and Ubuntu in CI.
