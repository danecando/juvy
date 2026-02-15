## BACKUP FUNCTIONS ###########################################################

# Perform backup of all configured files and commit changes

_juvy_backup() {
  local backup_status=0

  if ! _juvy_acquire_lock "backup"; then
    _juvy_warn "Backup already in progress; skipping this run"
    return 0
  fi

  _juvy_backup_internal "$@" || backup_status=$?
  _juvy_release_lock "backup"
  return "$backup_status"
}

_juvy_backup_internal() {
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
