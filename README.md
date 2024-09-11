# juvy

Simple dot/config file backup utility that uses rsync to backup files to a specified directory

Currently targets MacOS devices that use zsh as their shell. Default backup directory is in iCloud Drive.

You probably don't want to use it in it's current state. Feel free to help make it better.

## Installation

Load the script in your .zshrc

```bash
source $HOME/repos/juvy/juvy.zsh
```

## Commands

- `juvy init` - Set up all the necessary directories and files
- `juvy backup` - Backup all files in the backup list
- `juvy rm` - Remove all the config files and backup directory

## Configuration

- `$HOME/.config/juvy/config` - juvy config: backup directory
- `$HOME/.config/juvy/backup` - file paths relative to $HOME to backup
