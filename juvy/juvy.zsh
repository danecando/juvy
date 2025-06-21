emulate -L zsh

typeset -g JUVY_VERSION="1.0.1"
typeset -g JUVY_CONFIG_DIR="$HOME/.config/juvy"
typeset -g JUVY_CONFIG="$JUVY_CONFIG_DIR/config"
typeset -g JUVY_BACKUP="$JUVY_CONFIG_DIR/backup"
typeset -g JUVY_LOG="$JUVY_CONFIG_DIR/log"

# Global configuration array
typeset -gA _JUVY_CONFIG

_juvy_load_config() {
  local line key value
  
  _JUVY_CONFIG[backup_dir]="$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy"
  _JUVY_CONFIG[remote_url]=""
  _JUVY_CONFIG[remote_push]=""
  _JUVY_CONFIG[remote_name]=""
  _JUVY_CONFIG[schedule_enabled]="false"
  _JUVY_CONFIG[schedule_frequency]="hourly"
  _JUVY_CONFIG[schedule_time]="02:00"
  _JUVY_CONFIG[schedule_method]="launchd"
  
  if [[ -f "$JUVY_CONFIG" ]]; then
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
        (JUVY_SCHEDULE_ENABLED)
          _JUVY_CONFIG[schedule_enabled]="$value"
          ;;
        (JUVY_SCHEDULE_FREQUENCY)
          _JUVY_CONFIG[schedule_frequency]="$value"
          ;;
        (JUVY_SCHEDULE_TIME)
          _JUVY_CONFIG[schedule_time]="$value"
          ;;
        (JUVY_SCHEDULE_METHOD)
          _JUVY_CONFIG[schedule_method]="$value"
          ;;
      esac
    done < "$JUVY_CONFIG"
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
  if [[ ! -f "$JUVY_BACKUP" ]]; then
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
    printf "juvy: Set JUVY_BACKUP_DIR value in %s\n" "$JUVY_CONFIG" >&2
    return 1
  fi
  return 0
}

_juvy_validate_time_format() {
  local time_value="$1"
  
  if [[ "$time_value" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    return 0
  else
    print "❌ Invalid time format. Expected: HH:MM (24-hour format)" >&2
    print "   Example: '14:30' or '02:15'" >&2
    return 1
  fi
}

_juvy_validate_schedule_frequency() {
  local frequency="$1"
  
  case "$frequency" in
    (daily|weekly|hourly)
      return 0
      ;;
    (*)
      print "❌ Invalid schedule frequency: $frequency" >&2
      print "   Expected: daily, weekly, or hourly" >&2
      return 1
      ;;
  esac
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
  
  print "See $JUVY_LOG for details" >&2
  _juvy_log_error "rsync failed (exit code $rsync_exit_code): $rsync_output"
  return $rsync_exit_code
}

juvy() {
  # Load configuration at start of each command
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
    (backup)
      _juvy_backup "$@"
      ;;
    (validate)
      _juvy_validate "$@"
      ;;
    (version|--version|-v)
      print "juvy $JUVY_VERSION"
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
      _juvy_restore "$@"
      ;;
    (list)
      _juvy_list "$@"
      ;;
    (status)
      shift
      _juvy_status "$@"
      ;;
    (schedule)
      shift
      _juvy_schedule "$@"
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

_juvy_init() {
  local force_reinit=false
  
  # Check if this is a re-initialization
  if [[ -d "$JUVY_CONFIG_DIR" && -f "$JUVY_CONFIG" ]]; then
    force_reinit=true
    print "🔄 Juvy is already initialized. Re-initializing with current settings as defaults..."
    print ""
  fi
  
  if [[ ! -d "$JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi

  if [[ ! -f "$JUVY_BACKUP" ]]; then
    _juvy_init_smart_defaults
  fi

  if [[ ! -f "$JUVY_CONFIG" ]]; then
    touch "$JUVY_CONFIG"
  fi

  _juvy_init_backups "$force_reinit"
}

_juvy_init_backups() { 
  local dir force_reinit="$1"
  local current_backup_dir="${_JUVY_CONFIG[backup_dir]}"
  
  # Always prompt for backup directory (with current value as default)
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_BACKUP_DIR=" "$JUVY_CONFIG" 2>/dev/null; then
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
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_REMOTE_URL=" "$JUVY_CONFIG" 2>/dev/null; then
    _juvy_prompt_remote_setup "$force_reinit"
  fi
  
  # Prompt for schedule setup (always if force_reinit, otherwise only if not configured)
  if [[ "$force_reinit" == "true" ]] || ! grep -q "JUVY_SCHEDULE_ENABLED=" "$JUVY_CONFIG" 2>/dev/null; then
    _juvy_prompt_schedule_setup "$force_reinit"
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
      print "⏭️  Skipping remote setup. You can add one later with: juvy remote add <url>"
      return 0
    fi
  fi
  
  # Validate URL format
  if ! _juvy_validate_git_url "$remote_url"; then
    print "❌ Invalid git URL format. Skipping remote setup."
    print "💡 You can add a remote later with: juvy remote add <url>"
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
        print "💡 You can add a remote later with: juvy remote add <url>"
        return 0
      fi
    fi
  else
    print "❌ Failed to add remote. Skipping setup."
    print "💡 You can add a remote later with: juvy remote add <url>"
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
    print "💡 To disable auto-push: Set JUVY_REMOTE_PUSH=false in $JUVY_CONFIG"
  fi
}

_juvy_prompt_schedule_setup() {
  local force_reinit="$1"
  local choice frequency time
  local current_enabled="${_JUVY_CONFIG[schedule_enabled]}"
  local current_frequency="${_JUVY_CONFIG[schedule_frequency]}"
  local current_time="${_JUVY_CONFIG[schedule_time]}"
  
  print ""
  print "🕒 Schedule Setup (Optional)"
  print "Juvy can automatically backup your files on a schedule."
  print ""
  print "Available frequencies:"
  print "  ✓ hourly  - Run backup every hour"
  print "  ○ daily   - Run backup once per day at specified time"
  print "  ○ weekly  - Run backup once per week (Sundays) at specified time"
  print ""
  
  if [[ "$force_reinit" == "true" && "$current_enabled" == "true" ]]; then
    printf "Currently enabled: %s" "$current_frequency"
    if [[ "$current_frequency" != "hourly" ]]; then
      printf " at %s" "$current_time"
    fi
    print ""
    print ""
  fi
  
  printf "Enable automated backups? [Y/n]: "
  read -r "choice?"
  
  if [[ "$choice" =~ ^[Nn]$ ]]; then
    _juvy_update_config "JUVY_SCHEDULE_ENABLED" "false"
    print "⏭️  Skipping automated backups. You can enable later with: juvy schedule enable"
    return 0
  fi
  
  # Default to hourly if user pressed enter or said yes
  frequency="hourly"
  
  printf "Select frequency [hourly]: "
  read -r "frequency?"
  
  # Set default if empty
  if [[ -z "$frequency" ]]; then
    frequency="hourly"
  fi
  
  # Validate frequency
  if ! _juvy_validate_schedule_frequency "$frequency"; then
    print "Invalid frequency. Defaulting to hourly."
    frequency="hourly"
  fi
  
  # For daily/weekly, ask for time
  if [[ "$frequency" == "daily" || "$frequency" == "weekly" ]]; then
    printf "Backup time (HH:MM format) [02:00]: "
    read -r "time?"
    
    if [[ -z "$time" ]]; then
      time="02:00"
    fi
    
    if ! _juvy_validate_time_format "$time"; then
      print "Invalid time format. Using 02:00."
      time="02:00"
    fi
    
    _juvy_update_config "JUVY_SCHEDULE_TIME" "$time"
  fi
  
  # Save configuration
  _juvy_update_config "JUVY_SCHEDULE_ENABLED" "true"
  _juvy_update_config "JUVY_SCHEDULE_FREQUENCY" "$frequency"
  
  # Install the schedule
  if _juvy_install_launchd_agent; then
    if [[ "$frequency" != "hourly" ]]; then
      print "✅ Automated backups enabled ($frequency at $time)"
    else
      print "✅ Automated backups enabled ($frequency)"
    fi
  else
    print "❌ Failed to enable automated backups"
    print "   You can try again later with: juvy schedule enable"
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
    print "~/.zshrc\n~/.gitconfig" >> "$JUVY_BACKUP"
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
        print "~/.zshrc\n~/.gitconfig" >> "$JUVY_BACKUP"
        print "✅ Created basic backup list"
      fi
      ;;
    (c|C)
      _juvy_interactive_file_selection "${found_files[@]}"
      ;;
    (s|S|*)
      print "~/.zshrc\n~/.gitconfig" >> "$JUVY_BACKUP"
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
    print "$file" >> "$JUVY_BACKUP"
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
    print "~/.zshrc\n~/.gitconfig" >> "$JUVY_BACKUP"
    print "✅ Created basic backup list"
  fi
}

_juvy_uninstall() {
  local confirm
  
  print "This will remove juvy from your system (but preserve backups):"
  print "  • Configuration directory: $JUVY_CONFIG_DIR"
  print "  • Installation directory: $HOME/.juvy"
  print "  • Automated backup schedule (if enabled)"
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
  
  print "🔧 Validating config file ($JUVY_CONFIG)..."
  
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
        local test_path
        if ! test_path="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi
        
        # Check if backup directory is accessible
        if [[ -n "$test_path" ]] && ! mkdir -p "$test_path" 2>/dev/null; then
          issues+=("Line $line_num: Cannot create backup directory: $test_path")
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
      (JUVY_SCHEDULE_ENABLED)
        local test_bool
        if ! test_bool="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi
        
        if [[ "$test_bool" != "true" && "$test_bool" != "false" ]]; then
          issues+=("Line $line_num: Invalid boolean value (use true/false): $test_bool")
        fi
        ;;
      (JUVY_SCHEDULE_FREQUENCY)
        local test_freq
        if ! test_freq="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi
        
        if [[ -n "$test_freq" ]] && [[ "$test_freq" != "daily" && "$test_freq" != "weekly" && "$test_freq" != "hourly" ]]; then
          issues+=("Line $line_num: Invalid schedule frequency (use daily/weekly/hourly): $test_freq")
        fi
        ;;
      (JUVY_SCHEDULE_TIME)
        local test_time
        if ! test_time="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi
        
        if [[ -n "$test_time" ]] && [[ ! "$test_time" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
          issues+=("Line $line_num: Invalid time format (use HH:MM): $test_time")
        fi
        ;;
      (JUVY_SCHEDULE_METHOD)
        local test_method
        if ! test_method="$(_juvy_parse_quoted_value "$value")"; then
          issues+=("Line $line_num: Invalid value format: $value")
          continue
        fi
        
        if [[ -n "$test_method" ]] && [[ "$test_method" != "launchd" && "$test_method" != "cron" ]]; then
          issues+=("Line $line_num: Invalid schedule method (use launchd/cron): $test_method")
        fi
        ;;
      (*)
        issues+=("Line $line_num: Unknown configuration key: $key")
        ;;
    esac
  done < "$JUVY_CONFIG"
  
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
      if _juvy_calculate_directory_info "$entry_path"; then
        if (( JUVY_DIR_SIZE_BYTES > 104857600 )); then
          large_paths+=("Line $line_num: $entry_path ($JUVY_DIR_SIZE_HUMAN, $JUVY_DIR_FILE_COUNT files)")
        fi
      fi
    fi
  done < "$JUVY_BACKUP"
  
  # Report validation results
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
  fi
  
  if (( ${#large_paths[@]} > 0 )); then
    print "⚠️  Large directories found in backup file:" >&2
    for large in "${large_paths[@]}"; do
      print "   $large" >&2
    done
    print "   These may slow down backup and consume significant storage" >&2
    print ""
  fi
  
  return 0
}

_juvy_backup() {
  _juvy_validate_backup_dir_configured || return 1
  _juvy_validate_backup_file_exists || return 1
  
  print "🔄 Starting backup process..."
  
  # Validate backup file before starting rsync
  _juvy_validate_backup_file
  
  # Process backup entries with support for directories and files
  if ! _juvy_process_backup_entries; then
    print "❌ Backup failed" >&2
    return 1
  fi
  
  print "✅ Files synced successfully"
  
  
  if [[ -n $(_juvy_git status --porcelain) ]]; then
    _juvy_git add -A
    if ! _juvy_git commit -m "Backup: $(_juvy_timestamp)"; then
      print "⚠️  Git commit failed, but files were synced" >&2
      _juvy_log_error "Git commit failed after successful rsync"
      return 1
    fi
    print "✅ Changes committed to git"
    
    # Auto-push if remote is configured and enabled
    if [[ "${_JUVY_CONFIG[remote_push]}" == "true" && -n "${_JUVY_CONFIG[remote_url]}" ]]; then
      if _juvy_remote_push_auto; then
        print "✅ Changes pushed to remote"
      else
        print "⚠️  Failed to push to remote (run 'juvy remote push' manually)" >&2
      fi
    fi
  else
    print "ℹ️  No changes to commit"
  fi
  
  print "✅ Backup completed successfully"
}

_juvy_validate() {
  local config_valid=true
  local backup_valid=true
  
  print "🔍 Validating juvy configuration..."
  
  # Validate config file
  if [[ -f "$JUVY_CONFIG" ]]; then
    if ! _juvy_validate_config_file; then
      config_valid=false
    fi
  else
    print "⚠️  No config file found at $JUVY_CONFIG"
    config_valid=false
  fi
  
  # Validate backup file
  if [[ -f "$JUVY_BACKUP" ]]; then
    if ! _juvy_validate_backup_file; then
      backup_valid=false  
    fi
  else
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    backup_valid=false
  fi
  
  if [[ "$config_valid" == "true" && "$backup_valid" == "true" ]]; then
    print "✅ All validation checks passed"
    return 0
  else
    print "⚠️  Some validation issues found (see above)"
    return 1
  fi
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


# New unified path mapping utilities

_juvy_entry_to_source_path() {
  local entry="$1"
  local resolved_path
  
  # Handle different path formats consistently
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
      # Implicit home-relative: .zshrc -> $HOME/.zshrc
      resolved_path="$HOME/$entry"
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


_juvy_add_directory_patterns() {
  local dir_path="$1"
  local include_file="$2"
  local path_parts=()
  local current_path=""
  
  dir_path="${dir_path%/}"
  
  # Split path into parts and add each parent directory
  if [[ -n "$dir_path" ]]; then
    # Convert path to array of parts
    IFS='/' read -rA path_parts <<< "$dir_path"
    
    # Add each parent directory progressively
    for part in "${path_parts[@]}"; do
      if [[ -n "$current_path" ]]; then
        current_path="$current_path/$part"
      else
        current_path="$part"
      fi
      print "$current_path/" >> "$include_file"
    done
    
    # Add recursive pattern for directory contents
    print "$dir_path/**" >> "$include_file"
  fi
}

_juvy_add_file_patterns() {
  local file_path="$1"
  local include_file="$2"
  local dir_path="${file_path%/*}"
  local path_parts=()
  local current_path=""
  
  # Add parent directories if file is not in root
  if [[ "$dir_path" != "$file_path" ]] && [[ -n "$dir_path" ]]; then
    # Convert directory path to array of parts
    IFS='/' read -rA path_parts <<< "$dir_path"
    
    # Add each parent directory progressively
    for part in "${path_parts[@]}"; do
      if [[ -n "$current_path" ]]; then
        current_path="$current_path/$part"
      else
        current_path="$part"
      fi
      print "$current_path/" >> "$include_file"
    done
  fi
  
  # Add the file itself
  print "$file_path" >> "$include_file"
}


_juvy_process_backup_entries() {
  local -a include_paths exclude_patterns final_paths home_paths system_paths
  local entry parsed_data entry_type entry_path
  local home_count=0 system_count=0
  local temp_home_list temp_system_list
  
  print "📋 Processing backup entries..."
  
  # First pass: collect include and exclude patterns
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue
    
    # Parse entry
    parsed_data="$(_juvy_parse_backup_entry "$entry")"
    entry_type="$(_juvy_extract_parsed_field "$parsed_data" "type" "include")"
    entry_path="$(_juvy_extract_parsed_field "$parsed_data" "path" "")"
    
    if [[ "$entry_type" == "include" ]]; then
      include_paths+=("$entry_path")
    elif [[ "$entry_type" == "exclude" ]]; then
      exclude_patterns+=("$entry_path")
    fi
  done < "$JUVY_BACKUP"
  
  # Second pass: filter includes against excludes
  local should_exclude
  for include_path in "${include_paths[@]}"; do
    should_exclude=false
    
    # Check against each exclude pattern
    for exclude_pattern in "${exclude_patterns[@]}"; do
      if _juvy_path_matches_pattern "$include_path" "$exclude_pattern"; then
        print "⚠️  Excluding $include_path (matches pattern: $exclude_pattern)"
        should_exclude=true
        break
      fi
    done
    
    if [[ "$should_exclude" == "false" ]]; then
      final_paths+=("$include_path")
    fi
  done
  
  print "ℹ️  Processing ${#final_paths[@]} paths"
  
  # Separate home paths from system paths and validate
  local source_path
  for clean_path in "${final_paths[@]}"; do
    source_path="$(_juvy_entry_to_source_path "$clean_path")"
    
    # Check if path exists
    if [[ "$clean_path" == */ ]]; then
      # Directory entry
      if [[ ! -d "$source_path" ]]; then
        print "⚠️  Directory not found: $source_path" >&2
        continue
      fi
    else
      # File entry
      if [[ ! -f "$source_path" ]]; then
        print "⚠️  File not found: $source_path" >&2
        continue
      fi
    fi
    
    # Categorize as home or system path
    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$clean_path")
    else
      system_paths+=("$clean_path")
    fi
  done
  
  # Process home paths with single rsync operation
  if (( ${#home_paths[@]} > 0 )); then
    print "🏠 Backing up ${#home_paths[@]} home paths..."
    
    # Create include patterns for home paths
    local temp_include_file
    temp_include_file="$(mktemp)"
    
    # Build include patterns from home paths
    local backup_path dest_dir
    for clean_path in "${home_paths[@]}"; do
      source_path="$(_juvy_entry_to_source_path "$clean_path")"
      backup_path="$(_juvy_entry_to_backup_path "$clean_path")"
      
      # Create destination directory structure
      dest_dir="$(dirname "$backup_path")"
      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        print "❌ Failed to create destination directory: $dest_dir" >&2
        rm -f "$temp_include_file"
        return 1
      fi
      
      # Add relative path from HOME to include file
      local relative_path="${source_path#$HOME/}"
      
      if [[ "$clean_path" == */ ]]; then
        # Directory entry - need parent dirs, directory, and recursive pattern
        _juvy_add_directory_patterns "$relative_path" "$temp_include_file"
      else
        # File entry - need parent dirs and file
        _juvy_add_file_patterns "$relative_path" "$temp_include_file"
      fi
    done
    
    # Use rsync with --delete and include patterns for home paths
    if ! _juvy_rsync_with_includes "$HOME/" "${_JUVY_CONFIG[backup_dir]}$HOME/" "$temp_include_file"; then
      print "❌ Failed to backup home paths" >&2
      rm -f "$temp_include_file"
      return 1
    fi
    
    rm -f "$temp_include_file"
    home_count=${#home_paths[@]}
  fi
  
  # Process system paths with single rsync operation
  if (( ${#system_paths[@]} > 0 )); then
    print "🖥️  Backing up ${#system_paths[@]} system paths..."
    
    # Create include patterns for system paths
    local temp_include_file
    temp_include_file="$(mktemp)"
    
    # Build include patterns from system paths
    local backup_path dest_dir
    for clean_path in "${system_paths[@]}"; do
      source_path="$(_juvy_entry_to_source_path "$clean_path")"
      backup_path="$(_juvy_entry_to_backup_path "$clean_path")"
      
      # Create destination directory structure
      dest_dir="$(dirname "$backup_path")"
      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        print "❌ Failed to create destination directory: $dest_dir" >&2
        rm -f "$temp_include_file"
        return 1
      fi
      
      # Add relative path from root to include file
      local relative_path="${source_path#/}"
      
      if [[ "$clean_path" == */ ]]; then
        # Directory entry - need parent dirs, directory, and recursive pattern
        _juvy_add_directory_patterns "$relative_path" "$temp_include_file"
      else
        # File entry - need parent dirs and file
        _juvy_add_file_patterns "$relative_path" "$temp_include_file"
      fi
    done
    
    # Use rsync with --delete and include patterns for system paths
    if ! _juvy_rsync_with_includes "/" "${_JUVY_CONFIG[backup_dir]}" "$temp_include_file"; then
      print "❌ Failed to backup system paths" >&2
      rm -f "$temp_include_file"
      return 1
    fi
    
    rm -f "$temp_include_file"
    system_count=${#system_paths[@]}
  fi
  
  print "ℹ️  Processed $home_count home and $system_count system paths"
  return 0
}

_juvy_path_matches_pattern() {
  local path="$1"
  local pattern="$2"
  local resolved_path resolved_pattern
  
  # Convert both to filesystem paths for comparison
  resolved_path="$(_juvy_entry_to_source_path "$path")"
  resolved_pattern="$(_juvy_entry_to_source_path "$pattern")"
  
  # Handle different types of patterns
  case "$pattern" in
    (*"*"*|*"?"*|*"["*)
      # Glob pattern - use zsh pattern matching
      setopt LOCAL_OPTIONS EXTENDED_GLOB
      [[ "$resolved_path" == ${~resolved_pattern} ]]
      return $?
      ;;
    (*/*)
      # Path pattern - check if path starts with pattern (for directories)
      if [[ "$pattern" == */ ]]; then
        # Directory exclusion - check if path is under this directory
        [[ "$resolved_path" == "$resolved_pattern"* ]]
      else
        # Exact path match
        [[ "$resolved_path" == "$resolved_pattern" ]]
      fi
      return $?
      ;;
    (*)
      # Simple filename pattern - check basename
      local path_basename="${resolved_path:t}"
      local pattern_basename="${resolved_pattern:t}"
      
      if [[ "$pattern_basename" == *"*"* || "$pattern_basename" == *"?"* ]]; then
        setopt LOCAL_OPTIONS EXTENDED_GLOB
        [[ "$path_basename" == ${~pattern_basename} ]]
      else
        [[ "$path_basename" == "$pattern_basename" ]]
      fi
      return $?
      ;;
  esac
}

_juvy_rsync_with_includes() {
  local source="$1"
  local dest="$2" 
  local include_file="$3"
  
  _juvy_rsync_simple -av --delete --delete-excluded --include-from="$include_file" --exclude='*' "$source" "$dest"
}

_juvy_rsync_restore() {
  local source="$1"
  local dest="$2"
  
  # Use rsync to copy entire backup structure to filesystem root
  # No --delete flags to avoid removing existing files not in backup
  # Exclude .git directory to avoid restoring backup metadata
  # Use --ignore-errors to continue despite permission issues on system directories
  _juvy_rsync_simple -av --exclude='.git' --ignore-errors "$source/" "$dest"
}


_juvy_timestamp() {
  /bin/date "+%Y-%m-%d %H:%M:%S"
}

_juvy_log_error() {
  local message="$1"
  local timestamp
  
  timestamp="$(_juvy_timestamp)"
  
  # Ensure log directory exists
  if [[ ! -d "$JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi
  
  print "[$timestamp] $message" >> "$JUVY_LOG"
}


_juvy_git() {
  if [[ -d "${_JUVY_CONFIG[backup_dir]}" ]]; then
    git -C "${_JUVY_CONFIG[backup_dir]}" "$@"
  fi
}

_juvy_update() {
  local temp_script="/tmp/juvy_update.zsh"
  local juvy_script="$HOME/.juvy/juvy.zsh"
  local repo_url="https://raw.githubusercontent.com/danecando/juvy/main/juvy/juvy.zsh"
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
  
  if [[ "$latest_version" == "$JUVY_VERSION" ]]; then
    print "✅ juvy is already up to date (v$JUVY_VERSION)"
    rm -f "$temp_script"
    return 0
  fi
  
  print "📦 Update available: v$JUVY_VERSION → v$latest_version"
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
  print "  • Configuration directory: $JUVY_CONFIG_DIR"
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
  # Remove schedule agent first (before removing config)
  if _juvy_uninstall_launchd_agent; then
    print "🗑️  Removed automated backup schedule"
  fi
  
  if [[ -d "$JUVY_CONFIG_DIR" ]]; then
    rm -rf "$JUVY_CONFIG_DIR"
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
  local path="$1"
  local full_path
  
  if [[ "$path" = /* ]]; then
    full_path="$path"
  else
    # Path relative to HOME (remove leading ./ or /)
    path="${path#./}"
    path="${path#/}"
    full_path="$HOME/$path"
  fi
  
  if [[ ! -e "$full_path" ]]; then
    print "❌ Path does not exist: $path" >&2
    return 1
  fi
  
  return 0
}

_juvy_calculate_directory_info() {
  local path="$1"
  local full_path
  local size_bytes size_human file_count
  
  # Use path as-is if it's already absolute, otherwise resolve it
  if [[ "$path" = /* ]]; then
    full_path="$path"
  else
    # Path is relative to HOME or in backup entry format
    if [[ "$path" = ~* ]]; then
      full_path="${path/#\~/$HOME}"
    else
      path="${path#./}"
      path="${path#/}" 
      full_path="$HOME/$path"
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
  
  # Return values via global variables for zsh compatibility
  JUVY_DIR_SIZE_BYTES="$size_bytes"
  JUVY_DIR_SIZE_HUMAN="$size_human"
  JUVY_DIR_FILE_COUNT="$file_count"
  
  return 0
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
      "$editor" "$JUVY_BACKUP"
      print "💡 Consider running 'juvy validate' to check your backup file"
    else
      print "❌ Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
      return 1
    fi
  else
    # Arguments provided, validate and append to file
    for path in "${paths[@]}"; do
      # Validate path exists
      if ! _juvy_validate_path "$path"; then
        continue
      fi
      
      # Convert to absolute path if relative
      local full_path
      if [[ "$path" == /* ]]; then
        full_path="$path"
      else
        full_path="$PWD/$path"
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
        print "❌ Invalid path format: $path. Accepted formats: absolute paths (e.g., /path/to/file), home-relative paths (e.g., ~/file), or paths relative to the current directory." >&2
        continue
      fi
      
      # Check if path exists and determine type
      if [[ -d "$full_path" ]]; then
        # Directory - ensure it ends with /
        if [[ "$backup_entry" != */ ]]; then
          backup_entry="$backup_entry/"
        fi
        
        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$JUVY_BACKUP" 2>/dev/null; then
          print "ℹ️  Path already in backup list: $backup_entry"
          continue
        fi
        
        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            print "❌ Skipped adding sensitive directory: $path"
            continue
          fi
        fi
        
        # For directories, check size and prompt if needed
        if _juvy_calculate_directory_info "$path"; then
          # Check if directory is larger than 100MB (104857600 bytes)
          if (( JUVY_DIR_SIZE_BYTES > 104857600 )); then
            if ! _juvy_prompt_large_directory "$path" "$JUVY_DIR_SIZE_HUMAN" "$JUVY_DIR_FILE_COUNT" "false"; then
              print "❌ Skipped adding large directory: $path"
              continue
            fi
          fi
        fi
        
        print "$backup_entry" >> "$JUVY_BACKUP"
        print "✅ Added directory '$backup_entry' to backup list"
        
      elif [[ -f "$full_path" ]]; then
        # File - ensure it doesn't end with /
        backup_entry="${backup_entry%/}"
        
        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$JUVY_BACKUP" 2>/dev/null; then
          print "ℹ️  Path already in backup list: $backup_entry"
          continue
        fi
        
        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            print "❌ Skipped adding sensitive file: $path"
            continue
          fi
        fi
        
        print "$backup_entry" >> "$JUVY_BACKUP"
        print "✅ Added file '$backup_entry' to backup list"
        
      else
        print "❌ Path not found: $path" >&2
        continue
      fi
    done
  fi
}

_juvy_restore() {
  _juvy_validate_backup_dir_exists || return 1
  _juvy_validate_backup_file_exists || return 1
  
  local file_count dir_count total_size last_backup
  
  if ! _juvy_show_restore_preview; then
    print "❌ No files found to restore" >&2
    return 1
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
  if ! _juvy_perform_restore; then
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
  done < "$JUVY_BACKUP"
  
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
  done < "$JUVY_BACKUP"
  
  return 0
}

_juvy_create_safety_backup() {
  local timestamp safety_dir entry backup_path source_path dest_path dest_dir
  
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  safety_dir="$JUVY_CONFIG_DIR/safety-backup/$timestamp"
  
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
  done < "$JUVY_BACKUP"
  
  print "$safety_dir"
  return 0
}

_juvy_perform_restore() {
  local backup_dir="${_JUVY_CONFIG[backup_dir]}"
  
  print "🔄 Restoring files from backup..."
  
  # Single rsync operation to restore entire backup structure
  if ! _juvy_rsync_restore "$backup_dir" "/"; then
    print "❌ Failed to restore from backup" >&2
    return 1
  fi
  
  print "✅ Files restored successfully"
  return 0
}

_juvy_list() {
  local total_files=0 total_dirs=0 total_size=0
  local entry source_path file_size file_date display_size file_count
  
  _juvy_validate_backup_file_exists || return 1
  
  if [[ ! -s "$JUVY_BACKUP" ]]; then
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
        if _juvy_calculate_directory_info "$source_path"; then
          file_count="$JUVY_DIR_FILE_COUNT"
          display_size="$JUVY_DIR_SIZE_HUMAN"
          total_size=$((total_size + JUVY_DIR_SIZE_BYTES))
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
  done < "$JUVY_BACKUP"
  
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
  done < "$JUVY_BACKUP"
  
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


_juvy_remote() {
  case $1 in
    (off)
      _juvy_remote_off "$@"
      ;;
    (push)
      _juvy_remote_push "$@"
      ;;
    (*)
      if [[ -z $1 ]]; then
        _juvy_remote_status "$@"
      elif _juvy_validate_git_url "$1"; then
        # Treat as URL - set remote and enable auto-sync
        _juvy_remote_set "$1"
      else
        print "juvy remote: Invalid URL or unknown command '$1'" >&2
        print "Usage:" >&2
        print "  juvy remote <url>      # Set remote and enable auto-sync" >&2
        print "  juvy remote           # Show current status" >&2
        print "  juvy remote off       # Disable remote" >&2
        print "  juvy remote push      # Manual push" >&2
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
    print "❌ No remote configured. Add one with: juvy remote add <url>" >&2
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
    print "💡 Add a remote with: juvy remote add <url>"
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
  
  if [[ -f "$JUVY_CONFIG" ]]; then
    grep -v "^$key=" "$JUVY_CONFIG" > "$JUVY_CONFIG.tmp" 2>/dev/null || touch "$JUVY_CONFIG.tmp"
    mv "$JUVY_CONFIG.tmp" "$JUVY_CONFIG"
  fi
  
  # Add new key=value with robust quoting
  # Use single quotes for safety, but handle single quotes in the value
  if [[ "$value" == *"'"* ]]; then
    # Value contains single quotes, use double quotes with minimal escaping
    local escaped_value="${value//\\/\\\\}"    # Escape backslashes
    escaped_value="${escaped_value//\"/\\\"}"  # Escape double quotes
    escaped_value="${escaped_value//\$/\\\$}"  # Escape dollar signs  
    escaped_value="${escaped_value//\`/\\\`}"  # Escape backticks
    print "$key=\"$escaped_value\"" >> "$JUVY_CONFIG"
  else
    # Value doesn't contain single quotes, use single quotes (safest)
    print "$key='$value'" >> "$JUVY_CONFIG"
  fi
}

_juvy_remove_config() {
  local key="$1"
  
  if [[ -f "$JUVY_CONFIG" ]]; then
    grep -v "^$key=" "$JUVY_CONFIG" > "$JUVY_CONFIG.tmp" 2>/dev/null || touch "$JUVY_CONFIG.tmp"
    mv "$JUVY_CONFIG.tmp" "$JUVY_CONFIG"
  fi
}

_juvy_create_launchd_plist() {
  local plist_path="$HOME/Library/LaunchAgents/com.juvy.backup.plist"
  local frequency="${_JUVY_CONFIG[schedule_frequency]}"
  local time="${_JUVY_CONFIG[schedule_time]}"
  local hour minute
  
  # Parse time
  hour="${time%:*}"
  minute="${time#*:}"
  
  # Create LaunchAgents directory if it doesn't exist
  mkdir -p "$HOME/Library/LaunchAgents"
  
  # Generate plist content based on frequency
  case "$frequency" in
    (daily)
      cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.juvy.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/zsh</string>
        <string>-c</string>
        <string>source ~/.zshrc && juvy backup</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
    <key>StandardErrorPath</key>
    <string>$JUVY_LOG</string>
    <key>StandardOutPath</key>
    <string>$JUVY_LOG</string>
</dict>
</plist>
EOF
      ;;
    (weekly)
      cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.juvy.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/zsh</string>
        <string>-c</string>
        <string>source ~/.zshrc && juvy backup</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
        <key>Weekday</key>
        <integer>0</integer>
    </dict>
    <key>StandardErrorPath</key>
    <string>$JUVY_LOG</string>
    <key>StandardOutPath</key>
    <string>$JUVY_LOG</string>
</dict>
</plist>
EOF
      ;;
    (hourly)
      cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.juvy.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/zsh</string>
        <string>-c</string>
        <string>source ~/.zshrc && juvy backup</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardErrorPath</key>
    <string>$JUVY_LOG</string>
    <key>StandardOutPath</key>
    <string>$JUVY_LOG</string>
</dict>
</plist>
EOF
      ;;
  esac
  
  print "$plist_path"
}

_juvy_install_launchd_agent() {
  local plist_path
  
  # Create the plist file
  plist_path="$(_juvy_create_launchd_plist)"
  
  if [[ ! -f "$plist_path" ]]; then
    print "❌ Failed to create plist file" >&2
    return 1
  fi
  
  # Unload existing agent if loaded
  launchctl unload "$plist_path" 2>/dev/null || true
  
  # Load the new agent
  if launchctl load "$plist_path" 2>/dev/null; then
    return 0
  else
    print "❌ Failed to load launchd agent" >&2
    return 1
  fi
}

_juvy_uninstall_launchd_agent() {
  local plist_path="$HOME/Library/LaunchAgents/com.juvy.backup.plist"
  
  # Unload the agent if it exists
  if [[ -f "$plist_path" ]]; then
    launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
  fi
  
  return 0
}

_juvy_launchd_status() {
  local plist_path="$HOME/Library/LaunchAgents/com.juvy.backup.plist"
  
  if [[ -f "$plist_path" ]]; then
    print "   Plist file: exists"
    
    # Check if loaded
    if launchctl list | grep -q com.juvy.backup; then
      print "   Agent status: loaded"
    else
      print "   Agent status: not loaded"
    fi
  else
    print "   Plist file: missing"
    print "   Agent status: not installed"
  fi
}

_juvy_schedule() {
  case $1 in
    (enable|on)
      shift
      _juvy_schedule_enable "$@"
      ;;
    (disable|off)
      _juvy_schedule_disable "$@"
      ;;
    (status)
      _juvy_schedule_status "$@"
      ;;
    (daily|weekly|hourly)
      _juvy_schedule_set_frequency "$@"
      ;;
    (*)
      _juvy_schedule_help
      ;;
  esac
}

_juvy_schedule_enable() {
  local frequency="${1:-${_JUVY_CONFIG[schedule_frequency]}}"
  local time="${2:-${_JUVY_CONFIG[schedule_time]}}"
  
  _juvy_validate_backup_file_exists || return 1
  
  if [[ -n "$1" ]]; then
    if ! _juvy_validate_schedule_frequency "$frequency"; then
      return 1
    fi
  fi
  
  if [[ -n "$2" ]]; then
    if ! _juvy_validate_time_format "$time"; then
      return 1
    fi
  fi
  
  print "🕒 Enabling automated backups..."
  print "   Frequency: $frequency"
  print "   Time: $time"
  
  _juvy_update_config "JUVY_SCHEDULE_ENABLED" "true"
  _juvy_update_config "JUVY_SCHEDULE_FREQUENCY" "$frequency"
  _juvy_update_config "JUVY_SCHEDULE_TIME" "$time"
  
  # Install the actual schedule
  if _juvy_install_launchd_agent; then
    print "✅ Automated backups enabled"
    print "   Next backup will run according to schedule"
    print "   Use 'juvy schedule status' to check status"
  else
    print "❌ Failed to enable automated backups"
    return 1
  fi
}

_juvy_schedule_disable() {
  print "🕒 Disabling automated backups..."
  
  _juvy_update_config "JUVY_SCHEDULE_ENABLED" "false"
  
  if _juvy_uninstall_launchd_agent; then
    print "✅ Automated backups disabled"
  else
    print "⚠️  Schedule disabled in config, but may need manual cleanup"
    return 1
  fi
}

_juvy_schedule_status() {
  print "📋 Schedule Status:"
  print "   Enabled: ${_JUVY_CONFIG[schedule_enabled]}"
  print "   Frequency: ${_JUVY_CONFIG[schedule_frequency]}"
  print "   Time: ${_JUVY_CONFIG[schedule_time]}"
  print "   Method: ${_JUVY_CONFIG[schedule_method]}"
  
  if [[ "${_JUVY_CONFIG[schedule_enabled]}" == "true" ]]; then
    _juvy_launchd_status
  fi
}

_juvy_schedule_set_frequency() {
  local frequency="$1"
  local time="$2"
  
  if ! _juvy_validate_schedule_frequency "$frequency"; then
    return 1
  fi
  
  if [[ -n "$time" ]] && ! _juvy_validate_time_format "$time"; then
    return 1
  fi
  
  print "🕒 Setting schedule frequency to $frequency"
  
  _juvy_update_config "JUVY_SCHEDULE_FREQUENCY" "$frequency"
  
  if [[ -n "$time" ]]; then
    print "   Setting time to $time"
    _juvy_update_config "JUVY_SCHEDULE_TIME" "$time"
  fi
  
  # If scheduling is enabled, update the launchd agent
  if [[ "${_JUVY_CONFIG[schedule_enabled]}" == "true" ]]; then
    if _juvy_install_launchd_agent; then
      print "✅ Schedule updated"
    else
      print "❌ Failed to update schedule"
      return 1
    fi
  else
    print "✅ Schedule settings updated (use 'juvy schedule enable' to activate)"
  fi
}

_juvy_schedule_help() {
  print "juvy schedule - Manage automated backup scheduling"
  print ""
  print "Usage: juvy schedule <command>"
  print ""
  print "Commands:"
  print "  enable              Enable automated backups with current settings"
  print "  enable daily        Enable daily backups at configured time"
  print "  enable daily 14:30  Enable daily backups at 2:30 PM"
  print "  enable weekly       Enable weekly backups (Sundays at configured time)"
  print "  enable hourly       Enable hourly backups"
  print "  disable             Disable automated backups"
  print "  status              Show current schedule status"
  print "  daily [time]        Set frequency to daily with optional time"
  print "  weekly [time]       Set frequency to weekly with optional time"
  print "  hourly              Set frequency to hourly"
  print ""
  print "Examples:"
  print "  juvy schedule enable daily 02:00    # Daily backups at 2 AM"
  print "  juvy schedule enable weekly         # Weekly backups (current time)"
  print "  juvy schedule disable               # Turn off automated backups"
  print "  juvy schedule status                # Check current settings"
}


_juvy_help() {
  print "juvy $JUVY_VERSION - dotfile backup utility"
  print ""
  print "Usage: juvy <command>"
  print ""
  print "Commands:"
  print "  init        Initialize juvy configuration"
  print "  add         Add files/directories to backup list (or edit with \$EDITOR)"
  print "              Files: 'add ~/.zshrc' or 'add /etc/hosts'"
  print "              Directories: 'add ~/.config/nvim/' (with trailing slash)"
  print "              Absolute paths: '/etc/hosts' (may require sudo for backup)"
  print "              Home paths: '~/.zshrc' (recommended for dotfiles)"
  print "  backup      Backup files and directories to configured directory"
  print "  restore     Restore all files from latest backup"
  print "  list        Show all tracked files and directories"
  print "  status      Show changes since last backup"
  print "              'status [file]' shows detailed diff for specific file"
  print "  validate    Validate backup file without running backup"
  print "  git         Run git commands in backup directory"
  print "  remote      Manage git remote for backup synchronization"
  print "              'remote <url>' sets remote and enables auto-sync"
  print "              'remote' shows current remote status"
  print "              'remote off' disables remote synchronization"
  print "              'remote push' manually pushes to remote"
  print "  schedule    Manage automated backup scheduling"
  print "              'schedule enable' enables hourly backups (default)"
  print "              'schedule enable daily 14:30' enables daily backups at 2:30 PM"
  print "              'schedule disable' disables automated backups"
  print "              'schedule status' shows current schedule"
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
