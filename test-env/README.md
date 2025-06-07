# Test Environment

This directory contains a mock home environment for testing juvy functionality safely.

## Usage

```bash
# Set up test environment
source test-env/setup-test-env.sh

# Test juvy commands (they'll use the mock home)
source juvy/juvy.zsh
juvy init
juvy list

# Restore original environment
unset HOME JUVY_CONFIG_DIR JUVY_BACKUP_DIR

# Clean up test artifacts
./test-env/cleanup-test-env.sh
```

## Structure

- `mock-home/` - Fake home directory with sample dotfiles
- `setup-test-env.sh` - Script to configure test environment
- `cleanup-test-env.sh` - Script to clean up test artifacts

## Mock Dotfiles Included

- Shell configs: `.zshrc`, `.bashrc`
- Git: `.gitconfig`
- Editors: `.vimrc`, `.config/nvim/`
- SSH: `.ssh/config`, `.ssh/known_hosts` (sensitive)
- Terminal: `.tmux.conf`, `.alacritty.yml`
- Tools: `.npmrc`, `.config/gh/`