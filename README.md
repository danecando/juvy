# juvy

Track your dotfiles and config without the hassle. 

`juvy` is a simple cross-platform backup utility written in bash. It uses rsync to automatically backup your files to a directory / git repo in the background. No symlinks or managing your files through another utility. Configure the files that you want to track and `juvy` will handle the rest. 

See [`CHANGELOG.md`](CHANGELOG.md) for release notes.

## Quick Start

```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | bash
```

```bash
juvy init
```

`juvy init` will automatically detect common configuration files to bootstrap your configuration. You can easily add new files to track at any time with `juvy add`.

## How It Works

Every shell startup triggers `juvy backup` in the background. rsync only copies changed files, git only commits if there's something new. No scheduling, no daemons, no overhead.

If multiple shell sessions start at once, `juvy` uses a backup lock and skips overlapping runs to avoid rsync/git races.

To disable automatic backups, remove the `juvy backup` line from your shell rc file (`~/.zshrc` or `~/.bashrc`).

## Commands

### Setup

- `juvy init` - Initialize configuration with smart dotfile detection
- `juvy add [files...]` - Add files/directories to backup list
- `juvy remove [files...]` - Remove files/directories from backup list
- `juvy doctor [--fix]` - Validate configuration

### Backup & Restore

- `juvy backup` - Backup tracked files (runs automatically on shell startup)
- `juvy restore [--dry-run]` - Restore files from latest backup
- `juvy restore --from-safety <path>` - Restore files from a safety backup directory
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
- `juvy remote push` - Fetch, auto-rebase, and push

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

### Config Options

Settings in `~/.config/juvy/config`:

| Option | Description | Default |
|--------|-------------|---------|
| `JUVY_BACKUP_DIR` | Path to backup directory | See "Default Backup Directory" below  |
| `JUVY_REMOTE_URL` | Git remote URL for syncing | (none) |
| `JUVY_REMOTE_PUSH` | Auto-push after backup when remote is configured | `true` |
| `JUVY_REMOTE_NAME` | Git remote name | `origin` |

Example config:

```bash
JUVY_BACKUP_DIR='/Users/<username>/Library/Mobile Documents/com~apple~CloudDocs/juvy/<hostname>'
JUVY_REMOTE_URL='git@github.com:username/dotfiles.git'
JUVY_REMOTE_PUSH='true'
JUVY_REMOTE_NAME='origin'
```

When `JUVY_REMOTE_PUSH` is enabled, backups automatically fetch, reconcile, and push to the remote repository. If another machine has pushed newer commits, juvy rebases local commits before pushing. Use `juvy status`, `juvy remote`, or `juvy doctor` to detect divergence and get guidance.

### Backup File Format

```bash
~/.zshrc                    # Single file
~/.config/nvim/             # Directory (trailing slash)
!~/.config/nvim/undo/       # Exclude pattern
~/.gitconfig                # Inline comment
```

Excludes take precedence over includes.

### Restore Safety Backups

`juvy restore` creates a safety snapshot of current files before applying restore changes. After restore completes, it prints an undo command:

```bash
juvy restore "<safety-backup-path>"
```

You can also preview a safety restore without changing files:

```bash
juvy restore --dry-run --from-safety "<safety-backup-path>"
```

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
