## CONFIGURATION FUNCTIONS ###################################################


_juvy_load_config() {
  local line key value

  _JUVY_BACKUP_DIR="$(_juvy_default_backup_dir)"
  _JUVY_REMOTE_URL=""
  _JUVY_REMOTE_PUSH=""
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
        JUVY_REMOTE_PUSH)
          _JUVY_REMOTE_PUSH="$value"
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
    echo "Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  return 0
}

_juvy_validate_backup_dir_exists() {
  if [[ ! -d "$_JUVY_BACKUP_DIR" ]]; then
    echo "Backup directory not found: $_JUVY_BACKUP_DIR" >&2
    echo "   Run 'juvy init' to set up backup directory" >&2
    return 1
  fi
  return 0
}

_juvy_validate_backup_dir_configured() {
  if [[ ! -d "$_JUVY_BACKUP_DIR" ]]; then
    printf "juvy: Set JUVY_BACKUP_DIR value in %s\n" "$_JUVY_CONFIG_FILE" >&2
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
  local rsync_output
  local rsync_exit_code

  rsync_output=$(rsync "$@" 2>&1)
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
    1)
      echo "rsync syntax or usage error" >&2
      ;;
    2)
      echo "rsync protocol incompatibility" >&2
      ;;
    11)
      echo "rsync file I/O error" >&2
      ;;
    12)
      echo "rsync protocol data stream error" >&2
      ;;
    23)
      echo "rsync partial transfer: some files could not be copied" >&2
      ;;
    24)
      echo "rsync source files vanished" >&2
      ;;
    *)
      echo "rsync failed with error code $rsync_exit_code" >&2
      ;;
  esac

  echo "See $_JUVY_LOG_FILE for details" >&2
  _juvy_log_error "rsync failed (exit code $rsync_exit_code): $rsync_output"
  return $rsync_exit_code
}

