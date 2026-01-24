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
