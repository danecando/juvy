# juvy

Simple dot/config file backup utility that uses rsync to backup files to a specified directory

Currently targets macOS devices that use zsh as their shell. Default backup directory is in iCloud Drive.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh
```

After installation, restart your shell or run:
```bash
source ~/.zshrc
```

The installer will:
- Create `~/.juvy/` directory for juvy files
- Download the latest version
- Add juvy to your `.zshrc`
- Detect existing configurations
- Optionally run initial setup

## Commands

- `juvy init` - Initialize juvy configuration
- `juvy add [files...]` - Add files to backup list (or edit with $EDITOR)
- `juvy backup` - Backup files to configured directory
- `juvy git <args>` - Run git commands in backup directory
- `juvy update` - Update juvy to the latest version
- `juvy version` - Show version information
- `juvy uninstall` - Remove juvy from system (preserves backups)
- `juvy nuke` - Completely destroy juvy and all backups

## Configuration

- `$HOME/.config/juvy/config` - juvy config: backup directory
- `$HOME/.config/juvy/backup` - file paths relative to $HOME to backup

## Usage

1. **Initialize**: Run `juvy init` to set up configuration
2. **Add files**: Use `juvy add ~/.vimrc` to add files to backup list
3. **Backup**: Run `juvy backup` to backup all tracked files
4. **Git operations**: Use `juvy git log` to view backup history
