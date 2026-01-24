emulate -L zsh
# ------------------------------------------------------------------------------
# juvy.zsh - dotfile backup utility (generated)
# ------------------------------------------------------------------------------
# This file is generated from the src/ modules via scripts/build.sh.
# The script is organized into the following sections. Search for the
# corresponding headers to quickly jump to an area:
#   CONFIGURATION FUNCTIONS
#   UTILITY FUNCTIONS
#   BACKUP FUNCTIONS
#   RESTORE FUNCTIONS
#   GIT/REMOTE FUNCTIONS
#   SCHEDULING FUNCTIONS
#   COMMAND DISPATCHER & HELP
# ------------------------------------------------------------------------------

# Single global associative array for all juvy state.
# Environment variables can override paths for testing:
#   JUVY_CONFIG_DIR - base config directory (others derive from this)
typeset -gA _JUVY_CONFIG

# Initialize paths and constants. Called at start of juvy().
# Supports environment variable overrides for testing.
_juvy_init_paths() {
  # Version constant
  _JUVY_CONFIG[version]="1.0.1"

  # Config directory - respect environment override for testing
  if [[ -n "${JUVY_CONFIG_DIR:-}" ]]; then
    _JUVY_CONFIG[config_dir]="$JUVY_CONFIG_DIR"
  else
    _JUVY_CONFIG[config_dir]="$HOME/.config/juvy"
  fi

  # Derived paths
  _JUVY_CONFIG[config_file]="${_JUVY_CONFIG[config_dir]}/config"
  _JUVY_CONFIG[backup_file]="${_JUVY_CONFIG[config_dir]}/backup"
  _JUVY_CONFIG[log_file]="${_JUVY_CONFIG[config_dir]}/log"
}
