# juvy

Simple dot/config file backup utility that uses rsync to backup files to a specified directory

Currently targets macOS devices that use zsh as their shell. Default backup directory is in iCloud Drive.

## Installation

### Quick Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/danecando/juvy/main/install.sh | zsh
```

### Manual Install

```bash
# Clone the repository
git clone https://github.com/danecando/juvy.git
cd juvy

# Run the installer
zsh install.sh
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

- `juvy init` - Set up backup directories and configuration
- `juvy backup` - Backup all files in the backup list
- `juvy rm` - Remove all config files and backup directory

## Configuration

- `$HOME/.config/juvy/config` - juvy config: backup directory
- `$HOME/.config/juvy/backup` - file paths relative to $HOME to backup
