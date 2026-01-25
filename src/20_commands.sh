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

  # Add remote temporarily to test connection
  local remote_name="origin"
  local test_success=false

  if _juvy_git remote add "$remote_name" "$remote_url" 2>/dev/null; then
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

