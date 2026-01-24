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

## CONFIGURATION FUNCTIONS ###################################################


_juvy_load_config() {
  local line key value

  _JUVY_CONFIG[backup_dir]="$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy"
  _JUVY_CONFIG[remote_url]=""
  _JUVY_CONFIG[remote_push]=""
  _JUVY_CONFIG[remote_name]=""

  if [[ -f "${_JUVY_CONFIG[config_file]}" ]]; then
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
        (JUVY_BACKUP_DIR)
          _JUVY_CONFIG[backup_dir]="$value"
          ;;
        (JUVY_REMOTE_URL)
          _JUVY_CONFIG[remote_url]="$value"
          ;;
        (JUVY_REMOTE_NAME)
          _JUVY_CONFIG[remote_name]="$value"
          ;;
        (JUVY_REMOTE_PUSH)
          _JUVY_CONFIG[remote_push]="$value"
          ;;
      esac
    done < "${_JUVY_CONFIG[config_file]}"
  fi
}

# Common utility functions to reduce code duplication

_juvy_trim_whitespace() {
  local input="$1"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  print "$input"
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
      print ""
      return 1
    fi
    # Handle basic backslash escapes
    value="${value//\\ / }"
    value="${value//\\\$/\$}"
    value="${value//\\\`/\`}"
    value="${value//\\\"/\"}"
    value="${value//\\\'/\'}"
  fi
  
  print "$value"
  return 0
}

# Consolidated prerequisite validation functions

_juvy_validate_backup_file_exists() {
  if [[ ! -f "${_JUVY_CONFIG[backup_file]}" ]]; then
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  return 0
}

_juvy_validate_backup_dir_exists() {
  if [[ ! -d "${_JUVY_CONFIG[backup_dir]}" ]]; then
    print "❌ Backup directory not found: ${_JUVY_CONFIG[backup_dir]}" >&2
    print "   Run 'juvy init' to set up backup directory" >&2
    return 1
  fi
  return 0
}

_juvy_validate_backup_dir_configured() {
  if [[ ! -d "${_JUVY_CONFIG[backup_dir]}" ]]; then
    printf "juvy: Set JUVY_BACKUP_DIR value in %s\n" "${_JUVY_CONFIG[config_file]}" >&2
    return 1
  fi
  return 0
}

_juvy_parse_entry_basic() {
  local entry="$1"
  
  [[ -z "$entry" || "$entry" == \#* ]] && return 1
  
  entry="$(_juvy_trim_whitespace "$entry")"
  [[ -z "$entry" ]] && return 1
  
  print "$entry"
  return 0
}

_juvy_rsync_simple() {
  local rsync_args=("$@")
  local rsync_output
  local rsync_exit_code

  rsync_output=$(rsync "${rsync_args[@]}" 2>&1)
  rsync_exit_code=$?

  if [[ $rsync_exit_code -eq 0 ]]; then
    return 0
  fi

  # Handle partial transfer as success if files were transferred (for restore operations)
  if [[ $rsync_exit_code -eq 23 ]] && [[ "$rsync_output" == *"sent "* ]]; then
    return 0
  fi

  # Show user-friendly error message
  case $rsync_exit_code in
    (1)
      print "❌ rsync syntax or usage error" >&2
      ;;
    (2)
      print "❌ rsync protocol incompatibility" >&2
      ;;
    (11)
      print "❌ rsync file I/O error" >&2
      ;;
    (12)
      print "❌ rsync protocol data stream error" >&2
      ;;
    (23)
      print "❌ rsync partial transfer: some files could not be copied" >&2
      ;;
    (24)
      print "❌ rsync source files vanished" >&2
      ;;
    (*)
      print "❌ rsync failed with error code $rsync_exit_code" >&2
      ;;
  esac

  print "See ${_JUVY_CONFIG[log_file]} for details" >&2
  _juvy_log_error "rsync failed (exit code $rsync_exit_code): $rsync_output"
  return $rsync_exit_code
}

## COMMAND DISPATCHER & HELP ###################################################


juvy() {
  # Initialize paths and load configuration at start of each command
  _juvy_init_paths
  _juvy_load_config
  
  case $1 in
    (init)
      _juvy_init "$@"
      ;;
    (uninstall)
      _juvy_uninstall "$@"
      ;;
    (add)
      shift
      _juvy_add "$@"
      ;;
    (remove)
      shift
      _juvy_remove "$@"
      ;;
    (backup)
      _juvy_backup "$@"
      ;;
    (doctor)
      _juvy_doctor "$@"
      ;;
    (version|--version|-v)
      print "juvy ${_JUVY_CONFIG[version]}"
      ;;
    (git)
      shift
      _juvy_git "$@"
      ;;
    (remote)
      shift
      _juvy_remote "$@"
      ;;
    (update)
      _juvy_update "$@"
      ;;
    (nuke)
      _juvy_nuke "$@"
      ;;
    (restore)
      shift
      _juvy_restore "$@"
      ;;
    (list)
      _juvy_list "$@"
      ;;
    (status)
      shift
      _juvy_status "$@"
      ;;
    (*)
      if [[ -z $1 ]]; then
        _juvy_help
      else
        print "juvy: Unknown command '$1'" >&2
        print "Run 'juvy' for usage information"
      fi
      ;;
  esac
}

_juvy_help() {
  print "juvy ${_JUVY_CONFIG[version]} - dotfile backup utility"
  print ""
  print "Usage: juvy <command>"
  print ""
  print "Commands:"
  print "  init        Initialize juvy configuration"
  print "  add         Add files/directories to backup list (or edit with \$EDITOR)"
  print "              'add ~/.zshrc' or 'add ~/.config/nvim/'"
  print "  remove      Remove files/directories from backup list (or edit with \$EDITOR)"
  print "              'remove ~/.zshrc' or 'remove ~/.config/nvim/'"
  print "  backup      Backup files and directories to configured directory"
  print "  restore     Restore all files from latest backup"
  print "              'restore --dry-run' shows what would be restored"
  print "  list        Show all tracked files and directories"
  print "  status      Show changes since last backup"
  print "              'status [file]' shows detailed diff for specific file"
  print "  doctor      Validate juvy configuration and setup"
  print "              'doctor --fix' applies common repairs"
  print "  git         Run git commands in backup directory"
  print "  remote      Manage git remote for backup synchronization"
  print "              'remote' shows current status"
  print "              'remote <url>' sets/changes remote"
  print "              'remote off' removes remote"
  print "              'remote push' manually pushes to remote"
  print "  update      Update juvy to the latest version"
  print "  version     Show version information"
  print "  uninstall   Remove juvy from system (preserves backups)"
  print "  nuke        Completely destroy juvy and all backups"
  print ""
  print "Backup File Format:"
  print "  # Comments start with #"
  print "  ~/.zshrc                  # Include files"
  print "  ~/.config/nvim/           # Include directories (trailing /)"
  print "  !~/.config/nvim/undo/     # Exclude patterns (prefix with !)"
  print "  ~/.ssh/config             # Inline comments supported"
  print ""
}
_juvy_init() {
  local force_reinit=false
  
  # Check if this is a re-initialization
  if [[ -d "${_JUVY_CONFIG[config_dir]}" && -f "${_JUVY_CONFIG[config_file]}" ]]; then
    force_reinit=true
    print "🔄 Juvy is already initialized. Re-initializing with current settings as defaults..."
    print ""
  fi
  
  if [[ ! -d "${_JUVY_CONFIG[config_dir]}" ]]; then
    mkdir -p "${_JUVY_CONFIG[config_dir]}" > /dev/null 2>&1
  fi

  if [[ ! -f "${_JUVY_CONFIG[backup_file]}" ]]; then
    _juvy_init_smart_defaults
  fi

  if [[ ! -f "${_JUVY_CONFIG[config_file]}" ]]; then
    touch "${_JUVY_CONFIG[config_file]}"
  fi

  _juvy_init_backups "$force_reinit"
}

_juvy_init_backups() { 
  local dir force_reinit="$1"
  local current_backup_dir="${_JUVY_CONFIG[backup_dir]}"
  
  # Always prompt for backup directory (with current value as default)
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_BACKUP_DIR=" "${_JUVY_CONFIG[config_file]}" 2>/dev/null; then
    printf "juvy: Where do you want backups to be stored? (enter for current: %s) " "$current_backup_dir"
    read -r "dir?"

    if [[ -n $dir ]]; then
      if mkdir -p "$dir" > /dev/null 2>&1; then
        _JUVY_CONFIG[backup_dir]="$dir"
      else
        printf "juvy: Unable to create backup directory (%s). Keeping current (%s)\n" "$dir" "$current_backup_dir"
      fi
    fi

    # Save backup directory using _juvy_update_config (it handles quoting internally)
    _juvy_update_config "JUVY_BACKUP_DIR" "${_JUVY_CONFIG[backup_dir]}"
  fi 

  if [[ ! -d "${_JUVY_CONFIG[backup_dir]}/.git" ]]; then
    git init -b main "${_JUVY_CONFIG[backup_dir]}"
  fi
  
  # Prompt for remote setup (always if force_reinit, otherwise only if not configured)
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_REMOTE_URL=" "${_JUVY_CONFIG[config_file]}" 2>/dev/null; then
    _juvy_prompt_remote_setup "$force_reinit"
  fi
}

_juvy_prompt_remote_setup() {
  local force_reinit="$1"
  local remote_url choice
  local current_remote="${_JUVY_CONFIG[remote_url]}"
  local current_push="${_JUVY_CONFIG[remote_push]}"
  
  print ""
  print "🔗 Git Remote Setup (Optional)"
  print "You can sync your backups to a remote git repository."
  print ""
  print "Benefits:"
  print "  • Access backups from multiple devices"
  print "  • Extra backup redundancy"
  print "  • Version history in the cloud"
  print ""
  
  if [[ "$force_reinit" == "true" && -n "$current_remote" ]]; then
    print "Current remote: $current_remote"
    print "Current auto-push: ${current_push:-false}"
    print ""
    print "Enter new git remote URL (or press Enter to keep current):"
  else
    print "Enter git remote URL (or press Enter to skip):"
  fi
  
  print "Examples:"
  print "  git@github.com:username/dotfiles.git"
  print "  https://github.com/username/dotfiles.git"
  print ""
  print -n "Remote URL: "
  read -r "remote_url?"
  
  if [[ -z "$remote_url" ]]; then
    if [[ "$force_reinit" == "true" && -n "$current_remote" ]]; then
      print "✅ Keeping current remote configuration"
      return 0
    else
      print "⏭️  Skipping remote setup. You can add one later with: juvy remote <url>"
      return 0
    fi
  fi
  
  # Validate URL format
  if ! _juvy_validate_git_url "$remote_url"; then
    print "❌ Invalid git URL format. Skipping remote setup."
    print "💡 You can add a remote later with: juvy remote <url>"
    return 0
  fi
  
  print ""
  print "🔍 Testing connection to remote..."
  
  # Add remote temporarily to test connection
  local remote_name="origin"
  local test_success=false
  
  if _juvy_git remote add "$remote_name" "$remote_url" 2>/dev/null; then
    if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
      print "✅ Remote connection successful"
      test_success=true
    else
      print "⚠️  Warning: Could not connect to remote"
      print "   This might be due to authentication or the repository not existing"
      print ""
      print -n "Continue anyway? [y/N] "
      read -r "choice?"
      
      if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        test_success=true
      else
        _juvy_git remote remove "$remote_name" 2>/dev/null
        print "❌ Remote setup cancelled"
        print "💡 You can add a remote later with: juvy remote <url>"
        return 0
      fi
    fi
  else
    print "❌ Failed to add remote. Skipping setup."
    print "💡 You can add a remote later with: juvy remote <url>"
    return 0
  fi
  
  if [[ "$test_success" == "true" ]]; then
    # Update config file
    _juvy_update_config "JUVY_REMOTE_URL" "$remote_url"
    _juvy_update_config "JUVY_REMOTE_PUSH" "true"
    _juvy_update_config "JUVY_REMOTE_NAME" "$remote_name"
    
    print "✅ Remote setup completed successfully"
    print ""
    print "💡 Auto-push is enabled. Future backups will be pushed automatically."
    print "💡 To disable auto-push: Set JUVY_REMOTE_PUSH=false in ${_JUVY_CONFIG[config_file]}"
  fi
}

_juvy_init_smart_defaults() {
  local -a found_files recommended_files sensitive_files
  local -a all_patterns recommended_patterns sensitive_patterns
  local choice
  
  # Define dotfile patterns to search for
  all_patterns=(
    # Shell configs
    "~/.zshrc" "~/.bashrc" "~/.profile" "~/.bash_profile"
    # Git
    "~/.gitconfig" "~/.gitignore_global" "~/.gitignore"
    # SSH (sensitive)
    "~/.ssh/config" "~/.ssh/known_hosts"
    # Editors
    "~/.vimrc" "~/.config/nvim/"
    "~/.emacs" "~/.emacs.d/"
    # Terminal
    "~/.tmux.conf" "~/.alacritty.yml" "~/.alacritty.toml"
    # Tools
    "~/.config/gh/" "~/.aws/config" "~/.npmrc"
  )
  
  recommended_patterns=(
    "~/.zshrc" "~/.bashrc" "~/.profile" "~/.bash_profile"
    "~/.gitconfig" "~/.gitignore_global" "~/.gitignore"
    "~/.vimrc" "~/.config/nvim/"
    "~/.emacs" "~/.emacs.d/"
    "~/.tmux.conf" "~/.alacritty.yml" "~/.alacritty.toml"
    "~/.npmrc"
  )
  
  sensitive_patterns=(
    "~/.ssh/config" "~/.ssh/known_hosts"
    "~/.config/gh/" "~/.aws/config"
  )
  
  print "🔍 Scanning for common dotfiles..."
  print ""
  
  # Scan for existing files
  for pattern in "${all_patterns[@]}"; do
    local full_path="${pattern/#\~/$HOME}"
    if [[ -e "$full_path" ]]; then
      found_files+=("$pattern")
      
      if (( ${recommended_patterns[(Ie)$pattern]} )); then
        recommended_files+=("$pattern")
      fi
      
      if (( ${sensitive_patterns[(Ie)$pattern]} )); then
        sensitive_files+=("$pattern")
      fi
    fi
  done
  
  if (( ${#found_files[@]} == 0 )); then
    print "No common dotfiles found. Creating basic backup list..."
    print "~/.zshrc\n~/.gitconfig" >> "${_JUVY_CONFIG[backup_file]}"
    return 0
  fi
  
  # Display found files
  print "Found these files you might want to backup:"
  print ""
  
  for file in "${found_files[@]}"; do
    local file_status="○"
    local warning=""
    
    if (( ${recommended_files[(Ie)$file]} )); then
      file_status="✓"
    fi
    
    if (( ${sensitive_files[(Ie)$file]} )); then
      warning=" ⚠️ contains sensitive data"
    fi
    
    local full_path="${file/#\~/$HOME}"
    local file_type="(config)"
    
    if [[ -d "$full_path" ]]; then
      file_type="(directory)"
    elif [[ "$file" == *"rc" || "$file" == *"profile" ]]; then
      file_type="(shell config)"
    elif [[ "$file" == *"git"* ]]; then
      file_type="(git config)"
    elif [[ "$file" == *"vim"* || "$file" == *"emacs"* ]]; then
      file_type="(editor config)"
    elif [[ "$file" == *"ssh"* ]]; then
      file_type="(ssh config)"
    elif [[ "$file" == *"tmux"* || "$file" == *"alacritty"* ]]; then
      file_type="(terminal config)"
    fi
    
    printf "  %s %s %s%s\\n" "$file_status" "$file" "$file_type" "$warning"
  done
  
  print ""
  print "Select files to track:"
  print "  a) All files"
  print "  r) Recommended only (non-sensitive)"
  print "  c) Choose individually"
  print "  s) Skip - I'll add manually"
  print ""
  print -n "Choice [a/r/c/s]: "
  read -r "choice?"
  
  case "$choice" in
    (a|A)
      _juvy_add_files_to_backup "${found_files[@]}"
      print "✅ Added all found files to backup list"
      ;;
    (r|R)
      if (( ${#recommended_files[@]} > 0 )); then
        _juvy_add_files_to_backup "${recommended_files[@]}"
        print "✅ Added recommended files to backup list"
      else
        print "~/.zshrc\n~/.gitconfig" >> "${_JUVY_CONFIG[backup_file]}"
        print "✅ Created basic backup list"
      fi
      ;;
    (c|C)
      _juvy_interactive_file_selection "${found_files[@]}"
      ;;
    (s|S|*)
      print "~/.zshrc\n~/.gitconfig" >> "${_JUVY_CONFIG[backup_file]}"
      print "✅ Created basic backup list"
      print "💡 Use 'juvy add <path>' to add files later"
      ;;
  esac
}

_juvy_add_files_to_backup() {
  for file in "$@"; do
    # Add trailing slash for directories
    local full_path="${file/#\~/$HOME}"
    if [[ -d "$full_path" && "$file" != */ ]]; then
      file="$file/"
    fi
    print "$file" >> "${_JUVY_CONFIG[backup_file]}"
  done
}

_juvy_interactive_file_selection() {
  local -a selected_files
  local response
  
  print ""
  print "Select files individually (y/n for each):"
  print ""
  
  for file in "$@"; do
    local full_path="${file/#\~/$HOME}"
    local warning=""
    local file_type="config"
    
    if [[ -d "$full_path" ]]; then
      file_type="directory"
    fi
    
    # Check if sensitive
    if _juvy_is_sensitive_file "$file"; then
      warning=" ⚠️ sensitive"
    fi
    
    print -n "  Include $file ($file_type)$warning? [y/N] "
    read -r "response?"
    
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
      selected_files+=("$file")
    fi
  done
  
  if (( ${#selected_files[@]} > 0 )); then
    _juvy_add_files_to_backup "${selected_files[@]}"
    print "✅ Added ${#selected_files[@]} files to backup list"
  else
    print "~/.zshrc\n~/.gitconfig" >> "${_JUVY_CONFIG[backup_file]}"
    print "✅ Created basic backup list"
  fi
}

_juvy_uninstall() {
  local confirm
  
  print "This will remove juvy from your system (but preserve backups):"
  print "  • Configuration directory: ${_JUVY_CONFIG[config_dir]}"
  print "  • Installation directory: $HOME/.juvy"
  print "  • juvy entry from ~/.zshrc"
  print ""
  print "❗ Backup directory will be preserved: ${_JUVY_CONFIG[backup_dir]}"
  print "Are you sure you want to proceed? [y/N] "
  read -r "confirm?"
  
  if [[ "$confirm" != "y" ]]; then
    print "Remove cancelled"
    return 0
  fi
  
  _juvy_uninstall_internal
  
  print ""
  print "✅ juvy has been removed from your system"
  print "💾 Your backups are preserved in: ${_JUVY_CONFIG[backup_dir]}"
  print "ℹ️  Restart your shell or run: source ~/.zshrc"
}

_juvy_validate_config_file() {
  local issues=()
  local line_num=0
  local line key value
  local backup_dir_set=false
  
  print "🔧 Validating config file (${_JUVY_CONFIG[config_file]})..."
  
  # Test if config can be parsed without errors
  while IFS= read -r line; do
    (( line_num++ ))
    
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
      (JUVY_BACKUP_DIR)
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
          parent_dir="${test_path:h}"
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
      (JUVY_REMOTE_URL)
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
      (JUVY_REMOTE_PUSH)
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
      (JUVY_REMOTE_NAME)
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
      (*)
        issues+=("Line $line_num: Unknown configuration key: $key")
        ;;
    esac
  done < "${_JUVY_CONFIG[config_file]}"
  
  # Report issues
  if (( ${#issues[@]} > 0 )); then
    print "⚠️  Config file issues found:"
    for issue in "${issues[@]}"; do
      print "   $issue"
    done
    return 1
  else
    print "✅ Config file is valid"
    return 0
  fi
}

_juvy_validate_backup_file() {
  local invalid_paths=()
  local large_paths=()
  local exclude_patterns=()
  local line_num=0
  local entry parsed_data entry_type entry_path full_path
  
  print "🔍 Validating backup file..."
  
  while IFS= read -r entry; do
    (( line_num++ ))
    
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
  done < "${_JUVY_CONFIG[backup_file]}"
  
  # Report validation results
  local has_issues=false
  local has_warnings=false

  if (( ${#exclude_patterns[@]} > 0 )); then
    print "ℹ️  Exclude patterns found:"
    for exclude in "${exclude_patterns[@]}"; do
      print "   $exclude"
    done
    print ""
  fi
  
  if (( ${#invalid_paths[@]} > 0 )); then
    print "⚠️  Invalid paths found in backup file:" >&2
    for invalid in "${invalid_paths[@]}"; do
      print "   $invalid" >&2
    done
    print "   These paths will be skipped during backup" >&2
    print ""
    has_issues=true
  fi
  
  if (( ${#large_paths[@]} > 0 )); then
    print "⚠️  Large directories found in backup file:" >&2
    for large in "${large_paths[@]}"; do
      print "   $large" >&2
    done
    print "   These may slow down backup and consume significant storage" >&2
    print ""
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
  
  print "🔄 Starting backup process..."
  
  # Validate backup file before starting rsync
  _juvy_validate_backup_file
  
  # Process backup entries with support for directories and files
  if ! _juvy_process_backup_entries; then
    print "❌ Backup failed" >&2
    _juvy_log "BACKUP FAILED: rsync error"
    return 1
  fi
  
  print "✅ Files synced successfully"
  
  
  if [[ -n $(_juvy_git status --porcelain) ]]; then
    _juvy_git add -A
    if ! _juvy_git commit -m "Backup: $(_juvy_timestamp)"; then
      print "⚠️  Git commit failed, but files were synced" >&2
      _juvy_log "BACKUP FAILED: git commit error"
      return 1
    fi
    print "✅ Changes committed to git"

    # Auto-push if remote is configured and enabled
    local push_status=""
    if [[ "${_JUVY_CONFIG[remote_push]}" == "true" && -n "${_JUVY_CONFIG[remote_url]}" ]]; then
      if _juvy_remote_push_auto; then
        print "✅ Changes pushed to remote"
        push_status=" (pushed to remote)"
      else
        print "⚠️  Failed to push to remote (run 'juvy remote push' manually)" >&2
        push_status=" (push failed)"
      fi
    fi

    _juvy_log "BACKUP OK: changes committed${push_status}"
  else
    print "ℹ️  No changes to commit"
    _juvy_log "BACKUP OK: no changes"
  fi

  print "✅ Backup completed successfully"
}

_juvy_doctor() {
  local fix_mode=false
  local issues=0
  local warnings=0
  local backup_dir="${_JUVY_CONFIG[backup_dir]}"
  local remote_name="${_JUVY_CONFIG[remote_name]:-origin}"
  local remote_url="${_JUVY_CONFIG[remote_url]}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      (--fix)
        fix_mode=true
        shift
        ;;
      (-*)
        print "❌ Unknown option: $1" >&2
        print "Usage: juvy doctor [--fix]" >&2
        return 1
        ;;
      (*)
        shift
        ;;
    esac
  done

  print "🩺 Running juvy doctor..."
  print ""

  if [[ "$fix_mode" == "true" ]]; then
    local fixes=0
    local juvy_script="$HOME/.juvy/juvy.zsh"

    print "🔧 Applying quick fixes..."

    if [[ ! -d "${_JUVY_CONFIG[config_dir]}" ]]; then
      if mkdir -p "${_JUVY_CONFIG[config_dir]}" >/dev/null 2>&1; then
        print "✅ Created config directory"
        (( fixes++ ))
      else
        print "❌ Failed to create config directory: ${_JUVY_CONFIG[config_dir]}" >&2
      fi
    fi

    if [[ ! -f "${_JUVY_CONFIG[config_file]}" ]]; then
      if touch "${_JUVY_CONFIG[config_file]}" >/dev/null 2>&1; then
        print "✅ Created config file"
        (( fixes++ ))
      else
        print "❌ Failed to create config file: ${_JUVY_CONFIG[config_file]}" >&2
      fi
    fi

    if [[ -n "${_JUVY_CONFIG[config_dir]}" && -f "${_JUVY_CONFIG[config_file]}" ]]; then
      if ! grep -q "^JUVY_BACKUP_DIR=" "${_JUVY_CONFIG[config_file]}" 2>/dev/null; then
        _juvy_update_config "JUVY_BACKUP_DIR" "$backup_dir"
        print "✅ Wrote JUVY_BACKUP_DIR to config"
        (( fixes++ ))
      fi
    fi

    if [[ ! -f "${_JUVY_CONFIG[backup_file]}" ]]; then
      if touch "${_JUVY_CONFIG[backup_file]}" >/dev/null 2>&1; then
        print "✅ Created backup file"
        (( fixes++ ))
      else
        print "❌ Failed to create backup file: ${_JUVY_CONFIG[backup_file]}" >&2
      fi
    fi

    if [[ -n "$backup_dir" && ! -e "$backup_dir" ]]; then
      if mkdir -p "$backup_dir" >/dev/null 2>&1; then
        print "✅ Created backup directory"
        (( fixes++ ))
      else
        print "❌ Failed to create backup directory: $backup_dir" >&2
      fi
    fi

    if [[ -n "$backup_dir" && -d "$backup_dir" && ! -d "$backup_dir/.git" ]]; then
      if git init -b main "$backup_dir" >/dev/null 2>&1; then
        print "✅ Initialized backup git repository"
        (( fixes++ ))
      else
        print "❌ Failed to initialize backup git repository: $backup_dir" >&2
      fi
    fi

    if [[ -f "$juvy_script" ]]; then
      if [[ ! -f "$HOME/.zshrc" ]]; then
        if touch "$HOME/.zshrc" >/dev/null 2>&1; then
          print "✅ Created ~/.zshrc"
          (( fixes++ ))
        fi
      fi

      if [[ -f "$HOME/.zshrc" ]] && ! grep -q "source.*\\.juvy/juvy\\.zsh" "$HOME/.zshrc"; then
        {
          print ""
          print "# juvy dotfile backup tool"
          print "source $juvy_script"
        } >> "$HOME/.zshrc"
        print "✅ Added juvy source to ~/.zshrc"
        (( fixes++ ))
      fi
    fi

    if (( fixes == 0 )); then
      print "ℹ️  No quick fixes applied"
    fi

    print ""
  fi

  # Prerequisites
  if [[ "$SHELL" != *"zsh"* ]]; then
    print "❌ Shell is not zsh: $SHELL" >&2
    (( issues++ ))
  else
    print "✅ Shell: zsh"
  fi

  if (( $+commands[rsync] )); then
    print "✅ rsync available"
  else
    print "❌ Missing dependency: rsync" >&2
    (( issues++ ))
  fi

  if (( $+commands[git] )); then
    print "✅ git available"
  else
    print "❌ Missing dependency: git" >&2
    (( issues++ ))
  fi

  print ""

  # Config directory and file
  if [[ -d "${_JUVY_CONFIG[config_dir]}" ]]; then
    if [[ -w "${_JUVY_CONFIG[config_dir]}" ]]; then
      print "✅ Config directory: ${_JUVY_CONFIG[config_dir]}"
    else
      print "❌ Config directory not writable: ${_JUVY_CONFIG[config_dir]}" >&2
      (( issues++ ))
    fi
  else
    print "❌ Config directory missing: ${_JUVY_CONFIG[config_dir]}" >&2
    (( issues++ ))
  fi

  if [[ -f "${_JUVY_CONFIG[config_file]}" ]]; then
    if _juvy_validate_config_file; then
      print "✅ Config file parsed"
    else
      (( issues++ ))
    fi
  else
    print "❌ Config file missing: ${_JUVY_CONFIG[config_file]}" >&2
    (( issues++ ))
  fi

  print ""

  # Backup file
  if [[ -f "${_JUVY_CONFIG[backup_file]}" ]]; then
    if _juvy_validate_backup_file; then
      print "✅ Backup file parsed"
    else
      (( issues++ ))
    fi
  else
    print "❌ Backup file missing: ${_JUVY_CONFIG[backup_file]}" >&2
    (( issues++ ))
  fi

  print ""

  # Backup directory and git repository
  if [[ -z "$backup_dir" ]]; then
    print "❌ Backup directory not configured (JUVY_BACKUP_DIR missing)" >&2
    (( issues++ ))
  elif [[ -e "$backup_dir" && ! -d "$backup_dir" ]]; then
    print "❌ Backup path is not a directory: $backup_dir" >&2
    (( issues++ ))
  elif [[ ! -d "$backup_dir" ]]; then
    print "❌ Backup directory missing: $backup_dir" >&2
    (( issues++ ))
  else
    if [[ -w "$backup_dir" ]]; then
      print "✅ Backup directory: $backup_dir"
    else
      print "❌ Backup directory not writable: $backup_dir" >&2
      (( issues++ ))
    fi

    if _juvy_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      print "✅ Backup git repository found"
    else
      print "❌ Backup directory is not a git repository (run 'juvy init')" >&2
      (( issues++ ))
    fi
  fi

  print ""

  # Remote configuration checks (optional)
  if [[ -n "$remote_url" ]]; then
    if [[ -d "$backup_dir/.git" ]]; then
      if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
        local actual_url
        actual_url="$(_juvy_git remote get-url "$remote_name" 2>/dev/null)"
        if [[ -n "$actual_url" && "$actual_url" != "$remote_url" ]]; then
          print "⚠️  Remote URL mismatch: config=$remote_url git=$actual_url" >&2
          (( warnings++ ))
        else
          print "✅ Remote '$remote_name' configured"
        fi

        if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
          print "✅ Remote reachable"
        else
          print "⚠️  Remote not reachable (check network/auth)" >&2
          (( warnings++ ))
        fi
      else
        print "❌ Remote '$remote_name' not found in backup repo" >&2
        (( issues++ ))
      fi
    else
      print "❌ Cannot check remote: backup repo not initialized" >&2
      (( issues++ ))
    fi
  else
    print "ℹ️  No remote configured"
  fi

  print ""

  # Shell integration
  if [[ -f "$HOME/.zshrc" ]] && grep -q "source.*\\.juvy/juvy\\.zsh" "$HOME/.zshrc"; then
    print "✅ .zshrc loads juvy"
  else
    print "⚠️  .zshrc does not source juvy (run install.sh or add source line)" >&2
    (( warnings++ ))
  fi

  print ""

  if (( issues == 0 && warnings == 0 )); then
    print "✅ Doctor found no issues"
    return 0
  fi

  if (( issues > 0 )); then
    print "❌ Doctor found $issues issue(s) and $warnings warning(s)" >&2
    return 1
  fi

  print "⚠️  Doctor found $warnings warning(s)"
  return 0
}


_juvy_parse_backup_entry() {
  local entry="$1"
  local type="include"
  local path="$entry"
  local comment=""
  
  if [[ "$entry" == !* ]]; then
    type="exclude"
    path="${entry#!}"
  fi
  
  if [[ "$path" == *" #"* ]]; then
    comment="${path#*# }"
    path="${path%% #*}"
    # Trim trailing whitespace
    path="${path%"${path##*[![:space:]]}"}"
  fi
  
  print "type:$type"
  print "path:$path"
  if [[ -n "$comment" ]]; then
    print "comment:$comment"
  fi
}

_juvy_extract_parsed_field() {
  local parsed_data="$1"
  local field="$2"
  local default_value="$3"
  
  local value
  value="$(print "$parsed_data" | grep "^$field:" | cut -d: -f2-)"
  
  if [[ -n "$value" ]]; then
    print "$value"
  else
    print "$default_value"
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
    (\~/*)
      # Explicit home-relative: ~/path -> $HOME/path
      resolved_path="${HOME}${entry#\~}"
      ;;
    (/*)
      # Absolute path: /etc/hosts -> /etc/hosts
      resolved_path="$entry"
      ;;
    (*)
      # Invalid format - not home-relative (~/) or absolute (/)
      print "❌ Invalid path format: $entry" >&2
      print "   Use ~/path for home-relative or /path for absolute" >&2
      return 1
      ;;
  esac

  print "$resolved_path"
}

_juvy_entry_to_backup_path() {
  local entry="$1"
  local source_path backup_path
  
  source_path="$(_juvy_entry_to_source_path "$entry")"
  
  # Map to backup using absolute path structure
  backup_path="${_JUVY_CONFIG[backup_dir]}$source_path"

  print "$backup_path"
}

_juvy_entry_to_relative_path() {
  local entry="$1"
  local base_root="$2"
  local resolved_path
  
  resolved_path="$(_juvy_entry_to_source_path "$entry")"
  
  if [[ "$base_root" == "$HOME" ]]; then
    if [[ "$resolved_path" == "$HOME/"* ]]; then
      print "${resolved_path#$HOME/}"
      return 0
    fi
    return 1
  fi
  
  if [[ "$resolved_path" == "$HOME/"* ]]; then
    return 1
  fi
  
  if [[ "$resolved_path" == /* ]]; then
    print "${resolved_path#/}"
    return 0
  fi
  
  return 1
}

_juvy_add_parent_rules() {
  local dir_path="$1"
  local path_parts=()
  local current_path=""
  
  [[ -z "$dir_path" ]] && return 0
  
  IFS='/' read -rA path_parts <<< "$dir_path"
  
  for part in "${path_parts[@]}"; do
    [[ -z "$part" ]] && continue
    if [[ -n "$current_path" ]]; then
      current_path="$current_path/$part"
    else
      current_path="$part"
    fi
    print "+ /$current_path/"
  done
}

_juvy_add_include_rules() {
  local relative_path="$1"
  local is_dir="$2"
  local clean_path="${relative_path%/}"
  
  if [[ "$is_dir" == "true" ]]; then
    print "+ /$clean_path/"
    print "+ /$clean_path/***"
  else
    print "+ /$relative_path"
  fi
}

_juvy_add_exclude_rules() {
  local relative_path="$1"
  local is_dir="$2"
  local clean_path="${relative_path%/}"

  if [[ "$is_dir" == "true" ]]; then
    print -r -- "- /$clean_path/"
    print -r -- "- /$clean_path/***"
  else
    print -r -- "- /$relative_path"
  fi
}

_juvy_write_unique_rules() {
  local output_file="$1"
  shift
  local -A seen
  local rule

  for rule in "$@"; do
    [[ -z "$rule" ]] && continue
    if [[ -z "${seen[$rule]}" ]]; then
      print -r -- "$rule" >> "$output_file"
      seen[$rule]=1
    fi
  done
}

# Collects backup entries from ${_JUVY_CONFIG[backup_file]}, separating includes and excludes.
# Uses zsh-compatible array assignment via 'set -A' instead of bash namerefs.
_juvy_collect_backup_entries() {
  local include_ref="$1"
  local exclude_ref="$2"
  local entry parsed_data entry_type entry_path
  local -a _temp_includes _temp_excludes

  _temp_includes=()
  _temp_excludes=()

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    parsed_data="$(_juvy_parse_backup_entry "$entry")"
    entry_type="$(_juvy_extract_parsed_field "$parsed_data" "type" "include")"
    entry_path="$(_juvy_extract_parsed_field "$parsed_data" "path" "")"

    if [[ "$entry_type" == "include" ]]; then
      _temp_includes+=("$entry_path")
    elif [[ "$entry_type" == "exclude" ]]; then
      _temp_excludes+=("$entry_path")
    fi
  done < "${_JUVY_CONFIG[backup_file]}"

  # Assign to caller's arrays using zsh 'set -A'
  set -A "$include_ref" "${_temp_includes[@]}"
  set -A "$exclude_ref" "${_temp_excludes[@]}"
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
#
# Uses zsh-compatible eval instead of bash namerefs for array access.
_juvy_build_rsync_filter_file() {
  local base_root="$1"
  local include_ref="$2"
  local exclude_ref="$3"
  local filter_file="$4"
  local extra_exclude_ref="${5:-}"

  # Copy arrays using eval (zsh-compatible alternative to namerefs)
  local -a includes excludes extra_excludes
  eval "includes=(\"\${${include_ref}[@]}\")"
  eval "excludes=(\"\${${exclude_ref}[@]}\")"

  if [[ -n "$extra_exclude_ref" ]]; then
    eval "extra_excludes=(\"\${${extra_exclude_ref}[@]}\")"
  fi

  local -a parent_rules include_rules exclude_rules
  local entry relative_path parent_path is_dir clean_path

  # Start with root directory rule
  parent_rules=("+ /")

  # Process include patterns
  for entry in "${includes[@]}"; do
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
      parent_rules+=("${(@f)$(_juvy_add_parent_rules "$parent_path")}")
    fi

    include_rules+=("${(@f)$(_juvy_add_include_rules "$relative_path" "$is_dir")}")
  done

  # Process exclude patterns
  for entry in "${excludes[@]}" "${extra_excludes[@]}"; do
    if ! relative_path="$(_juvy_entry_to_relative_path "$entry" "$base_root")"; then
      continue
    fi

    is_dir="false"
    if [[ "$entry" == */ ]]; then
      is_dir="true"
    fi

    exclude_rules+=("${(@f)$(_juvy_add_exclude_rules "$relative_path" "$is_dir")}")
  done

  # Write filter file with correct ordering
  : > "$filter_file"
  _juvy_write_unique_rules "$filter_file" "${parent_rules[@]}"  # 1. Parents
  _juvy_write_unique_rules "$filter_file" "${exclude_rules[@]}" # 2. Excludes
  _juvy_write_unique_rules "$filter_file" "${include_rules[@]}" # 3. Includes
  print -r -- "- *" >> "$filter_file"                            # 4. Exclude rest
}


_juvy_process_backup_entries() {
  local -a include_paths exclude_patterns home_paths system_paths
  local entry source_path
  local home_count=0 system_count=0
  
  print "📋 Processing backup entries..."
  
  _juvy_collect_backup_entries include_paths exclude_patterns
  
  print "ℹ️  Processing ${#include_paths[@]} paths"
  
  for entry in "${include_paths[@]}"; do
    source_path="$(_juvy_entry_to_source_path "$entry")"
    
    if [[ "$entry" == */ ]]; then
      if [[ ! -d "$source_path" ]]; then
        print "⚠️  Directory not found: $source_path" >&2
        continue
      fi
    else
      if [[ ! -f "$source_path" ]]; then
        print "⚠️  File not found: $source_path" >&2
        continue
      fi
    fi
    
    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$entry")
    else
      system_paths+=("$entry")
    fi
  done
  
  if (( ${#home_paths[@]} > 0 )); then
    print "🏠 Backing up ${#home_paths[@]} home paths..."
    
    local temp_filter_file
    temp_filter_file="$(mktemp)"
    
    if ! _juvy_build_rsync_filter_file "$HOME" home_paths exclude_patterns "$temp_filter_file"; then
      print "❌ Failed to build filter file for home paths" >&2
      rm -f "$temp_filter_file"
      return 1
    fi
    
    if ! mkdir -p "${_JUVY_CONFIG[backup_dir]}$HOME/" > /dev/null 2>&1; then
      print "❌ Failed to create backup directory for home paths" >&2
      rm -f "$temp_filter_file"
      return 1
    fi
    
    if ! _juvy_rsync_backup_with_filters "$HOME/" "${_JUVY_CONFIG[backup_dir]}$HOME/" "$temp_filter_file"; then
      print "❌ Failed to backup home paths" >&2
      rm -f "$temp_filter_file"
      return 1
    fi
    
    rm -f "$temp_filter_file"
    home_count=${#home_paths[@]}
  fi
  
  if (( ${#system_paths[@]} > 0 )); then
    print "🖥️  Backing up ${#system_paths[@]} system paths..."
    
    local temp_filter_file
    temp_filter_file="$(mktemp)"
    
    if ! _juvy_build_rsync_filter_file "/" system_paths exclude_patterns "$temp_filter_file"; then
      print "❌ Failed to build filter file for system paths" >&2
      rm -f "$temp_filter_file"
      return 1
    fi
    
    if ! mkdir -p "${_JUVY_CONFIG[backup_dir]}" > /dev/null 2>&1; then
      print "❌ Failed to create backup directory" >&2
      rm -f "$temp_filter_file"
      return 1
    fi
    
    if ! _juvy_rsync_backup_with_filters "/" "${_JUVY_CONFIG[backup_dir]}" "$temp_filter_file"; then
      print "❌ Failed to backup system paths" >&2
      rm -f "$temp_filter_file"
      return 1
    fi
    
    rm -f "$temp_filter_file"
    system_count=${#system_paths[@]}
  fi
  
  print "ℹ️  Processed $home_count home and $system_count system paths"
  return 0
}

# Displays filter file contents for debugging rsync issues
_juvy_show_filter_debug() {
  local filter_file="$1"

  print "📋 Filter file contents (for debugging):" >&2
  print "   ----------------------------------------" >&2
  while IFS= read -r line; do
    print "   $line" >&2
  done < "$filter_file"
  print "   ----------------------------------------" >&2
}

_juvy_rsync_backup_with_filters() {
  local source="$1"
  local dest="$2"
  local filter_file="$3"

  if ! _juvy_rsync_simple -av --delete --delete-excluded --filter="merge $filter_file" "$source" "$dest"; then
    _juvy_show_filter_debug "$filter_file"
    return 1
  fi
}

_juvy_rsync_restore_with_filters() {
  local source="$1"
  local dest="$2"
  local filter_file="$3"
  local dry_run="${4:-false}"
  local -a rsync_args

  # Build rsync arguments
  # Use --ignore-times to force copy even when backup files are older than current files
  # (This happens when user modifies a file after backup and wants to restore the original)
  rsync_args=(-av --ignore-times --ignore-errors --filter="merge $filter_file")

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
  /bin/date "+%Y-%m-%d %H:%M:%S"
}

_juvy_log() {
  local message="$1"
  local timestamp

  timestamp="$(_juvy_timestamp)"

  # Ensure log directory exists
  if [[ ! -d "${_JUVY_CONFIG[config_dir]}" ]]; then
    mkdir -p "${_JUVY_CONFIG[config_dir]}" > /dev/null 2>&1
  fi

  print "[$timestamp] $message" >> "${_JUVY_CONFIG[log_file]}"
}

_juvy_log_error() {
  _juvy_log "ERROR: $1"
}


_juvy_git() {
  if [[ -d "${_JUVY_CONFIG[backup_dir]}" ]]; then
    git -C "${_JUVY_CONFIG[backup_dir]}" "$@"
  fi
}

_juvy_update() {
  local temp_script="/tmp/juvy_update.zsh"
  local juvy_script="$HOME/.juvy/juvy.zsh"
  local repo_url="https://raw.githubusercontent.com/danecando/juvy/main/juvy.zsh"
  local latest_version update
  
  print "Checking for updates..."
  
  if ! curl -sSL "$repo_url" -o "$temp_script"; then
    print "❌ Failed to download latest version" >&2
    return 1
  fi
  
  latest_version=$(grep "^JUVY_VERSION=" "$temp_script" | cut -d'"' -f2)
  
  if [[ -z "$latest_version" ]]; then
    print "❌ Failed to extract version from downloaded script" >&2
    rm -f "$temp_script"
    return 1
  fi
  
  if [[ "$latest_version" == "${_JUVY_CONFIG[version]}" ]]; then
    print "✅ juvy is already up to date (v${_JUVY_CONFIG[version]})"
    rm -f "$temp_script"
    return 0
  fi
  
  print "📦 Update available: v${_JUVY_CONFIG[version]} → v$latest_version"
  print "Do you want to update? [Y/n] "
  read -r "update?"
  
  if [[ "$update" == "n" ]]; then
    print "Update cancelled"
    rm -f "$temp_script"
    return 0
  fi
  
  if mv "$temp_script" "$juvy_script"; then
    print "✅ Updated juvy to v$latest_version"
    print "ℹ️  Restart your shell or run: source ~/.zshrc"
  else
    print "❌ Failed to update juvy" >&2
    rm -f "$temp_script"
    return 1
  fi
}

_juvy_nuke() {
  local confirm
  
  print "🚨 WARNING: This will COMPLETELY DESTROY all juvy data including:"
  print "  • Configuration directory: ${_JUVY_CONFIG[config_dir]}"
  print "  • Backup directory: ${_JUVY_CONFIG[backup_dir]}"
  print "  • Installation directory: $HOME/.juvy"
  print "  • juvy entry from ~/.zshrc"
  print ""
  print "💥 ALL YOUR BACKUPS WILL BE DELETED!"
  print "❗ This action cannot be undone!"
  print "Are you absolutely sure? [y/N] "
  read -r "confirm?"
  
  if [[ "$confirm" != "y" ]]; then
    print "Nuke cancelled"
    return 0
  fi
  
  # Call rm function first (removes config, installation, .zshrc)
  _juvy_uninstall_internal
  
  if [[ -d "${_JUVY_CONFIG[backup_dir]}" ]]; then
    rm -rf "${_JUVY_CONFIG[backup_dir]}"
    print "💥 Nuked backup directory"
  fi
  
  print ""
  print "💥 juvy has been completely nuked from your system"
  print "ℹ️  Restart your shell or run: source ~/.zshrc"
}

_juvy_uninstall_internal() {
  if [[ -d "${_JUVY_CONFIG[config_dir]}" ]]; then
    rm -rf "${_JUVY_CONFIG[config_dir]}"
    print "🗑️  Removed configuration directory"
  fi
  
  if [[ -d "$HOME/.juvy" ]]; then
    rm -rf "$HOME/.juvy"
    print "🗑️  Removed installation directory"
  fi
  
  # Remove from .zshrc
  if [[ -f "$HOME/.zshrc" ]] && grep -q "source.*\.juvy/juvy\.zsh" "$HOME/.zshrc"; then
    # Create a temporary file without the juvy lines
    {
      grep -v "source.*\.juvy/juvy\.zsh" "$HOME/.zshrc" | grep -v "# juvy dotfile backup tool"
    } > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
    print "🗑️  Removed juvy from .zshrc"
  fi
}

_juvy_is_sensitive_file() {
  local file="$1"
  local -a sensitive_patterns
  
  sensitive_patterns=(
    "*id_rsa*" "*id_ed25519*" "*id_ecdsa*"  # SSH keys
    "*.pem" "*.key" "*.cert"                 # Certificates
    "*credentials*" "*token*" "*secret*"     # Credentials
    "*.env" ".env.*"                         # Environment files
    "*auth*" "*passwd*"                      # Auth files
  )
  
  local pattern
  for pattern in "${sensitive_patterns[@]}"; do
    if [[ "${file:t}" == ${~pattern} ]]; then
      return 0
    fi
  done
  return 1
}

_juvy_show_security_warning() {
  local file="$1"
  local choice
  
  print "🔒 Security Warning: This appears to be a sensitive file"
  print "   File: $file"
  print ""
  print "Backing up to cloud storage may expose sensitive data."
  print "Options:"
  print "  1) Cancel (recommended)"
  print "  2) Continue anyway"
  print ""
  print -n "Choice [1-2]: "
  read -r "choice?"
  
  case "$choice" in
    (2)
      return 0
      ;;
    (*)
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
    print "❌ Path does not exist: $input_path" >&2
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
  size_bytes=$(/usr/bin/du -sb "$full_path" 2>/dev/null | /usr/bin/cut -f1)
  if [[ -z "$size_bytes" ]]; then
    # macOS doesn't support -sb, use -sk and convert to bytes
    local size_kb
    size_kb=$(/usr/bin/du -sk "$full_path" 2>/dev/null | /usr/bin/cut -f1)
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
  file_count=$(/usr/bin/find "$full_path" -type f 2>/dev/null | /usr/bin/wc -l)
  [[ -z "$file_count" ]] && file_count=0
  file_count="${file_count#"${file_count%%[![:space:]]*}"}"

  # Return colon-separated string (no globals)
  print "$size_bytes:$size_human:$file_count"
}

# Parse directory info string returned by _juvy_calculate_directory_info.
# Usage: _juvy_parse_dir_info "$dir_info" bytes|human|count
_juvy_parse_dir_info() {
  local info="$1"
  local field="$2"

  case "$field" in
    (bytes)
      print "${info%%:*}"
      ;;
    (human)
      local rest="${info#*:}"
      print "${rest%%:*}"
      ;;
    (count)
      print "${info##*:}"
      ;;
  esac
}

_juvy_prompt_large_directory() {
  local path="$1"
  local size_human="$2" 
  local file_count="$3"
  local force="$4"
  local response
  
  if [[ "$force" == "true" ]]; then
    return 0
  fi
  
  print "⚠️  This directory contains:"
  print "   Files: $file_count"
  print "   Size: $size_human"
  print ""
  print "Large backups may be slow and consume significant storage."
  print "Continue? [y/N] "
  read -r "response?"
  
  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    return 1
  fi
  
  return 0
}

_juvy_add() {
  local paths=()
  
  _juvy_validate_backup_file_exists || return 1
  
  # Parse path arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      (-*)
        print "❌ Unknown flag: $1" >&2
        print "Usage: juvy add [path...]" >&2
        return 1
        ;;
      (*)
        paths+=("$1")
        shift
        ;;
    esac
  done
  
  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if (( $+commands[$editor] )); then
      "$editor" "${_JUVY_CONFIG[backup_file]}"
      print "💡 Consider running 'juvy doctor' to check your backup file"
    else
      print "❌ Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
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
        print "❌ Invalid path format: $p. Accepted formats: absolute paths (e.g., /path/to/file), home-relative paths (e.g., ~/file), or paths relative to the current directory." >&2
        continue
      fi

      # Check if path exists and determine type
      if [[ -d "$full_path" ]]; then
        # Directory - ensure it ends with /
        if [[ "$backup_entry" != */ ]]; then
          backup_entry="$backup_entry/"
        fi

        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "${_JUVY_CONFIG[backup_file]}" 2>/dev/null; then
          print "ℹ️  Path already in backup list: $backup_entry"
          continue
        fi

        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            print "❌ Skipped adding sensitive directory: $p"
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
              print "❌ Skipped adding large directory: $p"
              continue
            fi
          fi
        fi
        
        print "$backup_entry" >> "${_JUVY_CONFIG[backup_file]}"
        print "✅ Added directory '$backup_entry' to backup list"
        
      elif [[ -f "$full_path" ]]; then
        # File - ensure it doesn't end with /
        backup_entry="${backup_entry%/}"
        
        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "${_JUVY_CONFIG[backup_file]}" 2>/dev/null; then
          print "ℹ️  Path already in backup list: $backup_entry"
          continue
        fi
        
        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            print "❌ Skipped adding sensitive file: $p"
            continue
          fi
        fi
        
        print "$backup_entry" >> "${_JUVY_CONFIG[backup_file]}"
        print "✅ Added file '$backup_entry' to backup list"

      else
        print "❌ Path not found: $p" >&2
        continue
      fi
    done
  fi
}

_juvy_remove() {
  local paths=()

  _juvy_validate_backup_file_exists || return 1

  # Parse path arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      (-*)
        print "❌ Unknown flag: $1" >&2
        print "Usage: juvy remove [path...]" >&2
        return 1
        ;;
      (*)
        paths+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if (( $+commands[$editor] )); then
      "$editor" "${_JUVY_CONFIG[backup_file]}"
      print "💡 Consider running 'juvy doctor' to check your backup file"
    else
      print "❌ Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
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

      if grep -Fxq "$backup_entry" "${_JUVY_CONFIG[backup_file]}" 2>/dev/null; then
        entry_to_remove="$backup_entry"
        found=true
      elif grep -Fxq "${backup_entry}/" "${_JUVY_CONFIG[backup_file]}" 2>/dev/null; then
        entry_to_remove="${backup_entry}/"
        found=true
      elif grep -Fxq "${backup_entry%/}" "${_JUVY_CONFIG[backup_file]}" 2>/dev/null; then
        entry_to_remove="${backup_entry%/}"
        found=true
      fi

      if [[ "$found" == "true" ]]; then
        # Remove the entry from backup file
        grep -Fxv "$entry_to_remove" "${_JUVY_CONFIG[backup_file]}" > "${_JUVY_CONFIG[backup_file]}.tmp"
        mv "${_JUVY_CONFIG[backup_file]}.tmp" "${_JUVY_CONFIG[backup_file]}"
        print "✅ Removed '$entry_to_remove' from backup list"
      else
        print "ℹ️  Path not in backup list: $p"
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
      (--dry-run|-n)
        dry_run="true"
        shift
        ;;
      (-*)
        print "❌ Unknown option: $1" >&2
        print "Usage: juvy restore [--dry-run]" >&2
        return 1
        ;;
      (*)
        shift
        ;;
    esac
  done

  _juvy_validate_backup_dir_exists || return 1
  _juvy_validate_backup_file_exists || return 1

  local file_count dir_count total_size last_backup

  if ! _juvy_show_restore_preview; then
    print "❌ No files found to restore" >&2
    return 1
  fi

  # In dry-run mode, show what would be restored and exit
  if [[ "$dry_run" == "true" ]]; then
    print ""
    print "🔍 Dry-run mode: showing what would be restored..."
    print ""
    _juvy_perform_restore "$dry_run"
    print ""
    print "ℹ️  No files were modified (dry-run mode)"
    return 0
  fi

  print ""
  print "⚠️  Current files will be backed up to ~/.config/juvy/safety-backup/"
  print ""
  print -n "Proceed with restore? [Y/n] "
  local confirm
  read -r "confirm?"

  if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    print "Restore cancelled"
    return 0
  fi

  print ""
  print "✓ Creating safety backup..."
  local safety_backup_path
  if ! safety_backup_path="$(_juvy_create_safety_backup)"; then
    print "❌ Failed to create safety backup" >&2
    return 1
  fi

  print "✓ Restoring files..."
  if ! _juvy_perform_restore "$dry_run"; then
    print "❌ Restore failed" >&2
    return 1
  fi

  print "✓ Setting permissions..."
  print "✅ Restore complete!"
  print ""
  print "💡 To undo: juvy restore \"$safety_backup_path\""
}

_juvy_show_restore_preview() {
  local entry file_count=0 dir_count=0 total_files=0
  local backup_path source_path file_size last_backup
  
  last_backup="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  if [[ -z "$last_backup" ]]; then
    last_backup="Unknown"
  fi
  
  print "📋 Restore Summary:"
  
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue
    
    backup_path="$(_juvy_entry_to_backup_path "$entry")"
    
    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        (( total_files += dir_file_count ))
        (( dir_count++ ))
      fi
    else
      if [[ -f "$backup_path" ]]; then
        (( total_files++ ))
        (( file_count++ ))
      fi
    fi
  done < "${_JUVY_CONFIG[backup_file]}"
  
  if (( total_files == 0 )); then
    return 1
  fi
  
  print "   $total_files files will be restored from backup"
  print "   Last backup: $last_backup"
  print ""
  
  print "Files to restore:"
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue
    
    backup_path="$(_juvy_entry_to_backup_path "$entry")"
    
    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        print "  ~$entry ($dir_file_count files)"
      fi
    else
      if [[ -f "$backup_path" ]]; then
        file_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
        [[ -z "$file_size" ]] && file_size="0B"
        print "  ~$entry ($file_size)"
      fi
    fi
  done < "${_JUVY_CONFIG[backup_file]}"
  
  return 0
}

_juvy_create_safety_backup() {
  local timestamp safety_dir entry backup_path source_path dest_path dest_dir
  
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  safety_dir="${_JUVY_CONFIG[config_dir]}/safety-backup/$timestamp"
  
  if ! mkdir -p "$safety_dir" > /dev/null 2>&1; then
    print "❌ Failed to create safety backup directory: $safety_dir" >&2
    return 1
  fi
  
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue
    
    source_path="$(_juvy_entry_to_source_path "$entry")"
    
    if [[ -e "$source_path" ]]; then
      dest_path="$safety_dir$entry"
      dest_dir="$(dirname "$dest_path")"
      
      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        print "❌ Failed to create safety backup directory: $dest_dir" >&2
        return 1
      fi
      
      if [[ "$entry" == */ ]]; then
        if [[ -d "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_dir/" > /dev/null 2>&1; then
            print "❌ Failed to backup directory: $source_path" >&2
            return 1
          fi
        fi
      else
        if [[ -f "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_path" > /dev/null 2>&1; then
            print "❌ Failed to backup file: $source_path" >&2
            return 1
          fi
        fi
      fi
    fi
  done < "${_JUVY_CONFIG[backup_file]}"
  
  print "$safety_dir"
  return 0
}

_juvy_perform_restore() {
  local dry_run="${1:-false}"
  local backup_dir="${_JUVY_CONFIG[backup_dir]}"
  local -a include_paths exclude_patterns home_paths system_paths
  local source_path

  if [[ "$dry_run" == "true" ]]; then
    print "🔄 Showing what would be restored from backup..."
  else
    print "🔄 Restoring files from backup..."
  fi

  _juvy_collect_backup_entries include_paths exclude_patterns

  for entry in "${include_paths[@]}"; do
    source_path="$(_juvy_entry_to_source_path "$entry")"
    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$entry")
    else
      system_paths+=("$entry")
    fi
  done

  if (( ${#home_paths[@]} > 0 )); then
    local home_filter_file
    home_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "$HOME" home_paths exclude_patterns "$home_filter_file"; then
      print "❌ Failed to build restore filter for home paths" >&2
      rm -f "$home_filter_file"
      return 1
    fi

    if ! _juvy_rsync_restore_with_filters "$backup_dir$HOME" "$HOME" "$home_filter_file" "$dry_run"; then
      print "❌ Failed to restore home files" >&2
      rm -f "$home_filter_file"
      return 1
    fi

    rm -f "$home_filter_file"
  fi

  if (( ${#system_paths[@]} > 0 )); then
    local system_filter_file
    local -a extra_excludes
    system_filter_file="$(mktemp)"
    extra_excludes=("/.git/")

    if ! _juvy_build_rsync_filter_file "/" system_paths exclude_patterns "$system_filter_file" extra_excludes; then
      print "❌ Failed to build restore filter for system paths" >&2
      rm -f "$system_filter_file"
      return 1
    fi

    if ! _juvy_rsync_restore_with_filters "$backup_dir" "/" "$system_filter_file" "$dry_run"; then
      print "❌ Failed to restore system files" >&2
      rm -f "$system_filter_file"
      return 1
    fi

    rm -f "$system_filter_file"
  fi

  if [[ "$dry_run" != "true" ]]; then
    print "✅ Files restored successfully"
  fi
  return 0
}

_juvy_list() {
  local total_files=0 total_dirs=0 total_size=0
  local entry source_path file_size file_date display_size file_count
  
  _juvy_validate_backup_file_exists || return 1
  
  if [[ ! -s "${_JUVY_CONFIG[backup_file]}" ]]; then
    print "📋 No files are currently tracked."
    print "   Use 'juvy add <path>' to add files or directories."
    return 0
  fi
  
  print "📋 Tracked Files and Directories:"
  print ""
  
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
          (( total_dirs++ ))
        else
          file_count="?"
          display_size="?"
        fi
        
        if [[ -d "$source_path" ]]; then
          file_date="$(stat -f '%Sm' "$source_path" 2>/dev/null || stat -c '%y' "$source_path" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)"
          [[ -z "$file_date" ]] && file_date="Unknown"
        else
          file_date="Missing"
        fi
        
        printf "  📁 %-30s %8s  %s (%s files)\\n" "$entry" "$display_size" "$file_date" "$file_count"
      else
        printf "  ❌ %-30s %8s  %s (missing)\\n" "$entry" "-" "-"
      fi
    else
      if [[ -f "$source_path" ]]; then
        file_size="$(du -h "$source_path" 2>/dev/null | cut -f1)"
        [[ -z "$file_size" ]] && file_size="0B"
        
        file_date="$(stat -f '%Sm' "$source_path" 2>/dev/null || stat -c '%y' "$source_path" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)"
        [[ -z "$file_date" ]] && file_date="Unknown"
        
        total_size=$((total_size + $(stat -f '%z' "$source_path" 2>/dev/null || stat -c '%s' "$source_path" 2>/dev/null || echo 0)))
        (( total_files++ ))
        
        printf "  📄 %-30s %8s  %s\\n" "$entry" "$file_size" "$file_date"
      else
        printf "  ❌ %-30s %8s  %s (missing)\\n" "~$entry" "-" "-"
      fi
    fi
  done < "${_JUVY_CONFIG[backup_file]}"
  
  print ""
  if (( total_size >= 1073741824 )); then
    display_size="$(( total_size / 1073741824 )).$(( (total_size % 1073741824) / 107374182 ))GB"
  elif (( total_size >= 1048576 )); then
    display_size="$(( total_size / 1048576 )).$(( (total_size % 1048576) / 104857 ))MB"
  elif (( total_size >= 1024 )); then
    display_size="$(( total_size / 1024 ))KB"
  else
    display_size="${total_size}B"
  fi
  
  print "📊 Summary: $((total_files + total_dirs)) items tracked, ~$display_size total"
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
    print "✅ Last backup: $last_backup_date ($last_backup_relative)"
  else
    print "⚠️  No backup history found"
  fi
  
  # Check for changes in backup directory (uncommitted changes)
  local backup_changes="$(_juvy_git status --porcelain 2>/dev/null)"
  
  # Check for changes in actual tracked files
  local live_changes=0
  local changed_files=()
  local deleted_files=()
  local new_files=()
  
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue
    
    local source_path="$(_juvy_entry_to_source_path "$entry")"
    local backup_path="$(_juvy_entry_to_backup_path "$entry")"
    
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
            (( live_changes++ ))
          fi
        fi
      elif [[ -d "$source_path" && ! -d "$backup_path" ]]; then
        # Directory exists but not backed up
        new_files+=("$entry")
        (( live_changes++ ))
      elif [[ ! -d "$source_path" && -d "$backup_path" ]]; then
        # Directory was deleted
        deleted_files+=("$entry")
        (( live_changes++ ))
      fi
    else
      # File entry
      if [[ -f "$source_path" && -f "$backup_path" ]]; then
        # Compare modification times first (fast check)
        local source_mtime="$(stat -f '%m' "$source_path" 2>/dev/null || stat -c '%Y' "$source_path" 2>/dev/null)"
        local backup_mtime="$(stat -f '%m' "$backup_path" 2>/dev/null || stat -c '%Y' "$backup_path" 2>/dev/null)"
        
        if [[ -n "$source_mtime" && -n "$backup_mtime" && "$source_mtime" != "$backup_mtime" ]]; then
          # Times differ, check if content actually changed
          if ! /usr/bin/diff -q "$source_path" "$backup_path" >/dev/null 2>&1; then
            changed_files+=("$entry")
            (( live_changes++ ))
          fi
        elif [[ -z "$source_mtime" || -z "$backup_mtime" ]]; then
          # Fallback to content comparison if stat fails
          if ! /usr/bin/diff -q "$source_path" "$backup_path" >/dev/null 2>&1; then
            changed_files+=("$entry")
            (( live_changes++ ))
          fi
        fi
      elif [[ -f "$source_path" && ! -f "$backup_path" ]]; then
        # File exists but not backed up
        new_files+=("$entry")
        (( live_changes++ ))
      elif [[ ! -f "$source_path" && -f "$backup_path" ]]; then
        # File was deleted
        deleted_files+=("$entry")
        (( live_changes++ ))
      fi
    fi
  done < "${_JUVY_CONFIG[backup_file]}"
  
  # Display results
  if [[ -z "$backup_changes" && $live_changes -eq 0 ]]; then
    print "✅ No changes since last backup"
    return 0
  fi
  
  # Show uncommitted changes in backup directory
  if [[ -n "$backup_changes" ]]; then
    print "📝 Uncommitted changes in backup directory:"
    
    local status_prefix file_path display_path
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
        (" M"|"M ")
          print "  📝 $display_path (modified)"
          ;;
        (" A"|"A ")
          print "  ✅ $display_path (added)"
          ;;
        (" D"|"D ")
          print "  ❌ $display_path (deleted)"
          ;;
        ("??") 
          print "  ❓ $display_path (untracked)"
          ;;
        (*)
          print "  📝 $display_path (changed)"
          ;;
      esac
    done <<< "$backup_changes"
    
    if [[ $live_changes -gt 0 ]]; then
      print ""
    fi
  fi
  
  # Show changes in actual tracked files
  if [[ $live_changes -gt 0 ]]; then
    print "📝 Modified files since last backup:"
    
    # Show modified files
    for file in "${changed_files[@]}"; do
      print "  📝 $file (modified)"
    done
    
    # Show new files (exist but not in backup)
    for file in "${new_files[@]}"; do
      print "  ✅ $file (new)"
    done
    
    # Show deleted files (in backup but deleted from system)
    for file in "${deleted_files[@]}"; do
      print "  ❌ $file (deleted)"
    done
  fi
  
  print ""
  print "💡 Run 'juvy backup' to save changes"
  print "💡 Run 'juvy status [file]' for detailed changes"
  
  # Show remote status if configured
  if [[ -n "${_JUVY_CONFIG[remote_url]}" ]]; then
    print ""
    print "🔗 Remote: ${_JUVY_CONFIG[remote_url]}"
    if [[ "${_JUVY_CONFIG[remote_push]}" == "true" ]]; then
      print "   Auto-push: enabled"
    else
      print "   Auto-push: disabled"
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
    print "❌ File not found in backup: $file_arg" >&2
    print "   Use 'juvy add $file_arg' to track this file" >&2
    return 1
  fi
  
  if [[ ! -f "$source_file_path" ]]; then
    print "❌ Source file not found: $file_arg" >&2
    return 1
  fi
  
  local last_backup_date
  last_backup_date="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  [[ -z "$last_backup_date" ]] && last_backup_date="Unknown"
  
  print "📄 Comparing: $file_arg"
  print "   Backup: $last_backup_date"
  print "   Current: $(stat -f '%Sm' "$source_file_path" 2>/dev/null || stat -c '%y' "$source_file_path" 2>/dev/null | cut -d'.' -f1 || echo 'Unknown')"
  print ""
  
  if diff -u "$backup_file_path" "$source_file_path" 2>/dev/null; then
    print "✅ No differences found"
  fi
}



_juvy_get_relative_time() {
  local backup_date="$1"
  local date_bin backup_epoch current_epoch diff_seconds

  if command -v gdate >/dev/null 2>&1; then
    date_bin="gdate"
  else
    date_bin="/bin/date"
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
    (off)
      _juvy_remote_off
      ;;
    (push)
      _juvy_remote_push
      ;;
    (*)
      if [[ -z $1 ]]; then
        _juvy_remote_status
      elif _juvy_validate_git_url "$1"; then
        _juvy_remote_set "$1"
      else
        print "juvy remote: Invalid URL or unknown command '$1'" >&2
        print "Usage:" >&2
        print "  juvy remote          # Show current status" >&2
        print "  juvy remote <url>    # Set/change remote" >&2
        print "  juvy remote off      # Remove remote" >&2
        print "  juvy remote push     # Manual push" >&2
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
  
  print "🔗 Setting up git remote..."
  
  # Remove existing remote if it exists
  if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    _juvy_git remote remove "$remote_name" 2>/dev/null
  fi
  
  # Add remote to git repository
  if ! _juvy_git remote add "$remote_name" "$url"; then
    print "❌ Failed to add remote" >&2
    return 1
  fi
  
  # Test connection
  print "🔍 Testing connection to remote..."
  if ! _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
    print "⚠️  Warning: Could not connect to remote (check URL and authentication)" >&2
    print "   You can still proceed, but push/pull operations may fail" >&2
  else
    print "✅ Remote connection successful"
  fi
  
  # Update config file
  _juvy_update_config "JUVY_REMOTE_URL" "$url"
  _juvy_update_config "JUVY_REMOTE_PUSH" "$auto_push"
  _juvy_update_config "JUVY_REMOTE_NAME" "$remote_name"
  
  print "✅ Remote configured with auto-sync enabled"
  print ""
  print "💡 Your backups will now automatically sync to the remote repository"
}

_juvy_remote_off() {
  local remote_name="${_JUVY_CONFIG[remote_name]:-origin}"
  
  # Check if remote exists
  if ! _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    print "ℹ️  No remote configured to disable" >&2
    return 0
  fi
  
  # Remove remote from git
  if ! _juvy_git remote remove "$remote_name"; then
    print "❌ Failed to remove remote" >&2
    return 1
  fi
  
  # Remove from config
  _juvy_remove_config "JUVY_REMOTE_URL"
  _juvy_remove_config "JUVY_REMOTE_PUSH"
  _juvy_remove_config "JUVY_REMOTE_NAME"
  
  print "✅ Remote disabled - auto-sync turned off"
}

_juvy_remote_push() {
  local remote_name="${_JUVY_CONFIG[remote_name]:-origin}"
  local branch="main"
  
  if [[ -z "${_JUVY_CONFIG[remote_url]}" ]]; then
    print "❌ No remote configured. Add one with: juvy remote <url>" >&2
    return 1
  fi
  
  print "⬆️  Pushing to remote..."
  
  # Check if we have commits to push
  if ! _juvy_git log --oneline -1 >/dev/null 2>&1; then
    print "❌ No commits to push" >&2
    return 1
  fi
  
  # Push to remote
  if _juvy_git push "$remote_name" "$branch"; then
    print "✅ Successfully pushed to remote"
    return 0
  else
    local exit_code=$?
    print "❌ Failed to push to remote" >&2
    
    # Provide helpful error messages
    if [[ $exit_code -eq 128 ]]; then
      print "💡 This might be the first push. Try: juvy git push -u $remote_name $branch" >&2
    else
      print "💡 Check your authentication and network connection" >&2
      print "💡 For detailed error: juvy git push $remote_name $branch" >&2
    fi
    
    return $exit_code
  fi
}

_juvy_remote_push_auto() {
  local remote_name="${_JUVY_CONFIG[remote_name]:-origin}"
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
  local remote_name="${_JUVY_CONFIG[remote_name]:-origin}"
  local branch="main"
  
  print "🔗 Remote Configuration:"
  
  if [[ -n "${_JUVY_CONFIG[remote_url]}" ]]; then
    print "   URL: ${_JUVY_CONFIG[remote_url]}"
    print "   Name: $remote_name"
    print "   Auto-push: ${_JUVY_CONFIG[remote_push]:-false}"
    print ""
    
    # Check if remote is reachable
    if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
      print "✅ Remote is reachable"
      
      # Check for unpushed commits
      local unpushed
      unpushed="$(_juvy_git log --oneline "$remote_name/$branch"..HEAD 2>/dev/null | wc -l)"
      unpushed="${unpushed#"${unpushed%%[![:space:]]*}"}"
      
      if [[ "$unpushed" -gt 0 ]]; then
        print "⬆️  $unpushed commit(s) waiting to be pushed"
      else
        print "✅ Local and remote are in sync"
      fi
    else
      print "❌ Remote is not reachable"
    fi
  else
    print "   No remote configured"
    print ""
    print "💡 Add a remote with: juvy remote <url>"
  fi
}

_juvy_validate_git_url() {
  local url="$1"
  
  # Basic URL validation
  case "$url" in
    (git@*:*/*|https://*/*)
      return 0
      ;;
    (*)
      return 1
      ;;
  esac
}

_juvy_update_config() {
  local key="$1"
  local value="$2"
  
  if [[ -f "${_JUVY_CONFIG[config_file]}" ]]; then
    grep -v "^$key=" "${_JUVY_CONFIG[config_file]}" > "${_JUVY_CONFIG[config_file]}.tmp" 2>/dev/null || touch "${_JUVY_CONFIG[config_file]}.tmp"
    mv "${_JUVY_CONFIG[config_file]}.tmp" "${_JUVY_CONFIG[config_file]}"
  fi
  
  # Add new key=value with robust quoting
  # Use single quotes for safety, but handle single quotes in the value
  if [[ "$value" == *"'"* ]]; then
    # Value contains single quotes, use double quotes with minimal escaping
    local escaped_value="${value//\\/\\\\}"    # Escape backslashes
    escaped_value="${escaped_value//\"/\\\"}"  # Escape double quotes
    escaped_value="${escaped_value//\$/\\\$}"  # Escape dollar signs  
    escaped_value="${escaped_value//\`/\\\`}"  # Escape backticks
    print "$key=\"$escaped_value\"" >> "${_JUVY_CONFIG[config_file]}"
  else
    # Value doesn't contain single quotes, use single quotes (safest)
    print "$key='$value'" >> "${_JUVY_CONFIG[config_file]}"
  fi
}

_juvy_remove_config() {
  local key="$1"

  if [[ -f "${_JUVY_CONFIG[config_file]}" ]]; then
    grep -v "^$key=" "${_JUVY_CONFIG[config_file]}" > "${_JUVY_CONFIG[config_file]}.tmp" 2>/dev/null || touch "${_JUVY_CONFIG[config_file]}.tmp"
    mv "${_JUVY_CONFIG[config_file]}.tmp" "${_JUVY_CONFIG[config_file]}"
  fi
}

