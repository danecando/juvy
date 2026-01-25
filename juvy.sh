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
  _JUVY_VERSION="1.1.0"

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
}

## CONFIGURATION FUNCTIONS ###################################################


_juvy_load_config() {
  local line key value

  _JUVY_BACKUP_DIR="$(_juvy_default_backup_dir)"
  _JUVY_REMOTE_URL=""
  _JUVY_REMOTE_PUSH=""
  _JUVY_REMOTE_NAME=""

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue

      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" ]] && continue

      [[ "$line" != *=* ]] && continue

      key="${line%%=*}"
      value="${line#*=}"

      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      [[ -z "$key" ]] && continue

      if ! value="$(_juvy_parse_quoted_value "$value")"; then
        continue
      fi
      case "$key" in
        JUVY_BACKUP_DIR)
          _JUVY_BACKUP_DIR="$value"
          ;;
        JUVY_REMOTE_URL)
          _JUVY_REMOTE_URL="$value"
          ;;
        JUVY_REMOTE_NAME)
          _JUVY_REMOTE_NAME="$value"
          ;;
        JUVY_REMOTE_PUSH)
          _JUVY_REMOTE_PUSH="$value"
          ;;
      esac
    done < "$_JUVY_CONFIG_FILE"
  fi
}

# Common utility functions to reduce code duplication

_juvy_trim_whitespace() {
  local input="$1"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  echo "$input"
}

_juvy_parse_quoted_value() {
  local value="$1"

  # Handle various value formats safely
  if [[ "$value" == \"*\" ]]; then
    # Double quoted - remove quotes and handle escapes
    value="${value#\"}"
    value="${value%\"}"
    # Basic unescape for common cases
    value="${value//\\\\/\\}"
    value="${value//\\\"/\"}"
    value="${value//\\\$/\$}"
    value="${value//\\\`/\`}"
  elif [[ "$value" == \'*\' ]]; then
    # Single quoted - remove quotes, literal content
    value="${value#\'}"
    value="${value%\'}"
  else
    # Unquoted - handle basic shell escaping but be conservative
    # Only accept values that look safe (no unescaped spaces/special chars)
    if [[ "$value" == *[[:space:]]* && "$value" != *\\[[:space:]]* ]]; then
      # Contains unescaped spaces - return empty to signal invalid
      echo ""
      return 1
    fi
    # Handle basic backslash escapes
    value="${value//\\ / }"
    value="${value//\\\$/\$}"
    value="${value//\\\`/\`}"
    value="${value//\\\"/\"}"
    value="${value//\\\'/\'}"
  fi

  echo "$value"
  return 0
}

# Consolidated prerequisite validation functions

_juvy_validate_backup_file_exists() {
  if [[ ! -f "$_JUVY_BACKUP_FILE" ]]; then
    _juvy_error "Backup file not found. Run 'juvy init' first."
    return 1
  fi
  return 0
}

_juvy_validate_backup_dir_exists() {
  if [[ ! -d "$_JUVY_BACKUP_DIR" ]]; then
    _juvy_error "Backup directory not found: $_JUVY_BACKUP_DIR"
    _juvy_warn "Run 'juvy init' to set up backup directory"
    return 1
  fi
  return 0
}

_juvy_validate_backup_dir_configured() {
  if [[ ! -d "$_JUVY_BACKUP_DIR" ]]; then
    _juvy_error "juvy: Set JUVY_BACKUP_DIR value in $_JUVY_CONFIG_FILE"
    return 1
  fi
  return 0
}

_juvy_parse_entry_basic() {
  local entry="$1"

  [[ -z "$entry" || "$entry" == \#* ]] && return 1

  entry="$(_juvy_trim_whitespace "$entry")"
  [[ -z "$entry" ]] && return 1

  echo "$entry"
  return 0
}

_juvy_rsync_simple() {
  local rsync_output
  local rsync_exit_code

  rsync_output=$(rsync "$@" 2>&1)
  rsync_exit_code=$?

  if [[ $rsync_exit_code -eq 0 ]]; then
    if [[ "${JUVY_VERBOSE:-}" == "1" && -n "$rsync_output" ]]; then
      printf "%s\n" "$rsync_output"
    fi
    return 0
  fi

  # Handle partial transfer as success if files were transferred (for restore operations)
  if [[ $rsync_exit_code -eq 23 ]] && [[ "$rsync_output" == *"sent "* ]]; then
    if [[ "${JUVY_VERBOSE:-}" == "1" && -n "$rsync_output" ]]; then
      printf "%s\n" "$rsync_output"
    fi
    return 0
  fi

  # Show user-friendly error message
  case $rsync_exit_code in
    1)
      _juvy_error "rsync syntax or usage error"
      ;;
    2)
      _juvy_error "rsync protocol incompatibility"
      ;;
    11)
      _juvy_error "rsync file I/O error"
      ;;
    12)
      _juvy_error "rsync protocol data stream error"
      ;;
    23)
      _juvy_error "rsync partial transfer: some files could not be copied"
      ;;
    24)
      _juvy_error "rsync source files vanished"
      ;;
    *)
      _juvy_error "rsync failed with error code $rsync_exit_code"
      ;;
  esac

  _juvy_warn "See $_JUVY_LOG_FILE for details"
  _juvy_log_error "rsync failed (exit code $rsync_exit_code): $rsync_output"
  return $rsync_exit_code
}

## COMMAND DISPATCHER & HELP ###################################################


juvy() {
  # Initialize paths and load configuration at start of each command
  _juvy_init_paths
  _juvy_load_config

  # Check for verbose flag before command
  if [[ "${1:-}" == "-v" ]]; then
    export JUVY_VERBOSE=1
    shift
  fi

  case $1 in
    init)
      _juvy_init "$@"
      ;;
    uninstall)
      _juvy_uninstall "$@"
      ;;
    add)
      shift
      _juvy_add "$@"
      ;;
    remove)
      shift
      _juvy_remove "$@"
      ;;
    backup)
      _juvy_backup "$@"
      ;;
    doctor)
      _juvy_doctor "$@"
      ;;
    version|--version|-v)
      echo "juvy $_JUVY_VERSION"
      ;;
    git)
      shift
      _juvy_git "$@"
      ;;
    remote)
      shift
      _juvy_remote "$@"
      ;;
    update)
      _juvy_update "$@"
      ;;
    nuke)
      _juvy_nuke "$@"
      ;;
    restore)
      shift
      _juvy_restore "$@"
      ;;
    list)
      _juvy_list "$@"
      ;;
    status)
      shift
      _juvy_status "$@"
      ;;
    *)
      if [[ -z $1 ]]; then
        _juvy_help
      else
        echo "juvy: Unknown command '$1'" >&2
        echo "Run 'juvy' for usage information"
      fi
      ;;
  esac
}

_juvy_help() {
  echo "juvy $_JUVY_VERSION - dotfile backup utility"
  echo ""
  echo "Usage: juvy [-v] <command>"
  echo ""
  echo "Options:"
  echo "  -v            Enable verbose output (show progress messages)"
  echo ""
  echo "Commands:"
  echo "  init        Initialize juvy configuration"
  echo "  add         Add files/directories to backup list (or edit with \$EDITOR)"
  echo "              'add ~/.zshrc' or 'add ~/.config/nvim/'"
  echo "  remove      Remove files/directories from backup list (or edit with \$EDITOR)"
  echo "              'remove ~/.zshrc' or 'remove --delete ~/.zshrc'"
  echo "  backup      Backup files and directories to configured directory"
  echo "  restore     Restore all files from latest backup"
  echo "              'restore --dry-run' shows what would be restored"
  echo "  list        Show all tracked files and directories"
  echo "  status      Show changes since last backup"
  echo "              'status [file]' shows detailed diff for specific file"
  echo "  doctor      Validate juvy configuration and setup"
  echo "              'doctor --fix' applies common repairs"
  echo "  git         Run git commands in backup directory"
  echo "  remote      Manage git remote for backup synchronization"
  echo "              'remote' shows current status"
  echo "              'remote <url>' sets/changes remote"
  echo "              'remote off' removes remote"
  echo "              'remote push' manually pushes to remote"
  echo "  update      Update juvy to the latest version"
  echo "  version     Show version information"
  echo "  uninstall   Remove juvy from system (preserves backups)"
  echo "  nuke        Completely destroy juvy and all backups"
  echo ""
  echo "Backup File Format:"
  echo "  # Comments start with #"
  echo "  ~/.zshrc                  # Include files"
  echo "  ~/.config/nvim/           # Include directories (trailing /)"
  echo "  !~/.config/nvim/undo/     # Exclude patterns (prefix with !)"
  echo "  ~/.ssh/config             # Inline comments supported"
  echo ""
}
_juvy_init() {
  local force_reinit=false

  # Check if this is a re-initialization
  if [[ -d "$_JUVY_CONFIG_DIR" && -f "$_JUVY_CONFIG_FILE" ]]; then
    force_reinit=true
    echo "Juvy is already initialized. Re-initializing with current settings as defaults..."
    echo ""
  fi

  if [[ ! -d "$_JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$_JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi

  if [[ ! -f "$_JUVY_BACKUP_FILE" ]]; then
    _juvy_init_smart_defaults
  fi

  if [[ ! -f "$_JUVY_CONFIG_FILE" ]]; then
    touch "$_JUVY_CONFIG_FILE"
  fi

  _juvy_init_backups "$force_reinit"
}

_juvy_init_backups() {
  local dir force_reinit="$1"
  local current_backup_dir="$_JUVY_BACKUP_DIR"
  local use_icloud=""
  local default_dir=""

  # Prompt for backup directory (with current value or new default)
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_BACKUP_DIR=" "$_JUVY_CONFIG_FILE" 2>/dev/null; then
    # On macOS, prompt for iCloud preference (only for new setup, not re-init)
    if [[ "$_JUVY_PLATFORM" == "macos" && "$force_reinit" != "true" ]]; then
      local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
      if [[ -d "$icloud_dir" ]]; then
        printf "juvy: Do you want to store backups in iCloud? (y/n) "
        read -r use_icloud_response
        if [[ "$use_icloud_response" =~ ^[Yy] ]]; then
          use_icloud="icloud"
        fi
      fi
    fi

    # Get default based on iCloud preference
    default_dir="$(_juvy_default_backup_dir "$use_icloud")"

    # Use existing value if re-initializing
    if [[ "$force_reinit" == "true" && -n "$current_backup_dir" ]]; then
      default_dir="$current_backup_dir"
    fi

    printf "juvy: Backup directory (edit or press enter for default):\n"
    printf "      [%s] " "$default_dir"
    read -r dir

    if [[ -n "$dir" ]]; then
      # User provided custom path
      if mkdir -p "$dir" > /dev/null 2>&1; then
        _JUVY_BACKUP_DIR="$dir"
      else
        printf "juvy: Unable to create directory (%s). Using default.\n" "$dir"
        _JUVY_BACKUP_DIR="$default_dir"
        mkdir -p "$_JUVY_BACKUP_DIR" > /dev/null 2>&1
      fi
    else
      # User accepted default
      _JUVY_BACKUP_DIR="$default_dir"
      mkdir -p "$_JUVY_BACKUP_DIR" > /dev/null 2>&1
    fi

    # Save backup directory using _juvy_update_config (it handles quoting internally)
    _juvy_update_config "JUVY_BACKUP_DIR" "$_JUVY_BACKUP_DIR"
  fi

  if [[ ! -d "$_JUVY_BACKUP_DIR/.git" ]]; then
    git init -b main "$_JUVY_BACKUP_DIR"
  fi

  # Prompt for remote setup (always if force_reinit, otherwise only if not configured)
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_REMOTE_URL=" "$_JUVY_CONFIG_FILE" 2>/dev/null; then
    _juvy_prompt_remote_setup "$force_reinit"
  fi
}

_juvy_prompt_remote_setup() {
  local force_reinit="$1"
  local remote_url choice
  local current_remote="$_JUVY_REMOTE_URL"
  local current_push="$_JUVY_REMOTE_PUSH"

  echo ""
  echo "Git Remote Setup (Optional)"
  echo "You can sync your backups to a remote git repository."
  echo ""
  echo "Benefits:"
  echo "  - Access backups from multiple devices"
  echo "  - Extra backup redundancy"
  echo "  - Version history in the cloud"
  echo ""

  if [[ "$force_reinit" == "true" && -n "$current_remote" ]]; then
    echo "Current remote: $current_remote"
    echo "Current auto-push: ${current_push:-false}"
    echo ""
    echo "Enter new git remote URL (or press Enter to keep current):"
  else
    echo "Enter git remote URL (or press Enter to skip):"
  fi

  echo "Examples:"
  echo "  git@github.com:username/dotfiles.git"
  echo "  https://github.com/username/dotfiles.git"
  echo ""
  echo -n "Remote URL: "
  read -r remote_url

  if [[ -z "$remote_url" ]]; then
    if [[ "$force_reinit" == "true" && -n "$current_remote" ]]; then
      echo "Keeping current remote configuration"
      return 0
    else
      echo "Skipping remote setup. You can add one later with: juvy remote <url>"
      return 0
    fi
  fi

  # Validate URL format
  if ! _juvy_validate_git_url "$remote_url"; then
    echo "Invalid git URL format. Skipping remote setup."
    echo "You can add a remote later with: juvy remote <url>"
    return 0
  fi

  echo ""
  echo "Testing connection to remote..."

  # Add remote to test connection
  local remote_name="origin"
  local test_success=false

  # Remove existing remote if it exists
  if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    _juvy_git remote remove "$remote_name" 2>/dev/null
  fi

  if _juvy_git remote add "$remote_name" "$remote_url"; then
    if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
      echo "Remote connection successful"
      test_success=true
    else
      echo "Warning: Could not connect to remote"
      echo "   This might be due to authentication or the repository not existing"
      echo ""
      echo -n "Continue anyway? [y/N] "
      read -r choice

      if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        test_success=true
      else
        _juvy_git remote remove "$remote_name" 2>/dev/null
        echo "Remote setup cancelled"
        echo "You can add a remote later with: juvy remote <url>"
        return 0
      fi
    fi
  else
    echo "Failed to add remote. Skipping setup."
    echo "You can add a remote later with: juvy remote <url>"
    return 0
  fi

  if [[ "$test_success" == "true" ]]; then
    # Update config file
    _juvy_update_config "JUVY_REMOTE_URL" "$remote_url"
    _juvy_update_config "JUVY_REMOTE_PUSH" "true"
    _juvy_update_config "JUVY_REMOTE_NAME" "$remote_name"

    echo "Remote setup completed successfully"
    echo ""
    echo "Auto-push is enabled. Future backups will be pushed automatically."
    echo "To disable auto-push: Set JUVY_REMOTE_PUSH=false in $_JUVY_CONFIG_FILE"
  fi
}

# Helper function for case-insensitive array membership (Bash 3.2 compatible)
_juvy_array_contains() {
  local needle="$1"
  shift
  local needle_lower item_lower item
  needle_lower=$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')
  for item in "$@"; do
    item_lower=$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')
    [[ "$item_lower" == "$needle_lower" ]] && return 0
  done
  return 1
}

_juvy_add_fallback_defaults() {
  local added=false
  if [[ -f "$HOME/.zshrc" ]]; then
    echo "~/.zshrc" >> "$_JUVY_BACKUP_FILE"
    added=true
  fi
  if [[ -f "$HOME/.gitconfig" ]]; then
    echo "~/.gitconfig" >> "$_JUVY_BACKUP_FILE"
    added=true
  fi
  if [[ "$added" == "false" ]]; then
    echo "No default files found to add"
  fi
}

_juvy_init_smart_defaults() {
  local found_files=()
  local patterns=()
  local choice

  # Define dotfile patterns to search for (excludes sensitive files like SSH, gh CLI, AWS)
  patterns=(
    # Shell configs
    "~/.zshrc" "~/.bashrc" "~/.profile" "~/.bash_profile"
    "~/.zshenv" "~/.zprofile" "~/.inputrc"
    # Git
    "~/.gitconfig" "~/.gitignore_global" "~/.gitignore"
    # Editors
    "~/.vimrc" "~/.config/nvim/"
    "~/.emacs" "~/.emacs.d/"
    "~/.config/helix/" "~/.ideavimrc"
    # Terminal
    "~/.tmux.conf" "~/.alacritty.yml" "~/.alacritty.toml"
    "~/.config/kitty/" "~/.config/wezterm/" "~/.config/starship.toml" "~/.config/zellij/"
    # Development tools
    "~/.npmrc" "~/.tool-versions" "~/.config/mise/" "~/.mise.toml"
    "~/.cargo/config.toml" "~/.gemrc" "~/.yarnrc" "~/.yarnrc.yml" "~/.config/pip/"
    # CLI utilities
    "~/.config/lazygit/" "~/.config/bat/" "~/.config/htop/" "~/.hushlogin"
    # macOS
    "~/.config/karabiner/"
  )

  _juvy_info "Scanning for common dotfiles..."
  _juvy_info ""

  # Scan for existing files
  local pattern full_path
  for pattern in "${patterns[@]}"; do
    full_path="${pattern/#\~/$HOME}"
    if [[ -e "$full_path" ]]; then
      found_files+=("$pattern")
    fi
  done

  if [[ ${#found_files[@]} -eq 0 ]]; then
    echo "No common dotfiles found. Creating basic backup list..."
    _juvy_add_fallback_defaults
    return 0
  fi

  # Display found files
  echo "Found these files you might want to backup:"
  echo ""

  local file file_type
  for file in "${found_files[@]}"; do
    full_path="${file/#\~/$HOME}"
    file_type="(config)"

    if [[ -d "$full_path" ]]; then
      file_type="(directory)"
    elif [[ "$file" == *"rc" || "$file" == *"profile" ]]; then
      file_type="(shell config)"
    elif [[ "$file" == *"git"* ]]; then
      file_type="(git config)"
    elif [[ "$file" == *"vim"* || "$file" == *"emacs"* ]]; then
      file_type="(editor config)"
    elif [[ "$file" == *"tmux"* || "$file" == *"alacritty"* ]]; then
      file_type="(terminal config)"
    fi

    printf "  %s %s\n" "$file" "$file_type"
  done

  echo ""
  echo "Select files to track:"
  echo "  a) All files"
  echo "  c) Choose individually"
  echo "  s) Skip - I'll add manually"
  echo ""
  echo -n "Choice [a/c/s]: "
  read -r choice

  case "$choice" in
    a|A)
      _juvy_add_files_to_backup "${found_files[@]}"
      echo "Added all found files to backup list"
      ;;
    c|C)
      _juvy_interactive_file_selection "${found_files[@]}"
      ;;
    s|S|*)
      _juvy_add_fallback_defaults
      echo "Use 'juvy add <path>' to add files later"
      ;;
  esac
}

_juvy_add_files_to_backup() {
  local file full_path
  for file in "$@"; do
    # Add trailing slash for directories
    full_path="${file/#\~/$HOME}"
    if [[ -d "$full_path" && "$file" != */ ]]; then
      file="$file/"
    fi
    echo "$file" >> "$_JUVY_BACKUP_FILE"
  done
}

_juvy_interactive_file_selection() {
  local selected_files=()
  local response file full_path file_type warning

  echo ""
  echo "Select files individually (y/n for each):"
  echo ""

  for file in "$@"; do
    full_path="${file/#\~/$HOME}"
    warning=""
    file_type="config"

    if [[ -d "$full_path" ]]; then
      file_type="directory"
    fi

    # Check if sensitive
    if _juvy_is_sensitive_file "$file"; then
      warning=" (sensitive)"
    fi

    echo -n "  Include $file ($file_type)$warning? [y/N] "
    read -r response

    if [[ "$response" == "y" || "$response" == "Y" ]]; then
      selected_files+=("$file")
    fi
  done

  if [[ ${#selected_files[@]} -gt 0 ]]; then
    _juvy_add_files_to_backup "${selected_files[@]}"
    echo "Added ${#selected_files[@]} files to backup list"
  else
    _juvy_add_fallback_defaults
  fi
}

_juvy_uninstall() {
  local confirm

  echo "This will remove juvy from your system (but preserve backups):"
  echo "  - Configuration directory: $_JUVY_CONFIG_DIR"
  echo "  - Installation directory: $HOME/.juvy"
  echo "  - juvy entry from shell rc file"
  echo ""
  echo "Backup directory will be preserved: $_JUVY_BACKUP_DIR"
  echo -n "Are you sure you want to proceed? [y/N] "
  read -r confirm

  if [[ "$confirm" != "y" ]]; then
    echo "Remove cancelled"
    return 0
  fi

  _juvy_uninstall_internal

  echo ""
  echo "juvy has been removed from your system"
  echo "Your backups are preserved in: $_JUVY_BACKUP_DIR"
  echo "Restart your shell to complete removal"
}

_juvy_validate_config_file() {
  local issues=()
  local line_num=0
  local line key value
  local backup_dir_set=false

  _juvy_info "Validating config file ($_JUVY_CONFIG_FILE)..."

  # Test if config can be parsed without errors
  while IFS= read -r line; do
    (( ++line_num ))

    [[ -z "$line" || "$line" == \#* ]] && continue

    # Remove leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    # Must contain =
    if [[ "$line" != *=* ]]; then
      issues+=("Line $line_num: Invalid format (missing =): $line")
      continue
    fi

    # Extract key and value
    key="${line%%=*}"
    value="${line#*=}"

    # Clean up key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    if [[ -z "$key" ]]; then
      issues+=("Line $line_num: Empty key: $line")
      continue
    fi

    # Check for known configuration keys
    case "$key" in
      JUVY_BACKUP_DIR)
        backup_dir_set=true
        # Validate backup directory path
        local test_path parent_dir
        if ! test_path="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi

        if [[ -z "$test_path" ]]; then
          issues+=("Line $line_num: Empty backup directory path")
          continue
        fi

        if [[ -e "$test_path" && ! -d "$test_path" ]]; then
          issues+=("Line $line_num: Backup path is not a directory: $test_path")
          continue
        fi

        if [[ -d "$test_path" && ! -w "$test_path" ]]; then
          issues+=("Line $line_num: Backup directory is not writable: $test_path")
          continue
        fi

        if [[ ! -e "$test_path" ]]; then
          parent_dir="${test_path%/*}"
          if [[ -z "$parent_dir" || "$parent_dir" == "$test_path" ]]; then
            parent_dir="$(dirname "$test_path")"
          fi
          if [[ ! -d "$parent_dir" || ! -w "$parent_dir" ]]; then
            issues+=("Line $line_num: Backup directory cannot be created (check permissions): $test_path")
          else
            issues+=("Line $line_num: Backup directory does not exist: $test_path")
          fi
        fi
        ;;
      JUVY_REMOTE_URL)
        # Validate git URL format
        local test_url
        if ! test_url="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi

        if [[ -n "$test_url" ]] && ! _juvy_validate_git_url "$test_url"; then
          issues+=("Line $line_num: Invalid git URL format: $test_url")
        fi
        ;;
      JUVY_REMOTE_PUSH)
        # Validate boolean
        local test_bool
        if ! test_bool="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi

        if [[ "$test_bool" != "true" && "$test_bool" != "false" ]]; then
          issues+=("Line $line_num: Invalid boolean value (use true/false): $test_bool")
        fi
        ;;
      JUVY_REMOTE_NAME)
        # Validate remote name format
        local test_name
        if ! test_name="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi

        if [[ -n "$test_name" ]] && [[ ! "$test_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
          issues+=("Line $line_num: Invalid remote name format: $test_name")
        fi
        ;;
      *)
        issues+=("Line $line_num: Unknown configuration key: $key")
        ;;
    esac
  done < "$_JUVY_CONFIG_FILE"

  # Report issues
  if [[ ${#issues[@]} -gt 0 ]]; then
    echo "Config file issues found:"
    local issue
    for issue in "${issues[@]}"; do
      echo "   $issue"
    done
    return 1
  else
    echo "Config file is valid"
    return 0
  fi
}

_juvy_validate_backup_file() {
  local invalid_paths=()
  local large_paths=()
  local exclude_patterns=()
  local line_num=0
  local entry parsed_data entry_type entry_path full_path

  _juvy_info "Validating backup file..."

  while IFS= read -r entry; do
    (( ++line_num ))

    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    # Parse entry
    parsed_data="$(_juvy_parse_backup_entry "$entry")"
    entry_type="$(_juvy_extract_parsed_field "$parsed_data" "type" "include")"
    entry_path="$(_juvy_extract_parsed_field "$parsed_data" "path" "")"

    if [[ "$entry_type" == "exclude" ]]; then
      exclude_patterns+=("Line $line_num: $entry_path")
      continue
    fi

    # Validate include patterns
    full_path="$(_juvy_entry_to_source_path "$entry_path")"

    if [[ ! -e "$full_path" ]]; then
      invalid_paths+=("Line $line_num: $entry_path")
    elif [[ -d "$full_path" ]]; then
      # Check directory size
      local dir_info
      if dir_info="$(_juvy_calculate_directory_info "$entry_path")"; then
        local size_bytes size_human file_count
        size_bytes="$(_juvy_parse_dir_info "$dir_info" bytes)"
        size_human="$(_juvy_parse_dir_info "$dir_info" human)"
        file_count="$(_juvy_parse_dir_info "$dir_info" count)"
        if (( size_bytes > 104857600 )); then
          large_paths+=("Line $line_num: $entry_path ($size_human, $file_count files)")
        fi
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  # Report validation results
  local has_issues=false
  local has_warnings=false
  local exclude item

  if [[ ${#exclude_patterns[@]} -gt 0 ]]; then
    echo "Exclude patterns found:"
    for exclude in "${exclude_patterns[@]}"; do
      echo "   $exclude"
    done
    echo ""
  fi

  if [[ ${#invalid_paths[@]} -gt 0 ]]; then
    echo "Invalid paths found in backup file:" >&2
    for item in "${invalid_paths[@]}"; do
      echo "   $item" >&2
    done
    echo "   These paths will be skipped during backup" >&2
    echo ""
    has_issues=true
  fi

  if [[ ${#large_paths[@]} -gt 0 ]]; then
    echo "Large directories found in backup file:" >&2
    for item in "${large_paths[@]}"; do
      echo "   $item" >&2
    done
    echo "   These may slow down backup and consume significant storage" >&2
    echo ""
    has_warnings=true
  fi

  if [[ "$has_issues" == "true" ]]; then
    return 1
  fi

  return 0
}


## BACKUP FUNCTIONS ###########################################################

# Perform backup of all configured files and commit changes

_juvy_backup() {
  _juvy_validate_backup_dir_configured || return 1
  _juvy_validate_backup_file_exists || return 1

  _juvy_info "Starting backup process..."

  # Validate backup file before starting rsync
  _juvy_validate_backup_file

  # Process backup entries with support for directories and files
  if ! _juvy_process_backup_entries; then
    _juvy_error "Backup failed"
    _juvy_log "BACKUP FAILED: rsync error"
    return 1
  fi

  _juvy_info "Files synced successfully"


  if [[ -n $(_juvy_git status --porcelain) ]]; then
    _juvy_git add -A
    if ! _juvy_git commit -m "Backup: $(_juvy_timestamp)"; then
      _juvy_error "Git commit failed, but files were synced"
      _juvy_log "BACKUP FAILED: git commit error"
      return 1
    fi
    _juvy_info "Changes committed to git"

    # Auto-push if remote is configured and enabled
    local push_status=""
    if [[ "$_JUVY_REMOTE_PUSH" == "true" && -n "$_JUVY_REMOTE_URL" ]]; then
      if _juvy_remote_push_auto; then
        _juvy_info "Changes pushed to remote"
        push_status=" (pushed to remote)"
      else
        _juvy_warn "Failed to push to remote (run 'juvy remote push' manually)"
        push_status=" (push failed)"
      fi
    fi

    _juvy_log "BACKUP OK: changes committed${push_status}"
  else
    _juvy_info "No changes to commit"
    _juvy_log "BACKUP OK: no changes"
  fi

  _juvy_result "Backup completed successfully"
}

_juvy_doctor() {
  local fix_mode=false
  local issues=0
  local warnings=0
  local backup_dir="$_JUVY_BACKUP_DIR"
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local remote_url="$_JUVY_REMOTE_URL"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix)
        fix_mode=true
        shift
        ;;
      -*)
        _juvy_error "Unknown option: $1"
        _juvy_warn "Usage: juvy doctor [--fix]"
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done

  _juvy_info "Running juvy doctor..."

  if [[ "$fix_mode" == "true" ]]; then
    local fixes=0
    local juvy_script="$HOME/.juvy/juvy"

    _juvy_info "Applying quick fixes..."

    if [[ ! -d "$_JUVY_CONFIG_DIR" ]]; then
      if mkdir -p "$_JUVY_CONFIG_DIR" >/dev/null 2>&1; then
        _juvy_result "Created config directory"
        (( ++fixes ))
      else
        _juvy_error "Failed to create config directory: $_JUVY_CONFIG_DIR"
      fi
    fi

    if [[ ! -f "$_JUVY_CONFIG_FILE" ]]; then
      if touch "$_JUVY_CONFIG_FILE" >/dev/null 2>&1; then
        _juvy_result "Created config file"
        (( ++fixes ))
      else
        _juvy_error "Failed to create config file: $_JUVY_CONFIG_FILE"
      fi
    fi

    if [[ -n "$_JUVY_CONFIG_DIR" && -f "$_JUVY_CONFIG_FILE" ]]; then
      if ! grep -q "^JUVY_BACKUP_DIR=" "$_JUVY_CONFIG_FILE" 2>/dev/null; then
        _juvy_update_config "JUVY_BACKUP_DIR" "$backup_dir"
        _juvy_result "Wrote JUVY_BACKUP_DIR to config"
        (( ++fixes ))
      fi
    fi

    if [[ ! -f "$_JUVY_BACKUP_FILE" ]]; then
      if touch "$_JUVY_BACKUP_FILE" >/dev/null 2>&1; then
        _juvy_result "Created backup file"
        (( ++fixes ))
      else
        _juvy_error "Failed to create backup file: $_JUVY_BACKUP_FILE"
      fi
    fi

    if [[ -n "$backup_dir" && ! -e "$backup_dir" ]]; then
      if mkdir -p "$backup_dir" >/dev/null 2>&1; then
        _juvy_result "Created backup directory"
        (( ++fixes ))
      else
        _juvy_error "Failed to create backup directory: $backup_dir"
      fi
    fi

    if [[ -n "$backup_dir" && -d "$backup_dir" && ! -d "$backup_dir/.git" ]]; then
      if git init -b main "$backup_dir" >/dev/null 2>&1; then
        _juvy_result "Initialized backup git repository"
        (( ++fixes ))
      else
        _juvy_error "Failed to initialize backup git repository: $backup_dir"
      fi
    fi

    if [[ -f "$juvy_script" ]]; then
      # Detect shell rc file
      local rc_file
      rc_file="$(_juvy_detect_rc_file)"

      if [[ ! -f "$rc_file" ]]; then
        if touch "$rc_file" >/dev/null 2>&1; then
          _juvy_result "Created $rc_file"
          (( ++fixes ))
        fi
      fi

      if [[ -f "$rc_file" ]] && ! grep -q '\.juvy' "$rc_file"; then
        {
          echo ""
          echo "# juvy dotfile backup tool"
          echo 'export PATH="$HOME/.juvy:$PATH"'
        } >> "$rc_file"
        _juvy_result "Added juvy to PATH in $rc_file"
        (( ++fixes ))
      fi
    fi

    if (( fixes == 0 )); then
      _juvy_info "No quick fixes applied"
    fi
  fi

  # Prerequisites - check for bash or zsh
  local current_shell="${SHELL##*/}"
  if [[ "$current_shell" != "bash" && "$current_shell" != "zsh" ]]; then
    _juvy_error "Shell is not bash or zsh: $SHELL"
    (( ++issues ))
  else
    _juvy_info "Shell: $current_shell"
  fi

  if command -v rsync >/dev/null 2>&1; then
    _juvy_result "rsync available"
  else
    _juvy_error "Missing dependency: rsync"
    (( ++issues ))
  fi

  if command -v git >/dev/null 2>&1; then
    _juvy_result "git available"
  else
    _juvy_error "Missing dependency: git"
    (( ++issues ))
  fi

  # Config directory and file
  if [[ -d "$_JUVY_CONFIG_DIR" ]]; then
    if [[ -w "$_JUVY_CONFIG_DIR" ]]; then
      _juvy_result "Config directory: $_JUVY_CONFIG_DIR"
    else
      _juvy_error "Config directory not writable: $_JUVY_CONFIG_DIR"
      (( ++issues ))
    fi
  else
    _juvy_error "Config directory missing: $_JUVY_CONFIG_DIR"
    (( ++issues ))
  fi

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    if _juvy_validate_config_file; then
      _juvy_result "Config file parsed"
    else
      (( ++issues ))
    fi
  else
    _juvy_error "Config file missing: $_JUVY_CONFIG_FILE"
    (( ++issues ))
  fi

  # Backup file
  if [[ -f "$_JUVY_BACKUP_FILE" ]]; then
    if _juvy_validate_backup_file; then
      _juvy_result "Backup file parsed"
    else
      (( ++issues ))
    fi
  else
    _juvy_error "Backup file missing: $_JUVY_BACKUP_FILE"
    (( ++issues ))
  fi

  # Backup directory and git repository
  if [[ -z "$backup_dir" ]]; then
    _juvy_error "Backup directory not configured (JUVY_BACKUP_DIR missing)"
    (( ++issues ))
  elif [[ -e "$backup_dir" && ! -d "$backup_dir" ]]; then
    _juvy_error "Backup path is not a directory: $backup_dir"
    (( ++issues ))
  elif [[ ! -d "$backup_dir" ]]; then
    _juvy_error "Backup directory missing: $backup_dir"
    (( ++issues ))
  else
    if [[ -w "$backup_dir" ]]; then
      _juvy_result "Backup directory: $backup_dir"
    else
      _juvy_error "Backup directory not writable: $backup_dir"
      (( ++issues ))
    fi

    if _juvy_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      _juvy_result "Backup git repository found"
    else
      _juvy_error "Backup directory is not a git repository (run 'juvy init')"
      (( ++issues ))
    fi
  fi

  # Remote configuration checks (optional)
  if [[ -n "$remote_url" ]]; then
    if [[ -d "$backup_dir/.git" ]]; then
      if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
        local actual_url
        actual_url="$(_juvy_git remote get-url "$remote_name" 2>/dev/null)"
        if [[ -n "$actual_url" && "$actual_url" != "$remote_url" ]]; then
          _juvy_warn "Remote URL mismatch: config=$remote_url git=$actual_url"
          (( ++warnings ))
        else
          _juvy_result "Remote '$remote_name' configured"
        fi

        if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
          _juvy_result "Remote reachable"
        else
          _juvy_warn "Remote not reachable (check network/auth)"
          (( ++warnings ))
        fi
      else
        _juvy_error "Remote '$remote_name' not found in backup repo"
        (( ++issues ))
      fi
    else
      _juvy_error "Cannot check remote: backup repo not initialized"
      (( ++issues ))
    fi
  else
    _juvy_info "No remote configured"
  fi

  # Shell integration
  local rc_file
  rc_file="$(_juvy_detect_rc_file)"
  if [[ -f "$rc_file" ]] && grep -q '\.juvy' "$rc_file"; then
    _juvy_result "$rc_file adds juvy to PATH"
  else
    _juvy_warn "$rc_file does not add juvy to PATH (run install.sh)"
    (( ++warnings ))
  fi

  if (( issues == 0 && warnings == 0 )); then
    _juvy_result "Doctor found no issues"
    return 0
  fi

  if (( issues > 0 )); then
    _juvy_error "Doctor found $issues issue(s) and $warnings warning(s)"
    return 1
  fi

  _juvy_warn "Doctor found $warnings warning(s)"
  return 0
}

# Detect the appropriate shell rc file
_juvy_detect_rc_file() {
  local current_shell="${SHELL##*/}"
  case "$current_shell" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    *)    echo "$HOME/.profile" ;;
  esac
}


_juvy_parse_backup_entry() {
  local entry="$1"
  local type="include"
  local entry_path="$entry"
  local comment=""

  if [[ "$entry" == !* ]]; then
    type="exclude"
    entry_path="${entry#!}"
  fi

  if [[ "$entry_path" == *" #"* ]]; then
    comment="${entry_path#*# }"
    entry_path="${entry_path%% #*}"
    # Trim trailing whitespace
    entry_path="${entry_path%"${entry_path##*[![:space:]]}"}"
  fi

  echo "type:$type"
  echo "path:$entry_path"
  if [[ -n "$comment" ]]; then
    echo "comment:$comment"
  fi
}

_juvy_extract_parsed_field() {
  local parsed_data="$1"
  local field="$2"
  local default_value="$3"

  local value
  value="$(echo "$parsed_data" | grep "^$field:" | cut -d: -f2-)"

  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default_value"
  fi
}

## UTILITY FUNCTIONS ##########################################################


# New unified path mapping utilities

# Converts a backup entry to a source filesystem path.
# Supported formats:
#   ~/path  -> $HOME/path (home-relative)
#   /path   -> /path (absolute)
# Returns empty string and logs error for invalid formats.
_juvy_entry_to_source_path() {
  local entry="$1"
  local resolved_path

  case "$entry" in
    \~/*)
      # Explicit home-relative: ~/path -> $HOME/path
      resolved_path="${HOME}${entry#\~}"
      ;;
    /*)
      # Absolute path: /etc/hosts -> /etc/hosts
      resolved_path="$entry"
      ;;
    *)
      # Invalid format - not home-relative (~/) or absolute (/)
      echo "Invalid path format: $entry" >&2
      echo "   Use ~/path for home-relative or /path for absolute" >&2
      return 1
      ;;
  esac

  echo "$resolved_path"
}

_juvy_entry_to_backup_path() {
  local entry="$1"
  local source_path backup_path

  source_path="$(_juvy_entry_to_source_path "$entry")"

  # Map to backup using absolute path structure
  backup_path="$_JUVY_BACKUP_DIR$source_path"

  echo "$backup_path"
}

_juvy_entry_to_relative_path() {
  local entry="$1"
  local base_root="$2"
  local resolved_path

  resolved_path="$(_juvy_entry_to_source_path "$entry")"

  if [[ "$base_root" == "$HOME" ]]; then
    if [[ "$resolved_path" == "$HOME/"* ]]; then
      echo "${resolved_path#$HOME/}"
      return 0
    fi
    return 1
  fi

  if [[ "$resolved_path" == "$HOME/"* ]]; then
    return 1
  fi

  if [[ "$resolved_path" == /* ]]; then
    echo "${resolved_path#/}"
    return 0
  fi

  return 1
}

_juvy_add_parent_rules() {
  local dir_path="$1"
  local path_parts=()
  local current_path=""
  local part

  [[ -z "$dir_path" ]] && return 0

  IFS='/' read -ra path_parts <<< "$dir_path"

  for part in "${path_parts[@]}"; do
    [[ -z "$part" ]] && continue
    if [[ -n "$current_path" ]]; then
      current_path="$current_path/$part"
    else
      current_path="$part"
    fi
    echo "+ /$current_path/"
  done
}

_juvy_add_include_rules() {
  local relative_path="$1"
  local is_dir="$2"
  local clean_path="${relative_path%/}"

  if [[ "$is_dir" == "true" ]]; then
    echo "+ /$clean_path/"
    echo "+ /$clean_path/***"
  else
    echo "+ /$relative_path"
  fi
}

_juvy_add_exclude_rules() {
  local relative_path="$1"
  local is_dir="$2"
  local clean_path="${relative_path%/}"

  if [[ "$is_dir" == "true" ]]; then
    printf '%s\n' "- /$clean_path/"
    printf '%s\n' "- /$clean_path/***"
  else
    printf '%s\n' "- /$relative_path"
  fi
}

# Write unique rules to filter file (Bash 3.2 compatible dedup using string)
_juvy_write_unique_rules() {
  local output_file="$1"
  shift
  local seen_rules=""
  local rule

  for rule in "$@"; do
    [[ -z "$rule" ]] && continue
    # Check if rule already seen (using string matching)
    if [[ "$seen_rules" != *"|$rule|"* ]]; then
      printf '%s\n' "$rule" >> "$output_file"
      seen_rules="$seen_rules|$rule|"
    fi
  done
}

# Collects backup entries from $_JUVY_BACKUP_FILE, separating includes and excludes.
# Populates global arrays _JUVY_INCLUDE_PATHS and _JUVY_EXCLUDE_PATTERNS
_juvy_collect_backup_entries() {
  local entry parsed_data entry_type entry_path

  _JUVY_INCLUDE_PATHS=()
  _JUVY_EXCLUDE_PATTERNS=()

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    parsed_data="$(_juvy_parse_backup_entry "$entry")"
    entry_type="$(_juvy_extract_parsed_field "$parsed_data" "type" "include")"
    entry_path="$(_juvy_extract_parsed_field "$parsed_data" "path" "")"

    if [[ "$entry_type" == "include" ]]; then
      _JUVY_INCLUDE_PATHS+=("$entry_path")
    elif [[ "$entry_type" == "exclude" ]]; then
      _JUVY_EXCLUDE_PATTERNS+=("$entry_path")
    fi
  done < "$_JUVY_BACKUP_FILE"
}

# Builds an rsync filter file from include/exclude patterns.
#
# Rule Ordering (rsync uses first-match-wins):
#   1. Parent directory rules (+ /path/) - Allow traversal to nested paths
#   2. Exclude rules (- /path/) - Block excluded files/directories BEFORE includes
#   3. Include rules (+ /path/***) - Include files/directories
#   4. Final exclude (- *) - Exclude everything not explicitly included
#
# This ordering ensures excludes take precedence over includes. For example:
#   ~/.config/nvim/        -> included
#   !~/.config/nvim/undo/  -> excluded (processed before the include's recursive rule)
_juvy_build_rsync_filter_file() {
  local base_root="$1"
  local include_array_name="$2"
  local exclude_array_name="$3"
  local filter_file="$4"
  local extra_exclude_array_name="${5:-}"

  # Copy arrays using eval (Bash 3.2 compatible)
  # Use safe expansion pattern to handle empty arrays
  local includes=()
  local excludes=()
  local extra_excludes=()
  eval "includes=(\"\${${include_array_name}[@]+\"\${${include_array_name}[@]}\"}\")"
  eval "excludes=(\"\${${exclude_array_name}[@]+\"\${${exclude_array_name}[@]}\"}\")"

  if [[ -n "$extra_exclude_array_name" ]]; then
    eval "extra_excludes=(\"\${${extra_exclude_array_name}[@]+\"\${${extra_exclude_array_name}[@]}\"}\")"
  fi

  local parent_rules=()
  local include_rules=()
  local exclude_rules=()
  local entry relative_path parent_path is_dir clean_path rule

  # Start with root directory rule
  parent_rules=("+ /")

  # Process include patterns
  for entry in ${includes[@]+"${includes[@]}"}; do
    if ! relative_path="$(_juvy_entry_to_relative_path "$entry" "$base_root")"; then
      continue
    fi

    is_dir="false"
    if [[ "$entry" == */ ]]; then
      is_dir="true"
    fi

    # Add parent directory rules for nested paths
    clean_path="${relative_path%/}"
    parent_path="${clean_path%/*}"
    if [[ "$parent_path" != "$clean_path" && -n "$parent_path" ]]; then
      while IFS= read -r rule; do
        parent_rules+=("$rule")
      done < <(_juvy_add_parent_rules "$parent_path")
    fi

    while IFS= read -r rule; do
      include_rules+=("$rule")
    done < <(_juvy_add_include_rules "$relative_path" "$is_dir")
  done

  # Process exclude patterns - handle empty arrays safely
  local all_excludes=()
  for entry in ${excludes[@]+"${excludes[@]}"}; do
    all_excludes+=("$entry")
  done
  for entry in ${extra_excludes[@]+"${extra_excludes[@]}"}; do
    all_excludes+=("$entry")
  done

  for entry in ${all_excludes[@]+"${all_excludes[@]}"}; do
    if ! relative_path="$(_juvy_entry_to_relative_path "$entry" "$base_root")"; then
      continue
    fi

    is_dir="false"
    if [[ "$entry" == */ ]]; then
      is_dir="true"
    fi

    while IFS= read -r rule; do
      exclude_rules+=("$rule")
    done < <(_juvy_add_exclude_rules "$relative_path" "$is_dir")
  done

  # Write filter file with correct ordering
  : > "$filter_file"
  _juvy_write_unique_rules "$filter_file" ${parent_rules[@]+"${parent_rules[@]}"}   # 1. Parents
  _juvy_write_unique_rules "$filter_file" ${exclude_rules[@]+"${exclude_rules[@]}"} # 2. Excludes
  _juvy_write_unique_rules "$filter_file" ${include_rules[@]+"${include_rules[@]}"} # 3. Includes
  printf '%s\n' "- *" >> "$filter_file"                                              # 4. Exclude rest
}


_juvy_process_backup_entries() {
  local home_paths=()
  local system_paths=()
  local entry source_path
  local home_count=0 system_count=0

  _juvy_info "Processing backup entries..."

  _juvy_collect_backup_entries

  _juvy_info "Processing ${#_JUVY_INCLUDE_PATHS[@]} paths"

  for entry in ${_JUVY_INCLUDE_PATHS[@]+"${_JUVY_INCLUDE_PATHS[@]}"}; do
    source_path="$(_juvy_entry_to_source_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ ! -d "$source_path" ]]; then
        continue
      fi
    else
      if [[ ! -f "$source_path" ]]; then
        continue
      fi
    fi

    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$entry")
    else
      system_paths+=("$entry")
    fi
  done

  if [[ ${#home_paths[@]} -gt 0 ]]; then
    _juvy_info "Backing up ${#home_paths[@]} home paths..."

    local temp_filter_file
    temp_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "$HOME" home_paths _JUVY_EXCLUDE_PATTERNS "$temp_filter_file"; then
      _juvy_error "Failed to build filter file for home paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! mkdir -p "$_JUVY_BACKUP_DIR$HOME/" > /dev/null 2>&1; then
      _juvy_error "Failed to create backup directory for home paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! _juvy_rsync_backup_with_filters "$HOME/" "$_JUVY_BACKUP_DIR$HOME/" "$temp_filter_file"; then
      _juvy_error "Failed to backup home paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    rm -f "$temp_filter_file"
    home_count=${#home_paths[@]}
  fi

  if [[ ${#system_paths[@]} -gt 0 ]]; then
    _juvy_info "Backing up ${#system_paths[@]} system paths..."

    local temp_filter_file
    temp_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "/" system_paths _JUVY_EXCLUDE_PATTERNS "$temp_filter_file"; then
      _juvy_error "Failed to build filter file for system paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! mkdir -p "$_JUVY_BACKUP_DIR" > /dev/null 2>&1; then
      _juvy_error "Failed to create backup directory"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! _juvy_rsync_backup_with_filters "/" "$_JUVY_BACKUP_DIR" "$temp_filter_file"; then
      _juvy_error "Failed to backup system paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    rm -f "$temp_filter_file"
    system_count=${#system_paths[@]}
  fi

  _juvy_info "Processed $home_count home and $system_count system paths"
  return 0
}

# Displays filter file contents for debugging rsync issues
_juvy_show_filter_debug() {
  local filter_file="$1"
  local line

  if [[ "${JUVY_DEBUG:-}" != "1" ]]; then
    return 0
  fi

  _juvy_warn "Filter file contents (for debugging):"
  _juvy_warn "   ----------------------------------------"
  while IFS= read -r line; do
    _juvy_warn "   $line"
  done < "$filter_file"
  _juvy_warn "   ----------------------------------------"
}

_juvy_rsync_backup_with_filters() {
  local source="$1"
  local dest="$2"
  local filter_file="$3"
  local rsync_args=(-a --delete --delete-excluded --filter="merge $filter_file")

  if [[ "${JUVY_VERBOSE:-}" == "1" ]]; then
    rsync_args=(-av --delete --delete-excluded --filter="merge $filter_file")
  fi

  if ! _juvy_rsync_simple "${rsync_args[@]}" "$source" "$dest"; then
    _juvy_show_filter_debug "$filter_file"
    return 1
  fi
}

_juvy_rsync_restore_with_filters() {
  local source="$1"
  local dest="$2"
  local filter_file="$3"
  local dry_run="${4:-false}"
  local rsync_args=()

  # Build rsync arguments
  # Use --ignore-times to force copy even when backup files are older than current files
  # (This happens when user modifies a file after backup and wants to restore the original)
  rsync_args=(-a --ignore-times --ignore-errors --filter="merge $filter_file")
  if [[ "${JUVY_VERBOSE:-}" == "1" ]]; then
    rsync_args=(-av --ignore-times --ignore-errors --filter="merge $filter_file")
  fi

  # Add dry-run flag if requested
  if [[ "$dry_run" == "true" ]]; then
    rsync_args+=(--dry-run --itemize-changes)
  fi

  # Use rsync to copy tracked files without removing existing files
  # Use --ignore-errors to continue despite permission issues on system directories
  if ! _juvy_rsync_simple "${rsync_args[@]}" "$source/" "$dest"; then
    _juvy_show_filter_debug "$filter_file"
    return 1
  fi
}


_juvy_timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

_juvy_log() {
  local message="$1"
  local timestamp

  timestamp="$(_juvy_timestamp)"

  # Ensure log directory exists
  if [[ ! -d "$_JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$_JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi

  echo "[$timestamp] $message" >> "$_JUVY_LOG_FILE"
}

_juvy_log_error() {
  _juvy_log "ERROR: $1"
}


# User-facing output utilities
# These respect JUVY_VERBOSE for progress messages

_juvy_info() {
  # Progress/status messages - only shown when verbose
  if [[ "${JUVY_VERBOSE:-}" == "1" ]]; then
    echo "$@"
  fi
}

_juvy_result() {
  # Final results - always shown
  echo "$@"
}

_juvy_error() {
  # Errors - always shown to stderr
  echo "$@" >&2
}

_juvy_warn() {
  # Warnings - always shown to stderr
  echo "Warning: $@" >&2
}


_juvy_git() {
  if [[ -d "$_JUVY_BACKUP_DIR" ]]; then
    git -C "$_JUVY_BACKUP_DIR" "$@"
  fi
}

_juvy_update() {
  local temp_script="/tmp/juvy_update.sh"
  local juvy_script="$HOME/.juvy/juvy"
  local repo_url="https://raw.githubusercontent.com/danecando/juvy/main/juvy.sh"
  local latest_version update

  echo "Checking for updates..."

  if ! curl -sSL "$repo_url" -o "$temp_script"; then
    echo "Failed to download latest version" >&2
    return 1
  fi

  latest_version=$(grep '_JUVY_VERSION="[0-9]' "$temp_script" | head -1 | cut -d'"' -f2)

  if [[ -z "$latest_version" ]]; then
    echo "Failed to extract version from downloaded script" >&2
    rm -f "$temp_script"
    return 1
  fi

  if [[ "$latest_version" == "$_JUVY_VERSION" ]]; then
    echo "juvy is already up to date (v$_JUVY_VERSION)"
    rm -f "$temp_script"
    return 0
  fi

  echo "Update available: v$_JUVY_VERSION -> v$latest_version"
  echo -n "Do you want to update? [Y/n] "
  read -r update

  if [[ "$update" == "n" ]]; then
    echo "Update cancelled"
    rm -f "$temp_script"
    return 0
  fi

  if mv "$temp_script" "$juvy_script" && chmod +x "$juvy_script"; then
    echo "Updated juvy to v$latest_version"
  else
    echo "Failed to update juvy" >&2
    rm -f "$temp_script"
    return 1
  fi
}

_juvy_nuke() {
  local confirm

  echo "WARNING: This will COMPLETELY DESTROY all juvy data including:"
  echo "  - Configuration directory: $_JUVY_CONFIG_DIR"
  echo "  - Backup directory: $_JUVY_BACKUP_DIR"
  echo "  - Installation directory: $HOME/.juvy"
  echo "  - juvy entry from shell rc file"
  echo ""
  echo "ALL YOUR BACKUPS WILL BE DELETED!"
  echo "This action cannot be undone!"
  echo -n "Are you absolutely sure? [y/N] "
  read -r confirm

  if [[ "$confirm" != "y" ]]; then
    echo "Nuke cancelled"
    return 0
  fi

  # Call rm function first (removes config, installation, .zshrc)
  _juvy_uninstall_internal

  if [[ -d "$_JUVY_BACKUP_DIR" ]]; then
    rm -rf "$_JUVY_BACKUP_DIR"
    echo "Nuked backup directory"
  fi

  echo ""
  echo "juvy has been completely nuked from your system"
  echo "Restart your shell to complete removal"
}

_juvy_uninstall_internal() {
  if [[ -d "$_JUVY_CONFIG_DIR" ]]; then
    rm -rf "$_JUVY_CONFIG_DIR"
    echo "Removed configuration directory"
  fi

  if [[ -d "$HOME/.juvy" ]]; then
    rm -rf "$HOME/.juvy"
    echo "Removed installation directory"
  fi

  # Remove from shell rc files
  local rc_file
  for rc_file in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc_file" ]] && grep -q '\.juvy\|juvy backup' "$rc_file"; then
      # Create a temporary file without the juvy lines
      {
        grep -v '\.juvy' "$rc_file" | grep -v "# juvy dotfile backup tool" | grep -v "juvy backup"
      } > "$rc_file.tmp" && mv "$rc_file.tmp" "$rc_file"
      echo "Removed juvy from $rc_file"
    fi
  done
}

_juvy_is_sensitive_file() {
  local file="$1"
  local filename="${file##*/}"  # basename
  local sensitive_patterns=(
    "*id_rsa*" "*id_ed25519*" "*id_ecdsa*"  # SSH keys
    "*.pem" "*.key" "*.cert"                 # Certificates
    "*credentials*" "*token*" "*secret*"     # Credentials
    "*.env" ".env.*"                         # Environment files
    "*auth*" "*passwd*"                      # Auth files
  )

  local pattern
  for pattern in "${sensitive_patterns[@]}"; do
    # Use case statement for pattern matching (Bash 3.2 compatible)
    case "$filename" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

_juvy_show_security_warning() {
  local file="$1"
  local choice

  echo "Security Warning: This appears to be a sensitive file"
  echo "   File: $file"
  echo ""
  echo "Backing up to cloud storage may expose sensitive data."
  echo "Options:"
  echo "  1) Cancel (recommended)"
  echo "  2) Continue anyway"
  echo ""
  echo -n "Choice [1-2]: "
  read -r choice

  case "$choice" in
    2)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_juvy_validate_path() {
  local input_path="$1"
  local full_path

  if [[ "$input_path" = /* ]]; then
    full_path="$input_path"
  else
    # Path relative to HOME (remove leading ./ or /)
    input_path="${input_path#./}"
    input_path="${input_path#/}"
    full_path="$HOME/$input_path"
  fi

  if [[ ! -e "$full_path" ]]; then
    echo "Path does not exist: $input_path" >&2
    return 1
  fi

  return 0
}

# Calculate directory size and file count.
# Returns colon-separated string: "size_bytes:size_human:file_count"
# Use _juvy_parse_dir_info helper to extract fields.
_juvy_calculate_directory_info() {
  local input_path="$1"
  local full_path
  local size_bytes size_human file_count

  # Use path as-is if it's already absolute, otherwise resolve it
  if [[ "$input_path" = /* ]]; then
    full_path="$input_path"
  else
    # Path is relative to HOME or in backup entry format
    if [[ "$input_path" = ~* ]]; then
      full_path="${input_path/#\~/$HOME}"
    else
      input_path="${input_path#./}"
      input_path="${input_path#/}"
      full_path="$HOME/$input_path"
    fi
  fi

  if [[ ! -d "$full_path" ]]; then
    return 1
  fi

  # Calculate size in bytes using du (try -sb first, fallback to -sk for macOS)
  size_bytes=$(du -sb "$full_path" 2>/dev/null | cut -f1)
  if [[ -z "$size_bytes" ]]; then
    # macOS doesn't support -sb, use -sk and convert to bytes
    local size_kb
    size_kb=$(du -sk "$full_path" 2>/dev/null | cut -f1)
    [[ -n "$size_kb" ]] && size_bytes=$((size_kb * 1024)) || size_bytes=0
  fi

  # Calculate human readable size
  if (( size_bytes >= 1073741824 )); then
    size_human="$(( size_bytes / 1073741824 )).$(( (size_bytes % 1073741824) / 107374182 ))GB"
  elif (( size_bytes >= 1048576 )); then
    size_human="$(( size_bytes / 1048576 )).$(( (size_bytes % 1048576) / 104857 ))MB"
  elif (( size_bytes >= 1024 )); then
    size_human="$(( size_bytes / 1024 ))KB"
  else
    size_human="${size_bytes}B"
  fi

  # Count files (not directories)
  file_count=$(find "$full_path" -type f 2>/dev/null | wc -l)
  [[ -z "$file_count" ]] && file_count=0
  file_count="${file_count#"${file_count%%[![:space:]]*}"}"

  # Return colon-separated string (no globals)
  echo "$size_bytes:$size_human:$file_count"
}

# Parse directory info string returned by _juvy_calculate_directory_info.
# Usage: _juvy_parse_dir_info "$dir_info" bytes|human|count
_juvy_parse_dir_info() {
  local info="$1"
  local field="$2"

  case "$field" in
    bytes)
      echo "${info%%:*}"
      ;;
    human)
      local rest="${info#*:}"
      echo "${rest%%:*}"
      ;;
    count)
      echo "${info##*:}"
      ;;
  esac
}

_juvy_prompt_large_directory() {
  local path_arg="$1"
  local size_human="$2"
  local file_count="$3"
  local force="$4"
  local response

  if [[ "$force" == "true" ]]; then
    return 0
  fi

  echo "This directory contains:"
  echo "   Files: $file_count"
  echo "   Size: $size_human"
  echo ""
  echo "Large backups may be slow and consume significant storage."
  echo -n "Continue? [y/N] "
  read -r response

  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    return 1
  fi

  return 0
}

_juvy_add() {
  local paths=()
  local p

  _juvy_validate_backup_file_exists || return 1

  # Parse path arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -*)
        echo "Unknown flag: $1" >&2
        echo "Usage: juvy add [path...]" >&2
        return 1
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if command -v "$editor" >/dev/null 2>&1; then
      "$editor" "$_JUVY_BACKUP_FILE"
      echo "Consider running 'juvy doctor' to check your backup file"
    else
      echo "Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
      return 1
    fi
  else
    # Arguments provided, validate and append to file
    for p in "${paths[@]}"; do
      # Validate path exists
      if ! _juvy_validate_path "$p"; then
        continue
      fi

      # Convert to absolute path if relative
      local full_path
      if [[ "$p" == /* ]]; then
        full_path="$p"
      else
        full_path="$PWD/$p"
      fi

      # Convert to backup entry format using Unix conventions
      local backup_entry
      if [[ "$full_path" == "$HOME"* ]]; then
        # Convert to home-relative with ~/ prefix
        backup_entry="~${full_path#$HOME}"
      elif [[ "$full_path" == /* ]]; then
        # Absolute path - use as-is
        backup_entry="$full_path"
      else
        echo "Invalid path format: $p. Accepted formats: absolute paths (e.g., /path/to/file), home-relative paths (e.g., ~/file), or paths relative to the current directory." >&2
        continue
      fi

      # Check if path exists and determine type
      if [[ -d "$full_path" ]]; then
        # Directory - ensure it ends with /
        if [[ "$backup_entry" != */ ]]; then
          backup_entry="$backup_entry/"
        fi

        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
          echo "Path already in backup list: $backup_entry"
          continue
        fi

        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            echo "Skipped adding sensitive directory: $p"
            continue
          fi
        fi

        # For directories, check size and prompt if needed
        local dir_info
        if dir_info="$(_juvy_calculate_directory_info "$p")"; then
          local size_bytes size_human file_count
          size_bytes="$(_juvy_parse_dir_info "$dir_info" bytes)"
          size_human="$(_juvy_parse_dir_info "$dir_info" human)"
          file_count="$(_juvy_parse_dir_info "$dir_info" count)"
          # Check if directory is larger than 100MB (104857600 bytes)
          if (( size_bytes > 104857600 )); then
            if ! _juvy_prompt_large_directory "$p" "$size_human" "$file_count" "false"; then
              echo "Skipped adding large directory: $p"
              continue
            fi
          fi
        fi

        echo "$backup_entry" >> "$_JUVY_BACKUP_FILE"
        echo "Added directory '$backup_entry' to backup list"

      elif [[ -f "$full_path" ]]; then
        # File - ensure it doesn't end with /
        backup_entry="${backup_entry%/}"

        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
          echo "Path already in backup list: $backup_entry"
          continue
        fi

        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            echo "Skipped adding sensitive file: $p"
            continue
          fi
        fi

        echo "$backup_entry" >> "$_JUVY_BACKUP_FILE"
        echo "Added file '$backup_entry' to backup list"

      else
        echo "Path not found: $p" >&2
        continue
      fi
    done
  fi
}

_juvy_remove() {
  local paths=()
  local p
  local delete_from_backup=false

  _juvy_validate_backup_file_exists || return 1

  # Parse path arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --delete)
        delete_from_backup=true
        shift
        ;;
      -*)
        echo "Unknown flag: $1" >&2
        echo "Usage: juvy remove [--delete] [path...]" >&2
        return 1
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if command -v "$editor" >/dev/null 2>&1; then
      "$editor" "$_JUVY_BACKUP_FILE"
      echo "Consider running 'juvy doctor' to check your backup file"
    else
      echo "Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
      return 1
    fi
  else
    # Arguments provided, remove from backup file
    for p in "${paths[@]}"; do
      # Convert to absolute path if relative
      local full_path
      if [[ "$p" == "~"* ]]; then
        full_path="${p/#\~/$HOME}"
      elif [[ "$p" == /* ]]; then
        full_path="$p"
      else
        full_path="$PWD/$p"
      fi

      # Convert to backup entry format
      local backup_entry
      if [[ "$full_path" == "$HOME"* ]]; then
        backup_entry="~${full_path#$HOME}"
      else
        backup_entry="$full_path"
      fi

      # Try both with and without trailing slash for directories
      local found=false
      local entry_to_remove=""

      if grep -Fxq "$backup_entry" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
        entry_to_remove="$backup_entry"
        found=true
      elif grep -Fxq "${backup_entry}/" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
        entry_to_remove="${backup_entry}/"
        found=true
      elif grep -Fxq "${backup_entry%/}" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
        entry_to_remove="${backup_entry%/}"
        found=true
      fi

      if [[ "$found" == "true" ]]; then
        # Remove the entry from backup file
        grep -Fxv "$entry_to_remove" "$_JUVY_BACKUP_FILE" > "$_JUVY_BACKUP_FILE.tmp"
        mv "$_JUVY_BACKUP_FILE.tmp" "$_JUVY_BACKUP_FILE"
        echo "Removed '$entry_to_remove' from backup list"

        # Check if file exists in backup directory and offer to delete
        local backup_path
        backup_path="$(_juvy_entry_to_backup_path "$entry_to_remove")"

        if [[ -e "$backup_path" ]]; then
          local should_delete=false

          if [[ "$delete_from_backup" == "true" ]]; then
            should_delete=true
          elif [[ -t 0 ]]; then
            # Only prompt if running interactively
            echo -n "Also delete from backup directory? [y/N] "
            local delete_confirm
            read -r delete_confirm
            if [[ "$delete_confirm" == [yY]* ]]; then
              should_delete=true
            fi
          fi

          if [[ "$should_delete" == "true" ]]; then
            rm -rf "$backup_path"
            echo "Deleted '$entry_to_remove' from backup"

            # Commit the deletion if there are changes
            if [[ -n $(_juvy_git status --porcelain) ]]; then
              _juvy_git add -A
              _juvy_git commit -m "Remove: $entry_to_remove" >/dev/null 2>&1
            fi
          fi
        fi
      else
        echo "Path not in backup list: $p"
      fi
    done
  fi
}

## RESTORE FUNCTIONS ##########################################################
# Restore all files from the latest backup

_juvy_restore() {
  local dry_run="false"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n)
        dry_run="true"
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        echo "Usage: juvy restore [--dry-run]" >&2
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done

  _juvy_validate_backup_dir_exists || return 1
  _juvy_validate_backup_file_exists || return 1

  local file_count dir_count total_size last_backup

  if ! _juvy_show_restore_preview; then
    echo "No files found to restore" >&2
    return 1
  fi

  # In dry-run mode, show what would be restored and exit
  if [[ "$dry_run" == "true" ]]; then
    echo ""
    echo "Dry-run mode: showing what would be restored..."
    echo ""
    _juvy_perform_restore "$dry_run"
    echo ""
    echo "No files were modified (dry-run mode)"
    return 0
  fi

  echo ""
  echo "Current files will be backed up to ~/.config/juvy/safety-backup/"
  echo ""
  echo -n "Proceed with restore? [Y/n] "
  local confirm
  read -r confirm

  if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    echo "Restore cancelled"
    return 0
  fi

  echo ""
  _juvy_info "Creating safety backup..."
  local safety_backup_path
  if ! safety_backup_path="$(_juvy_create_safety_backup)"; then
    _juvy_error "Failed to create safety backup"
    return 1
  fi

  _juvy_info "Restoring files..."
  if ! _juvy_perform_restore "$dry_run"; then
    _juvy_error "Restore failed"
    return 1
  fi

  _juvy_info "Setting permissions..."
  _juvy_result "Restore complete!"
  echo ""
  echo "To undo: juvy restore \"$safety_backup_path\""
}

_juvy_show_restore_preview() {
  local entry file_count=0 dir_count=0 total_files=0
  local backup_path source_path file_size last_backup

  last_backup="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  if [[ -z "$last_backup" ]]; then
    last_backup="Unknown"
  fi

  echo "Restore Summary:"

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    backup_path="$(_juvy_entry_to_backup_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        dir_file_count="${dir_file_count#"${dir_file_count%%[![:space:]]*}"}"
        (( total_files += dir_file_count ))
        (( ++dir_count ))
      fi
    else
      if [[ -f "$backup_path" ]]; then
        (( ++total_files ))
        (( ++file_count ))
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  if (( total_files == 0 )); then
    return 1
  fi

  echo "   $total_files files will be restored from backup"
  echo "   Last backup: $last_backup"
  echo ""

  echo "Files to restore:"
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    backup_path="$(_juvy_entry_to_backup_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        dir_file_count="${dir_file_count#"${dir_file_count%%[![:space:]]*}"}"
        echo "  ~$entry ($dir_file_count files)"
      fi
    else
      if [[ -f "$backup_path" ]]; then
        file_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
        [[ -z "$file_size" ]] && file_size="0B"
        echo "  ~$entry ($file_size)"
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  return 0
}

_juvy_create_safety_backup() {
  local timestamp safety_dir entry backup_path source_path dest_path dest_dir

  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  safety_dir="$_JUVY_CONFIG_DIR/safety-backup/$timestamp"

  if ! mkdir -p "$safety_dir" > /dev/null 2>&1; then
    _juvy_error "Failed to create safety backup directory: $safety_dir"
    return 1
  fi

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    source_path="$(_juvy_entry_to_source_path "$entry")"

    if [[ -e "$source_path" ]]; then
      dest_path="$safety_dir$entry"
      dest_dir="$(dirname "$dest_path")"

      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        _juvy_error "Failed to create safety backup directory: $dest_dir"
        return 1
      fi

      if [[ "$entry" == */ ]]; then
        if [[ -d "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_dir/" > /dev/null 2>&1; then
            _juvy_error "Failed to backup directory: $source_path"
            return 1
          fi
        fi
      else
        if [[ -f "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_path" > /dev/null 2>&1; then
            _juvy_error "Failed to backup file: $source_path"
            return 1
          fi
        fi
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  echo "$safety_dir"
  return 0
}

_juvy_perform_restore() {
  local dry_run="${1:-false}"
  local backup_dir="$_JUVY_BACKUP_DIR"
  local home_paths=()
  local system_paths=()
  local source_path entry

  if [[ "$dry_run" == "true" ]]; then
    _juvy_info "Showing what would be restored from backup..."
  else
    _juvy_info "Restoring files from backup..."
  fi

  _juvy_collect_backup_entries

  for entry in ${_JUVY_INCLUDE_PATHS[@]+"${_JUVY_INCLUDE_PATHS[@]}"}; do
    source_path="$(_juvy_entry_to_source_path "$entry")"
    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$entry")
    else
      system_paths+=("$entry")
    fi
  done

  if [[ ${#home_paths[@]} -gt 0 ]]; then
    local home_filter_file
    home_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "$HOME" home_paths _JUVY_EXCLUDE_PATTERNS "$home_filter_file"; then
      _juvy_error "Failed to build restore filter for home paths"
      rm -f "$home_filter_file"
      return 1
    fi

    if ! _juvy_rsync_restore_with_filters "$backup_dir$HOME" "$HOME" "$home_filter_file" "$dry_run"; then
      _juvy_error "Failed to restore home files"
      rm -f "$home_filter_file"
      return 1
    fi

    rm -f "$home_filter_file"
  fi

  if [[ ${#system_paths[@]} -gt 0 ]]; then
    local system_filter_file
    local extra_excludes=()
    system_filter_file="$(mktemp)"
    extra_excludes=("/.git/")

    if ! _juvy_build_rsync_filter_file "/" system_paths _JUVY_EXCLUDE_PATTERNS "$system_filter_file" extra_excludes; then
      _juvy_error "Failed to build restore filter for system paths"
      rm -f "$system_filter_file"
      return 1
    fi

    if ! _juvy_rsync_restore_with_filters "$backup_dir" "/" "$system_filter_file" "$dry_run"; then
      _juvy_error "Failed to restore system files"
      rm -f "$system_filter_file"
      return 1
    fi

    rm -f "$system_filter_file"
  fi

  if [[ "$dry_run" != "true" ]]; then
    _juvy_result "Files restored successfully"
  fi
  return 0
}

_juvy_list() {
  local total_files=0 total_dirs=0 total_size=0
  local entry source_path file_size file_date display_size file_count

  _juvy_validate_backup_file_exists || return 1

  if [[ ! -s "$_JUVY_BACKUP_FILE" ]]; then
    echo "No files are currently tracked."
    echo "   Use 'juvy add <path>' to add files or directories."
    return 0
  fi

  echo "Tracked Files and Directories:"
  echo ""

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    source_path="$(_juvy_entry_to_source_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ -d "$source_path" ]]; then
        local dir_info
        if dir_info="$(_juvy_calculate_directory_info "$source_path")"; then
          file_count="$(_juvy_parse_dir_info "$dir_info" count)"
          display_size="$(_juvy_parse_dir_info "$dir_info" human)"
          total_size=$((total_size + $(_juvy_parse_dir_info "$dir_info" bytes)))
          (( ++total_dirs ))
        else
          file_count="?"
          display_size="?"
        fi

        if [[ -d "$source_path" ]]; then
          file_date="$(_juvy_get_file_mtime_human "$source_path")"
          [[ -z "$file_date" ]] && file_date="Unknown"
        else
          file_date="Missing"
        fi

        printf "  [D] %-30s %8s  %s (%s files)\n" "$entry" "$display_size" "$file_date" "$file_count"
      else
        printf "  [X] %-30s %8s  %s (missing)\n" "$entry" "-" "-"
      fi
    else
      if [[ -f "$source_path" ]]; then
        file_size="$(du -h "$source_path" 2>/dev/null | cut -f1)"
        [[ -z "$file_size" ]] && file_size="0B"

        file_date="$(_juvy_get_file_mtime_human "$source_path")"
        [[ -z "$file_date" ]] && file_date="Unknown"

        total_size=$((total_size + $(_juvy_get_file_size "$source_path")))
        (( ++total_files ))

        printf "  [F] %-30s %8s  %s\n" "$entry" "$file_size" "$file_date"
      else
        printf "  [X] %-30s %8s  %s (missing)\n" "~$entry" "-" "-"
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  echo ""
  if (( total_size >= 1073741824 )); then
    display_size="$(( total_size / 1073741824 )).$(( (total_size % 1073741824) / 107374182 ))GB"
  elif (( total_size >= 1048576 )); then
    display_size="$(( total_size / 1048576 )).$(( (total_size % 1048576) / 104857 ))MB"
  elif (( total_size >= 1024 )); then
    display_size="$(( total_size / 1024 ))KB"
  else
    display_size="${total_size}B"
  fi

  echo "Summary: $((total_files + total_dirs)) items tracked, ~$display_size total"
}

# Cross-platform file mtime (human readable)
_juvy_get_file_mtime_human() {
  local file="$1"
  case "$_JUVY_PLATFORM" in
    macos) stat -f '%Sm' "$file" 2>/dev/null ;;
    *)     stat -c '%y' "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 ;;
  esac
}

# Cross-platform file mtime (epoch)
_juvy_get_file_mtime() {
  local file="$1"
  case "$_JUVY_PLATFORM" in
    macos) stat -f '%m' "$file" 2>/dev/null ;;
    *)     stat -c '%Y' "$file" 2>/dev/null ;;
  esac
}

# Cross-platform file size
_juvy_get_file_size() {
  local file="$1"
  case "$_JUVY_PLATFORM" in
    macos) stat -f '%z' "$file" 2>/dev/null || echo 0 ;;
    *)     stat -c '%s' "$file" 2>/dev/null || echo 0 ;;
  esac
}

_juvy_status() {
  local file_arg="$1"
  local last_backup_date last_backup_relative changes_output

  _juvy_validate_backup_dir_exists || return 1
  _juvy_validate_backup_file_exists || return 1

  # If file argument provided, show diff for that file
  if [[ -n "$file_arg" ]]; then
    _juvy_show_file_diff "$file_arg"
    return $?
  fi

  last_backup_date="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"

  if [[ -n "$last_backup_date" ]]; then
    last_backup_relative="$(_juvy_get_relative_time "$last_backup_date")"
    echo "Last backup: $last_backup_date ($last_backup_relative)"
  else
    echo "No backup history found"
  fi

  # Check for changes in backup directory (uncommitted changes)
  local backup_changes="$(_juvy_git status --porcelain 2>/dev/null)"

  # Check for changes in actual tracked files
  local live_changes=0
  local changed_files=()
  local deleted_files=()
  local new_files=()
  local entry source_path backup_path

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    source_path="$(_juvy_entry_to_source_path "$entry")"
    backup_path="$(_juvy_entry_to_backup_path "$entry")"

    if [[ "$entry" == */ ]]; then
      # Directory entry
      if [[ -d "$source_path" && -d "$backup_path" ]]; then
        # Use rsync with itemize-changes to detect directory changes
        local rsync_output
        rsync_output=$(rsync --dry-run --itemize-changes --archive --delete "$source_path/" "$backup_path/" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
          # Check if rsync would make any changes (look for actual change indicators)
          if echo "$rsync_output" | grep -q '^[>*<]'; then
            changed_files+=("$entry")
            (( ++live_changes ))
          fi
        fi
      elif [[ -d "$source_path" && ! -d "$backup_path" ]]; then
        # Directory exists but not backed up
        new_files+=("$entry")
        (( ++live_changes ))
      elif [[ ! -d "$source_path" && -d "$backup_path" ]]; then
        # Directory was deleted
        deleted_files+=("$entry")
        (( ++live_changes ))
      fi
    else
      # File entry
      if [[ -f "$source_path" && -f "$backup_path" ]]; then
        # Compare modification times first (fast check)
        local source_mtime="$(_juvy_get_file_mtime "$source_path")"
        local backup_mtime="$(_juvy_get_file_mtime "$backup_path")"

        if [[ -n "$source_mtime" && -n "$backup_mtime" && "$source_mtime" != "$backup_mtime" ]]; then
          # Times differ, check if content actually changed
          if ! diff -q "$source_path" "$backup_path" >/dev/null 2>&1; then
            changed_files+=("$entry")
            (( ++live_changes ))
          fi
        elif [[ -z "$source_mtime" || -z "$backup_mtime" ]]; then
          # Fallback to content comparison if stat fails
          if ! diff -q "$source_path" "$backup_path" >/dev/null 2>&1; then
            changed_files+=("$entry")
            (( ++live_changes ))
          fi
        fi
      elif [[ -f "$source_path" && ! -f "$backup_path" ]]; then
        # File exists but not backed up
        new_files+=("$entry")
        (( ++live_changes ))
      elif [[ ! -f "$source_path" && -f "$backup_path" ]]; then
        # File was deleted
        deleted_files+=("$entry")
        (( ++live_changes ))
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  # Display results
  if [[ -z "$backup_changes" && $live_changes -eq 0 ]]; then
    echo "No changes since last backup"
    return 0
  fi

  # Show uncommitted changes in backup directory
  if [[ -n "$backup_changes" ]]; then
    echo "Uncommitted changes in backup directory:"

    local status_prefix file_path display_path line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      status_prefix="${line:0:2}"
      file_path="${line:3}"

      if [[ "$file_path" == /* ]]; then
        display_path="~$file_path"
      else
        display_path="~/$file_path"
      fi

      case "$status_prefix" in
        " M"|"M ")
          echo "  [M] $display_path (modified)"
          ;;
        " A"|"A ")
          echo "  [A] $display_path (added)"
          ;;
        " D"|"D ")
          echo "  [D] $display_path (deleted)"
          ;;
        "??")
          echo "  [?] $display_path (untracked)"
          ;;
        *)
          echo "  [*] $display_path (changed)"
          ;;
      esac
    done <<< "$backup_changes"

    if [[ $live_changes -gt 0 ]]; then
      echo ""
    fi
  fi

  # Show changes in actual tracked files
  if [[ $live_changes -gt 0 ]]; then
    echo "Modified files since last backup:"

    # Show modified files
    local file
    for file in "${changed_files[@]}"; do
      echo "  [M] $file (modified)"
    done

    # Show new files (exist but not in backup)
    for file in "${new_files[@]}"; do
      echo "  [+] $file (new)"
    done

    # Show deleted files (in backup but deleted from system)
    for file in "${deleted_files[@]}"; do
      echo "  [-] $file (deleted)"
    done
  fi

  echo ""
  echo "Run 'juvy backup' to save changes"
  echo "Run 'juvy status [file]' for detailed changes"

  # Show remote status if configured
  if [[ -n "$_JUVY_REMOTE_URL" ]]; then
    echo ""
    echo "Remote: $_JUVY_REMOTE_URL"
    if [[ "$_JUVY_REMOTE_PUSH" == "true" ]]; then
      echo "   Auto-push: enabled"
    else
      echo "   Auto-push: disabled"
    fi
  fi
}

_juvy_show_file_diff() {
  local file_arg="$1"
  local backup_file_path source_file_path

  # Resolve source file path and convert to entry format for backup lookup
  local backup_entry

  if [[ "$file_arg" == ~* ]]; then
    # Tilde path - use as-is
    source_file_path="$(_juvy_entry_to_source_path "$file_arg")"
    backup_entry="$file_arg"
  elif [[ "$file_arg" == /* ]]; then
    # Absolute path - convert to entry format
    source_file_path="$file_arg"
    if [[ "$source_file_path" == "$HOME"* ]]; then
      backup_entry="~${source_file_path#$HOME}"
    else
      backup_entry="$source_file_path"
    fi
  else
    # Relative path - resolve to absolute then convert to entry format
    source_file_path="$PWD/$file_arg"
    if [[ "$source_file_path" == "$HOME"* ]]; then
      backup_entry="~${source_file_path#$HOME}"
    else
      backup_entry="$source_file_path"
    fi
  fi

  backup_file_path="$(_juvy_entry_to_backup_path "$backup_entry")"

  if [[ ! -f "$backup_file_path" ]]; then
    echo "File not found in backup: $file_arg" >&2
    echo "   Use 'juvy add $file_arg' to track this file" >&2
    return 1
  fi

  if [[ ! -f "$source_file_path" ]]; then
    echo "Source file not found: $file_arg" >&2
    return 1
  fi

  local last_backup_date
  last_backup_date="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  [[ -z "$last_backup_date" ]] && last_backup_date="Unknown"

  echo "Comparing: $file_arg"
  echo "   Backup: $last_backup_date"
  echo "   Current: $(_juvy_get_file_mtime_human "$source_file_path")"
  echo ""

  if diff -u "$backup_file_path" "$source_file_path" 2>/dev/null; then
    echo "No differences found"
  fi
}



_juvy_get_relative_time() {
  local backup_date="$1"
  local date_bin backup_epoch current_epoch diff_seconds

  if command -v gdate >/dev/null 2>&1; then
    date_bin="gdate"
  else
    date_bin="date"
  fi

  if ! backup_epoch="$("$date_bin" -d "$backup_date" +%s 2>/dev/null)"; then
    backup_epoch="$("$date_bin" -j -f '%Y-%m-%d %H:%M:%S' "$backup_date" +%s 2>/dev/null)"
  fi

  if [[ -z "$backup_epoch" ]]; then
    echo "unknown time ago"
    return
  fi

  current_epoch="$("$date_bin" +%s)"
  diff_seconds=$((current_epoch - backup_epoch))

  if (( diff_seconds < 60 )); then
    echo "${diff_seconds} seconds ago"
  elif (( diff_seconds < 3600 )); then
    echo "$((diff_seconds / 60)) minutes ago"
  elif (( diff_seconds < 86400 )); then
    echo "$((diff_seconds / 3600)) hours ago"
  else
    echo "$((diff_seconds / 86400)) days ago"
  fi
}


## GIT/REMOTE FUNCTIONS ######################################################


# Manage git remote configuration commands

_juvy_remote() {
  case $1 in
    off)
      _juvy_remote_off
      ;;
    push)
      _juvy_remote_push
      ;;
    *)
      if [[ -z $1 ]]; then
        _juvy_remote_status
      elif _juvy_validate_git_url "$1"; then
        _juvy_remote_set "$1"
      else
        echo "juvy remote: Invalid URL or unknown command '$1'" >&2
        echo "Usage:" >&2
        echo "  juvy remote          # Show current status" >&2
        echo "  juvy remote <url>    # Set/change remote" >&2
        echo "  juvy remote off      # Remove remote" >&2
        echo "  juvy remote push     # Manual push" >&2
        return 1
      fi
      ;;
  esac
}

_juvy_remote_set() {
  local url="$1"
  local auto_push="true"
  local remote_name="origin"

  _juvy_validate_backup_dir_exists || return 1

  _juvy_info "Setting up git remote..."

  # Remove existing remote if it exists
  if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    _juvy_git remote remove "$remote_name" 2>/dev/null
  fi

  # Add remote to git repository
  if ! _juvy_git remote add "$remote_name" "$url"; then
    _juvy_error "Failed to add remote"
    return 1
  fi

  # Test connection
  _juvy_info "Testing connection to remote..."
  if ! _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
    echo "Warning: Could not connect to remote (check URL and authentication)" >&2
    echo "   You can still proceed, but push/pull operations may fail" >&2
  else
    echo "Remote connection successful"
  fi

  # Update config file
  _juvy_update_config "JUVY_REMOTE_URL" "$url"
  _juvy_update_config "JUVY_REMOTE_PUSH" "$auto_push"
  _juvy_update_config "JUVY_REMOTE_NAME" "$remote_name"

  echo "Remote configured with auto-sync enabled"
  echo ""
  echo "Your backups will now automatically sync to the remote repository"
}

_juvy_remote_off() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"

  # Check if remote exists
  if ! _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    echo "No remote configured to disable" >&2
    return 0
  fi

  # Remove remote from git
  if ! _juvy_git remote remove "$remote_name"; then
    echo "Failed to remove remote" >&2
    return 1
  fi

  # Remove from config
  _juvy_remove_config "JUVY_REMOTE_URL"
  _juvy_remove_config "JUVY_REMOTE_PUSH"
  _juvy_remove_config "JUVY_REMOTE_NAME"

  echo "Remote disabled - auto-sync turned off"
}

_juvy_remote_push() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"

  if [[ -z "$_JUVY_REMOTE_URL" ]]; then
    echo "No remote configured. Add one with: juvy remote <url>" >&2
    return 1
  fi

  echo "Pushing to remote..."

  # Check if we have commits to push
  if ! _juvy_git log --oneline -1 >/dev/null 2>&1; then
    echo "No commits to push" >&2
    return 1
  fi

  # Push to remote
  if _juvy_git push "$remote_name" "$branch"; then
    echo "Successfully pushed to remote"
    return 0
  else
    local exit_code=$?
    echo "Failed to push to remote" >&2

    # Provide helpful error messages
    if [[ $exit_code -eq 128 ]]; then
      echo "This might be the first push. Try: juvy git push -u $remote_name $branch" >&2
    else
      echo "Check your authentication and network connection" >&2
      echo "For detailed error: juvy git push $remote_name $branch" >&2
    fi

    return $exit_code
  fi
}

_juvy_remote_push_auto() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"

  # Silent version of push for auto-push during backup
  if _juvy_git push "$remote_name" "$branch" >/dev/null 2>&1; then
    return 0
  else
    # Log the error but don't print to stderr (backup should continue)
    _juvy_log_error "Auto-push failed during backup"
    return 1
  fi
}

_juvy_remote_status() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"

  echo "Remote Configuration:"

  if [[ -n "$_JUVY_REMOTE_URL" ]]; then
    echo "   URL: $_JUVY_REMOTE_URL"
    echo "   Name: $remote_name"
    echo "   Auto-push: ${_JUVY_REMOTE_PUSH:-false}"
    echo ""

    # Check if remote is reachable
    if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
      echo "Remote is reachable"

      # Check for unpushed commits
      local unpushed
      unpushed="$(_juvy_git log --oneline "$remote_name/$branch"..HEAD 2>/dev/null | wc -l)"
      unpushed="${unpushed#"${unpushed%%[![:space:]]*}"}"

      if [[ "$unpushed" -gt 0 ]]; then
        echo "$unpushed commit(s) waiting to be pushed"
      else
        echo "Local and remote are in sync"
      fi
    else
      echo "Remote is not reachable"
    fi
  else
    echo "   No remote configured"
    echo ""
    echo "Add a remote with: juvy remote <url>"
  fi
}

_juvy_validate_git_url() {
  local url="$1"

  # Basic URL validation
  case "$url" in
    git@*:*/*|https://*/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_juvy_update_config() {
  local key="$1"
  local value="$2"

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    grep -v "^$key=" "$_JUVY_CONFIG_FILE" > "$_JUVY_CONFIG_FILE.tmp" 2>/dev/null || touch "$_JUVY_CONFIG_FILE.tmp"
    mv "$_JUVY_CONFIG_FILE.tmp" "$_JUVY_CONFIG_FILE"
  fi

  # Add new key=value with robust quoting
  # Use single quotes for safety, but handle single quotes in the value
  if [[ "$value" == *"'"* ]]; then
    # Value contains single quotes, use double quotes with minimal escaping
    local escaped_value="${value//\\/\\\\}"    # Escape backslashes
    escaped_value="${escaped_value//\"/\\\"}"  # Escape double quotes
    escaped_value="${escaped_value//\$/\\\$}"  # Escape dollar signs
    escaped_value="${escaped_value//\`/\\\`}"  # Escape backticks
    echo "$key=\"$escaped_value\"" >> "$_JUVY_CONFIG_FILE"
  else
    # Value doesn't contain single quotes, use single quotes (safest)
    echo "$key='$value'" >> "$_JUVY_CONFIG_FILE"
  fi
}

_juvy_remove_config() {
  local key="$1"

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    grep -v "^$key=" "$_JUVY_CONFIG_FILE" > "$_JUVY_CONFIG_FILE.tmp" 2>/dev/null || touch "$_JUVY_CONFIG_FILE.tmp"
    mv "$_JUVY_CONFIG_FILE.tmp" "$_JUVY_CONFIG_FILE"
  fi
}


## MAIN ENTRY POINT ############################################################

# When executed directly (not sourced), run the juvy command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  juvy "$@"
fi

