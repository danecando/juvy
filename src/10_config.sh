## CONFIGURATION FUNCTIONS ###################################################


_juvy_load_config() {
  local line key value

  _JUVY_BACKUP_DIR="$(_juvy_default_backup_dir)"
  _JUVY_REMOTE_URL=""
  _JUVY_REMOTE_AUTO_SYNC=""
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
        JUVY_REMOTE_AUTO_SYNC)
          _JUVY_REMOTE_AUTO_SYNC="$value"
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
  local allow_partial=false
  local rsync_output
  local rsync_exit_code

  if [[ "${1:-}" == "--allow-partial" ]]; then
    allow_partial=true
    shift
  fi

  rsync_output=$(rsync "$@" 2>&1)
  rsync_exit_code=$?

  if [[ $rsync_exit_code -eq 0 ]]; then
    if [[ "${JUVY_VERBOSE:-}" == "1" && -n "$rsync_output" ]]; then
      printf "%s\n" "$rsync_output"
    fi
    return 0
  fi

  # For restore operations, allow common permission-related partial transfers.
  if [[ $rsync_exit_code -eq 23 && "$allow_partial" == "true" ]]; then
    if [[ "$rsync_output" == *"Permission denied"* || "$rsync_output" == *"Operation not permitted"* ]]; then
      _juvy_warn "rsync completed with permission-related partial transfer"
      if [[ "${JUVY_VERBOSE:-}" == "1" && -n "$rsync_output" ]]; then
        printf "%s\n" "$rsync_output"
      fi
      return 0
    fi
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
