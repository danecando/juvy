#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# juvy.sh - dotfile backup utility (generated)
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

# Global state variables (replaces zsh associative array)
_JUVY_VERSION=""
_JUVY_CONFIG_DIR=""
_JUVY_CONFIG_FILE=""
_JUVY_BACKUP_FILE=""
_JUVY_LOG_FILE=""
_JUVY_BACKUP_DIR=""
_JUVY_REMOTE_URL=""
_JUVY_REMOTE_PUSH=""
_JUVY_REMOTE_NAME=""
_JUVY_PLATFORM=""
_JUVY_USE_COLOR="false"
_JUVY_VERBOSE="false"
_JUVY_DEBUG="false"

_JUVY_COLOR_INFO=""
_JUVY_COLOR_WARN=""
_JUVY_COLOR_ERROR=""
_JUVY_COLOR_SUCCESS=""
_JUVY_COLOR_RESET=""

# Global arrays for backup entry collection (Bash 3.2 compatible)
_JUVY_INCLUDE_PATHS=()
_JUVY_EXCLUDE_PATTERNS=()

# Detect platform for cross-platform compatibility
_juvy_detect_platform() {
  case "$(uname -s)" in
    Darwin) _JUVY_PLATFORM="macos" ;;
    Linux)  _JUVY_PLATFORM="linux" ;;
    *)      _JUVY_PLATFORM="unknown" ;;
  esac
}

# Get default backup directory based on platform
# Args: $1 = "icloud" to use iCloud path on macOS, anything else for local
_juvy_default_backup_dir() {
  local use_icloud="${1:-}"
  local host_name
  host_name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

  case "$_JUVY_PLATFORM" in
    macos)
      if [[ "$use_icloud" == "icloud" ]]; then
        echo "$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy/$host_name"
      else
        echo "$HOME/.local/share/juvy/$host_name"
      fi
      ;;
    *)
      echo "${XDG_DATA_HOME:-$HOME/.local/share}/juvy/$host_name"
      ;;
  esac
}

# Initialize paths and constants. Called at start of juvy().
# Supports environment variable overrides for testing.
_juvy_init_paths() {
  # Detect platform first
  _juvy_detect_platform

  # Version constant
  _JUVY_VERSION="1.0.1"

  # Config directory - respect environment override for testing
  if [[ -n "${JUVY_CONFIG_DIR:-}" ]]; then
    _JUVY_CONFIG_DIR="$JUVY_CONFIG_DIR"
  else
    _JUVY_CONFIG_DIR="$HOME/.config/juvy"
  fi

  # Derived paths
  _JUVY_CONFIG_FILE="$_JUVY_CONFIG_DIR/config"
  _JUVY_BACKUP_FILE="$_JUVY_CONFIG_DIR/backup"
  _JUVY_LOG_FILE="$_JUVY_CONFIG_DIR/log"

  _juvy_init_output
}

_juvy_is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

_juvy_init_output() {
  if _juvy_is_truthy "${JUVY_VERBOSE:-}"; then
    _JUVY_VERBOSE="true"
  else
    _JUVY_VERBOSE="false"
  fi

  if _juvy_is_truthy "${JUVY_DEBUG:-}"; then
    _JUVY_DEBUG="true"
  else
    _JUVY_DEBUG="false"
  fi

  if [[ -n "${JUVY_COLOR:-}" ]]; then
    if _juvy_is_truthy "${JUVY_COLOR:-}"; then
      _JUVY_USE_COLOR="true"
    else
      _JUVY_USE_COLOR="false"
    fi
  elif [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    _JUVY_USE_COLOR="true"
  else
    _JUVY_USE_COLOR="false"
  fi

  if [[ "$_JUVY_USE_COLOR" == "true" ]]; then
    _JUVY_COLOR_INFO="\033[0;36m"
    _JUVY_COLOR_WARN="\033[0;33m"
    _JUVY_COLOR_ERROR="\033[0;31m"
    _JUVY_COLOR_SUCCESS="\033[0;32m"
    _JUVY_COLOR_RESET="\033[0m"
  else
    _JUVY_COLOR_INFO=""
    _JUVY_COLOR_WARN=""
    _JUVY_COLOR_ERROR=""
    _JUVY_COLOR_SUCCESS=""
    _JUVY_COLOR_RESET=""
  fi
}

_juvy_out_info() {
  printf "%b\n" "${_JUVY_COLOR_INFO}[INFO]${_JUVY_COLOR_RESET} $*"
}

_juvy_out_warn() {
  printf "%b\n" "${_JUVY_COLOR_WARN}[WARN]${_JUVY_COLOR_RESET} $*" >&2
}

_juvy_out_error() {
  printf "%b\n" "${_JUVY_COLOR_ERROR}[ERROR]${_JUVY_COLOR_RESET} $*" >&2
}

_juvy_out_success() {
  printf "%b\n" "${_JUVY_COLOR_SUCCESS}[OK]${_JUVY_COLOR_RESET} $*"
}
