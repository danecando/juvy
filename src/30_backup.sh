## BACKUP FUNCTIONS ###########################################################

# Perform backup of all configured files and commit changes

_juvy_backup() {
  _juvy_validate_backup_dir_configured || return 1
  _juvy_validate_backup_file_exists || return 1

  echo "Starting backup process..."

  # Validate backup file before starting rsync
  _juvy_validate_backup_file

  # Process backup entries with support for directories and files
  if ! _juvy_process_backup_entries; then
    echo "Backup failed" >&2
    _juvy_log "BACKUP FAILED: rsync error"
    return 1
  fi

  echo "Files synced successfully"


  if [[ -n $(_juvy_git status --porcelain) ]]; then
    _juvy_git add -A
    if ! _juvy_git commit -m "Backup: $(_juvy_timestamp)"; then
      echo "Git commit failed, but files were synced" >&2
      _juvy_log "BACKUP FAILED: git commit error"
      return 1
    fi
    echo "Changes committed to git"

    # Auto-push if remote is configured and enabled
    local push_status=""
    if [[ "$_JUVY_REMOTE_PUSH" == "true" && -n "$_JUVY_REMOTE_URL" ]]; then
      if _juvy_remote_push_auto; then
        echo "Changes pushed to remote"
        push_status=" (pushed to remote)"
      else
        echo "Failed to push to remote (run 'juvy remote push' manually)" >&2
        push_status=" (push failed)"
      fi
    fi

    _juvy_log "BACKUP OK: changes committed${push_status}"
  else
    echo "No changes to commit"
    _juvy_log "BACKUP OK: no changes"
  fi

  echo "Backup completed successfully"
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
        echo "Unknown option: $1" >&2
        echo "Usage: juvy doctor [--fix]" >&2
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done

  echo "Running juvy doctor..."
  echo ""

  if [[ "$fix_mode" == "true" ]]; then
    local fixes=0
    local juvy_script="$HOME/.juvy/juvy.sh"

    echo "Applying quick fixes..."

    if [[ ! -d "$_JUVY_CONFIG_DIR" ]]; then
      if mkdir -p "$_JUVY_CONFIG_DIR" >/dev/null 2>&1; then
        echo "Created config directory"
        (( fixes++ ))
      else
        echo "Failed to create config directory: $_JUVY_CONFIG_DIR" >&2
      fi
    fi

    if [[ ! -f "$_JUVY_CONFIG_FILE" ]]; then
      if touch "$_JUVY_CONFIG_FILE" >/dev/null 2>&1; then
        echo "Created config file"
        (( fixes++ ))
      else
        echo "Failed to create config file: $_JUVY_CONFIG_FILE" >&2
      fi
    fi

    if [[ -n "$_JUVY_CONFIG_DIR" && -f "$_JUVY_CONFIG_FILE" ]]; then
      if ! grep -q "^JUVY_BACKUP_DIR=" "$_JUVY_CONFIG_FILE" 2>/dev/null; then
        _juvy_update_config "JUVY_BACKUP_DIR" "$backup_dir"
        echo "Wrote JUVY_BACKUP_DIR to config"
        (( fixes++ ))
      fi
    fi

    if [[ ! -f "$_JUVY_BACKUP_FILE" ]]; then
      if touch "$_JUVY_BACKUP_FILE" >/dev/null 2>&1; then
        echo "Created backup file"
        (( fixes++ ))
      else
        echo "Failed to create backup file: $_JUVY_BACKUP_FILE" >&2
      fi
    fi

    if [[ -n "$backup_dir" && ! -e "$backup_dir" ]]; then
      if mkdir -p "$backup_dir" >/dev/null 2>&1; then
        echo "Created backup directory"
        (( fixes++ ))
      else
        echo "Failed to create backup directory: $backup_dir" >&2
      fi
    fi

    if [[ -n "$backup_dir" && -d "$backup_dir" && ! -d "$backup_dir/.git" ]]; then
      if git init -b main "$backup_dir" >/dev/null 2>&1; then
        echo "Initialized backup git repository"
        (( fixes++ ))
      else
        echo "Failed to initialize backup git repository: $backup_dir" >&2
      fi
    fi

    if [[ -f "$juvy_script" ]]; then
      # Detect shell rc file
      local rc_file
      rc_file="$(_juvy_detect_rc_file)"

      if [[ ! -f "$rc_file" ]]; then
        if touch "$rc_file" >/dev/null 2>&1; then
          echo "Created $rc_file"
          (( fixes++ ))
        fi
      fi

      if [[ -f "$rc_file" ]] && ! grep -q "source.*\\.juvy/juvy\\.sh" "$rc_file"; then
        {
          echo ""
          echo "# juvy dotfile backup tool"
          echo "source $juvy_script"
        } >> "$rc_file"
        echo "Added juvy source to $rc_file"
        (( fixes++ ))
      fi
    fi

    if (( fixes == 0 )); then
      echo "No quick fixes applied"
    fi

    echo ""
  fi

  # Prerequisites - check for bash or zsh
  local current_shell="${SHELL##*/}"
  if [[ "$current_shell" != "bash" && "$current_shell" != "zsh" ]]; then
    echo "Shell is not bash or zsh: $SHELL" >&2
    (( issues++ ))
  else
    echo "Shell: $current_shell"
  fi

  if command -v rsync >/dev/null 2>&1; then
    echo "rsync available"
  else
    echo "Missing dependency: rsync" >&2
    (( issues++ ))
  fi

  if command -v git >/dev/null 2>&1; then
    echo "git available"
  else
    echo "Missing dependency: git" >&2
    (( issues++ ))
  fi

  echo ""

  # Config directory and file
  if [[ -d "$_JUVY_CONFIG_DIR" ]]; then
    if [[ -w "$_JUVY_CONFIG_DIR" ]]; then
      echo "Config directory: $_JUVY_CONFIG_DIR"
    else
      echo "Config directory not writable: $_JUVY_CONFIG_DIR" >&2
      (( issues++ ))
    fi
  else
    echo "Config directory missing: $_JUVY_CONFIG_DIR" >&2
    (( issues++ ))
  fi

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    if _juvy_validate_config_file; then
      echo "Config file parsed"
    else
      (( issues++ ))
    fi
  else
    echo "Config file missing: $_JUVY_CONFIG_FILE" >&2
    (( issues++ ))
  fi

  echo ""

  # Backup file
  if [[ -f "$_JUVY_BACKUP_FILE" ]]; then
    if _juvy_validate_backup_file; then
      echo "Backup file parsed"
    else
      (( issues++ ))
    fi
  else
    echo "Backup file missing: $_JUVY_BACKUP_FILE" >&2
    (( issues++ ))
  fi

  echo ""

  # Backup directory and git repository
  if [[ -z "$backup_dir" ]]; then
    echo "Backup directory not configured (JUVY_BACKUP_DIR missing)" >&2
    (( issues++ ))
  elif [[ -e "$backup_dir" && ! -d "$backup_dir" ]]; then
    echo "Backup path is not a directory: $backup_dir" >&2
    (( issues++ ))
  elif [[ ! -d "$backup_dir" ]]; then
    echo "Backup directory missing: $backup_dir" >&2
    (( issues++ ))
  else
    if [[ -w "$backup_dir" ]]; then
      echo "Backup directory: $backup_dir"
    else
      echo "Backup directory not writable: $backup_dir" >&2
      (( issues++ ))
    fi

    if _juvy_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "Backup git repository found"
    else
      echo "Backup directory is not a git repository (run 'juvy init')" >&2
      (( issues++ ))
    fi
  fi

  echo ""

  # Remote configuration checks (optional)
  if [[ -n "$remote_url" ]]; then
    if [[ -d "$backup_dir/.git" ]]; then
      if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
        local actual_url
        actual_url="$(_juvy_git remote get-url "$remote_name" 2>/dev/null)"
        if [[ -n "$actual_url" && "$actual_url" != "$remote_url" ]]; then
          echo "Remote URL mismatch: config=$remote_url git=$actual_url" >&2
          (( warnings++ ))
        else
          echo "Remote '$remote_name' configured"
        fi

        if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
          echo "Remote reachable"
        else
          echo "Remote not reachable (check network/auth)" >&2
          (( warnings++ ))
        fi
      else
        echo "Remote '$remote_name' not found in backup repo" >&2
        (( issues++ ))
      fi
    else
      echo "Cannot check remote: backup repo not initialized" >&2
      (( issues++ ))
    fi
  else
    echo "No remote configured"
  fi

  echo ""

  # Shell integration
  local rc_file
  rc_file="$(_juvy_detect_rc_file)"
  if [[ -f "$rc_file" ]] && grep -q "source.*\\.juvy/juvy\\.sh" "$rc_file"; then
    echo "$rc_file loads juvy"
  else
    echo "$rc_file does not source juvy (run install.sh or add source line)" >&2
    (( warnings++ ))
  fi

  echo ""

  if (( issues == 0 && warnings == 0 )); then
    echo "Doctor found no issues"
    return 0
  fi

  if (( issues > 0 )); then
    echo "Doctor found $issues issue(s) and $warnings warning(s)" >&2
    return 1
  fi

  echo "Doctor found $warnings warning(s)"
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

