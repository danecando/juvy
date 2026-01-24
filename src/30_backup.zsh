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
