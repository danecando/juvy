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

_juvy_validate() {
  local config_valid=true
  local backup_valid=true
  
  print "🔍 Validating juvy configuration..."
  
  # Validate config file
  if [[ -f "${_JUVY_CONFIG[config_file]}" ]]; then
    if ! _juvy_validate_config_file; then
      config_valid=false
    fi
  else
    print "⚠️  No config file found at ${_JUVY_CONFIG[config_file]}"
    config_valid=false
  fi
  
  # Validate backup file
  if [[ -f "${_JUVY_CONFIG[backup_file]}" ]]; then
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

