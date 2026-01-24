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
