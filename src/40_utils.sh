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
    \~/*)
      # Explicit home-relative: ~/path -> $HOME/path
      resolved_path="${HOME}${entry#\~}"
      ;;
    /*)
      # Absolute path: /etc/hosts -> /etc/hosts
      resolved_path="$entry"
      ;;
    *)
      # Invalid format - not home-relative (~/) or absolute (/)
      echo "Invalid path format: $entry" >&2
      echo "   Use ~/path for home-relative or /path for absolute" >&2
      return 1
      ;;
  esac

  echo "$resolved_path"
}

_juvy_entry_to_backup_path() {
  local entry="$1"
  local source_path backup_path

  source_path="$(_juvy_entry_to_source_path "$entry")"

  # Map to backup using absolute path structure
  backup_path="$_JUVY_BACKUP_DIR$source_path"

  echo "$backup_path"
}

_juvy_entry_to_relative_path() {
  local entry="$1"
  local base_root="$2"
  local resolved_path

  resolved_path="$(_juvy_entry_to_source_path "$entry")"

  if [[ "$base_root" == "$HOME" ]]; then
    if [[ "$resolved_path" == "$HOME/"* ]]; then
      echo "${resolved_path#$HOME/}"
      return 0
    fi
    return 1
  fi

  if [[ "$resolved_path" == "$HOME/"* ]]; then
    return 1
  fi

  if [[ "$resolved_path" == /* ]]; then
    echo "${resolved_path#/}"
    return 0
  fi

  return 1
}

_juvy_add_parent_rules() {
  local dir_path="$1"
  local path_parts=()
  local current_path=""
  local part

  [[ -z "$dir_path" ]] && return 0

  IFS='/' read -ra path_parts <<< "$dir_path"

  for part in "${path_parts[@]}"; do
    [[ -z "$part" ]] && continue
    if [[ -n "$current_path" ]]; then
      current_path="$current_path/$part"
    else
      current_path="$part"
    fi
    echo "+ /$current_path/"
  done
}

_juvy_add_include_rules() {
  local relative_path="$1"
  local is_dir="$2"
  local clean_path="${relative_path%/}"

  if [[ "$is_dir" == "true" ]]; then
    echo "+ /$clean_path/"
    echo "+ /$clean_path/***"
  else
    echo "+ /$relative_path"
  fi
}

_juvy_add_exclude_rules() {
  local relative_path="$1"
  local is_dir="$2"
  local clean_path="${relative_path%/}"

  if [[ "$is_dir" == "true" ]]; then
    printf '%s\n' "- /$clean_path/"
    printf '%s\n' "- /$clean_path/***"
  else
    printf '%s\n' "- /$relative_path"
  fi
}

# Write unique rules to filter file (Bash 3.2 compatible dedup using string)
_juvy_write_unique_rules() {
  local output_file="$1"
  shift
  local seen_rules=""
  local rule

  for rule in "$@"; do
    [[ -z "$rule" ]] && continue
    # Check if rule already seen (using string matching)
    if [[ "$seen_rules" != *"|$rule|"* ]]; then
      printf '%s\n' "$rule" >> "$output_file"
      seen_rules="$seen_rules|$rule|"
    fi
  done
}

# Collects backup entries from $_JUVY_BACKUP_FILE, separating includes and excludes.
# Populates global arrays _JUVY_INCLUDE_PATHS and _JUVY_EXCLUDE_PATTERNS
_juvy_collect_backup_entries() {
  local entry parsed_data entry_type entry_path

  _JUVY_INCLUDE_PATHS=()
  _JUVY_EXCLUDE_PATTERNS=()

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    parsed_data="$(_juvy_parse_backup_entry "$entry")"
    entry_type="$(_juvy_extract_parsed_field "$parsed_data" "type" "include")"
    entry_path="$(_juvy_extract_parsed_field "$parsed_data" "path" "")"

    if [[ "$entry_type" == "include" ]]; then
      _JUVY_INCLUDE_PATHS+=("$entry_path")
    elif [[ "$entry_type" == "exclude" ]]; then
      _JUVY_EXCLUDE_PATTERNS+=("$entry_path")
    fi
  done < "$_JUVY_BACKUP_FILE"
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
_juvy_build_rsync_filter_file() {
  local base_root="$1"
  local include_array_name="$2"
  local exclude_array_name="$3"
  local filter_file="$4"
  local extra_exclude_array_name="${5:-}"

  # Copy arrays using eval (Bash 3.2 compatible)
  # Use safe expansion pattern to handle empty arrays
  local includes=()
  local excludes=()
  local extra_excludes=()
  eval "includes=(\"\${${include_array_name}[@]+\"\${${include_array_name}[@]}\"}\")"
  eval "excludes=(\"\${${exclude_array_name}[@]+\"\${${exclude_array_name}[@]}\"}\")"

  if [[ -n "$extra_exclude_array_name" ]]; then
    eval "extra_excludes=(\"\${${extra_exclude_array_name}[@]+\"\${${extra_exclude_array_name}[@]}\"}\")"
  fi

  local parent_rules=()
  local include_rules=()
  local exclude_rules=()
  local entry relative_path parent_path is_dir clean_path rule

  # Start with root directory rule
  parent_rules=("+ /")

  # Process include patterns
  for entry in ${includes[@]+"${includes[@]}"}; do
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
      while IFS= read -r rule; do
        parent_rules+=("$rule")
      done < <(_juvy_add_parent_rules "$parent_path")
    fi

    while IFS= read -r rule; do
      include_rules+=("$rule")
    done < <(_juvy_add_include_rules "$relative_path" "$is_dir")
  done

  # Process exclude patterns - handle empty arrays safely
  local all_excludes=()
  for entry in ${excludes[@]+"${excludes[@]}"}; do
    all_excludes+=("$entry")
  done
  for entry in ${extra_excludes[@]+"${extra_excludes[@]}"}; do
    all_excludes+=("$entry")
  done

  for entry in ${all_excludes[@]+"${all_excludes[@]}"}; do
    if ! relative_path="$(_juvy_entry_to_relative_path "$entry" "$base_root")"; then
      continue
    fi

    is_dir="false"
    if [[ "$entry" == */ ]]; then
      is_dir="true"
    fi

    while IFS= read -r rule; do
      exclude_rules+=("$rule")
    done < <(_juvy_add_exclude_rules "$relative_path" "$is_dir")
  done

  # Write filter file with correct ordering
  : > "$filter_file"
  _juvy_write_unique_rules "$filter_file" ${parent_rules[@]+"${parent_rules[@]}"}   # 1. Parents
  _juvy_write_unique_rules "$filter_file" ${exclude_rules[@]+"${exclude_rules[@]}"} # 2. Excludes
  _juvy_write_unique_rules "$filter_file" ${include_rules[@]+"${include_rules[@]}"} # 3. Includes
  printf '%s\n' "- *" >> "$filter_file"                                              # 4. Exclude rest
}


_juvy_process_backup_entries() {
  local home_paths=()
  local system_paths=()
  local entry source_path
  local home_count=0 system_count=0

  _juvy_info "Processing backup entries..."

  _juvy_collect_backup_entries

  _juvy_info "Processing ${#_JUVY_INCLUDE_PATHS[@]} paths"

  for entry in ${_JUVY_INCLUDE_PATHS[@]+"${_JUVY_INCLUDE_PATHS[@]}"}; do
    source_path="$(_juvy_entry_to_source_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ ! -d "$source_path" ]]; then
        continue
      fi
    else
      if [[ ! -f "$source_path" ]]; then
        continue
      fi
    fi

    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$entry")
    else
      system_paths+=("$entry")
    fi
  done

  if [[ ${#home_paths[@]} -gt 0 ]]; then
    _juvy_info "Backing up ${#home_paths[@]} home paths..."

    local temp_filter_file
    temp_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "$HOME" home_paths _JUVY_EXCLUDE_PATTERNS "$temp_filter_file"; then
      _juvy_error "Failed to build filter file for home paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! mkdir -p "$_JUVY_BACKUP_DIR$HOME/" > /dev/null 2>&1; then
      _juvy_error "Failed to create backup directory for home paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! _juvy_rsync_backup_with_filters "$HOME/" "$_JUVY_BACKUP_DIR$HOME/" "$temp_filter_file"; then
      _juvy_error "Failed to backup home paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    rm -f "$temp_filter_file"
    home_count=${#home_paths[@]}
  fi

  if [[ ${#system_paths[@]} -gt 0 ]]; then
    _juvy_info "Backing up ${#system_paths[@]} system paths..."

    local temp_filter_file
    temp_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "/" system_paths _JUVY_EXCLUDE_PATTERNS "$temp_filter_file"; then
      _juvy_error "Failed to build filter file for system paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! mkdir -p "$_JUVY_BACKUP_DIR" > /dev/null 2>&1; then
      _juvy_error "Failed to create backup directory"
      rm -f "$temp_filter_file"
      return 1
    fi

    if ! _juvy_rsync_backup_with_filters "/" "$_JUVY_BACKUP_DIR" "$temp_filter_file"; then
      _juvy_error "Failed to backup system paths"
      rm -f "$temp_filter_file"
      return 1
    fi

    rm -f "$temp_filter_file"
    system_count=${#system_paths[@]}
  fi

  _juvy_info "Processed $home_count home and $system_count system paths"
  return 0
}

# Displays filter file contents for debugging rsync issues
_juvy_show_filter_debug() {
  local filter_file="$1"
  local line

  if [[ "${JUVY_DEBUG:-}" != "1" ]]; then
    return 0
  fi

  _juvy_warn "Filter file contents (for debugging):"
  _juvy_warn "   ----------------------------------------"
  while IFS= read -r line; do
    _juvy_warn "   $line"
  done < "$filter_file"
  _juvy_warn "   ----------------------------------------"
}

_juvy_rsync_backup_with_filters() {
  local source="$1"
  local dest="$2"
  local filter_file="$3"
  local rsync_args=(-a --delete --delete-excluded --filter="merge $filter_file")

  if [[ "${JUVY_VERBOSE:-}" == "1" ]]; then
    rsync_args=(-av --delete --delete-excluded --filter="merge $filter_file")
  fi

  if ! _juvy_rsync_simple "${rsync_args[@]}" "$source" "$dest"; then
    _juvy_show_filter_debug "$filter_file"
    return 1
  fi
}

_juvy_rsync_restore_with_filters() {
  local source="$1"
  local dest="$2"
  local filter_file="$3"
  local dry_run="${4:-false}"
  local rsync_args=()

  # Build rsync arguments
  # Use --ignore-times to force copy even when backup files are older than current files
  # (This happens when user modifies a file after backup and wants to restore the original)
  rsync_args=(-a --ignore-times --ignore-errors --filter="merge $filter_file")
  if [[ "${JUVY_VERBOSE:-}" == "1" ]]; then
    rsync_args=(-av --ignore-times --ignore-errors --filter="merge $filter_file")
  fi

  # Add dry-run flag if requested
  if [[ "$dry_run" == "true" ]]; then
    rsync_args+=(--dry-run --itemize-changes)
  fi

  # Use rsync to copy tracked files without removing existing files
  # Use --ignore-errors to continue despite permission issues on system directories
  if ! _juvy_rsync_simple --allow-partial "${rsync_args[@]}" "$source/" "$dest"; then
    _juvy_show_filter_debug "$filter_file"
    return 1
  fi
}


_juvy_timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

_juvy_log() {
  local message="$1"
  local timestamp

  timestamp="$(_juvy_timestamp)"

  # Ensure log directory exists
  if [[ ! -d "$_JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$_JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi

  echo "[$timestamp] $message" >> "$_JUVY_LOG_FILE"
}

_juvy_log_error() {
  _juvy_log "ERROR: $1"
}

_juvy_acquire_lock() {
  local lock_name="$1"
  local lock_dir="$_JUVY_CONFIG_DIR/locks/${lock_name}.lock"

  if mkdir -p "$_JUVY_CONFIG_DIR/locks" >/dev/null 2>&1 && mkdir "$lock_dir" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

_juvy_release_lock() {
  local lock_name="$1"
  local lock_dir="$_JUVY_CONFIG_DIR/locks/${lock_name}.lock"
  rm -rf "$lock_dir" >/dev/null 2>&1
}


# User-facing output utilities
# These respect JUVY_VERBOSE for progress messages

_juvy_info() {
  # Progress/status messages - only shown when verbose
  if [[ "${JUVY_VERBOSE:-}" == "1" ]]; then
    echo "$@"
  fi
}

_juvy_result() {
  # Final results - always shown
  echo "$@"
}

_juvy_error() {
  # Errors - always shown to stderr
  echo "$@" >&2
}

_juvy_warn() {
  # Warnings - always shown to stderr
  echo "Warning: $@" >&2
}


_juvy_git() {
  if [[ -d "$_JUVY_BACKUP_DIR" ]]; then
    git -C "$_JUVY_BACKUP_DIR" "$@"
  fi
}

_juvy_update() {
  local temp_script="/tmp/juvy_update.sh"
  local juvy_script="$HOME/.juvy/juvy"
  local repo_url="https://raw.githubusercontent.com/danecando/juvy/main/juvy.sh"
  local latest_version update

  echo "Checking for updates..."

  if ! curl -sSL "$repo_url" -o "$temp_script"; then
    echo "Failed to download latest version" >&2
    return 1
  fi

  latest_version=$(grep '_JUVY_VERSION="[0-9]' "$temp_script" | head -1 | cut -d'"' -f2)

  if [[ -z "$latest_version" ]]; then
    echo "Failed to extract version from downloaded script" >&2
    rm -f "$temp_script"
    return 1
  fi

  if [[ "$latest_version" == "$_JUVY_VERSION" ]]; then
    echo "juvy is already up to date (v$_JUVY_VERSION)"
    rm -f "$temp_script"
    return 0
  fi

  echo "Update available: v$_JUVY_VERSION -> v$latest_version"
  echo -n "Do you want to update? [Y/n] "
  read -r update

  if [[ "$update" == "n" ]]; then
    echo "Update cancelled"
    rm -f "$temp_script"
    return 0
  fi

  if mv "$temp_script" "$juvy_script" && chmod +x "$juvy_script"; then
    echo "Updated juvy to v$latest_version"
  else
    echo "Failed to update juvy" >&2
    rm -f "$temp_script"
    return 1
  fi
}

_juvy_detect_shell_name() {
  local current_shell="${SHELL##*/}"
  if [[ -n "$current_shell" ]]; then
    echo "$current_shell"
  else
    echo "unknown"
  fi
}

_juvy_detect_rc_file() {
  local shell_name="${1:-$(_juvy_detect_shell_name)}"

  case "$shell_name" in
    zsh)
      echo "$HOME/.zshrc"
      ;;
    bash)
      echo "$HOME/.bashrc"
      ;;
    *)
      echo "$HOME/.profile"
      ;;
  esac
}

_juvy_remove_managed_block_from_file() {
  local file_path="$1"
  local start_marker="$2"
  local end_marker="$3"
  local temp_file

  [[ -f "$file_path" ]] || return 0

  temp_file="$file_path.tmp"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block=1; removed=1; next }
    in_block && $0 == end { in_block=0; next }
    !in_block { print }
  ' "$file_path" > "$temp_file"

  if ! cmp -s "$file_path" "$temp_file" 2>/dev/null; then
    mv "$temp_file" "$file_path"
    return 0
  fi

  rm -f "$temp_file"
  return 1
}

_juvy_write_shell_integration_block() {
  local rc_file="$1"

  cat >> "$rc_file" << EOF
$_JUVY_SHELL_INTEGRATION_START
export PATH="\$HOME/.juvy:\$PATH"
if [[ "\${JUVY_AUTO_BACKUP:-1}" != "0" ]] && [[ -o interactive ]] && command -v juvy >/dev/null 2>&1; then
  if [[ -z "\${JUVY_AUTO_BACKUP_STARTED:-}" ]]; then
    export JUVY_AUTO_BACKUP_STARTED=1
    _juvy_auto_backup_interval="\${JUVY_AUTO_BACKUP_INTERVAL:-300}"
    _juvy_auto_backup_stamp="\${XDG_STATE_HOME:-\$HOME/.local/state}/juvy/auto-backup.last"
    if [[ "\$_juvy_auto_backup_interval" =~ ^[0-9]+$ ]] && (( _juvy_auto_backup_interval > 0 )); then
      _juvy_auto_backup_now="\$(date +%s 2>/dev/null || echo 0)"
      _juvy_auto_backup_prev=0
      if [[ -f "\$_juvy_auto_backup_stamp" ]]; then
        _juvy_auto_backup_prev="\$(cat "\$_juvy_auto_backup_stamp" 2>/dev/null || echo 0)"
      fi
      if (( _juvy_auto_backup_now - _juvy_auto_backup_prev >= _juvy_auto_backup_interval )); then
        mkdir -p "\$(dirname "\$_juvy_auto_backup_stamp")" >/dev/null 2>&1
        echo "\$_juvy_auto_backup_now" > "\$_juvy_auto_backup_stamp" 2>/dev/null
        juvy backup >/dev/null 2>&1 &
      fi
    else
      juvy backup >/dev/null 2>&1 &
    fi
    unset _juvy_auto_backup_interval _juvy_auto_backup_stamp _juvy_auto_backup_now _juvy_auto_backup_prev
  fi
fi
$_JUVY_SHELL_INTEGRATION_END
EOF
}

_juvy_ensure_bash_profile_bridge() {
  local bash_profile="$HOME/.bash_profile"
  local bridge_start="# >>> juvy bashrc bridge >>>"
  local bridge_end="# <<< juvy bashrc bridge <<<"

  touch "$bash_profile" 2>/dev/null || return 1

  _juvy_remove_managed_block_from_file "$bash_profile" "$bridge_start" "$bridge_end" >/dev/null 2>&1 || true

  if [[ -s "$bash_profile" ]]; then
    printf '\n' >> "$bash_profile"
  fi

  cat >> "$bash_profile" << 'EOF'
# >>> juvy bashrc bridge >>>
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
# <<< juvy bashrc bridge <<<
EOF

  return 0
}

_juvy_remove_bash_profile_bridge() {
  local bash_profile="$HOME/.bash_profile"
  local bridge_start="# >>> juvy bashrc bridge >>>"
  local bridge_end="# <<< juvy bashrc bridge <<<"

  _juvy_remove_managed_block_from_file "$bash_profile" "$bridge_start" "$bridge_end" >/dev/null 2>&1 || true
}

_juvy_upsert_shell_integration() {
  local shell_name="${1:-$(_juvy_detect_shell_name)}"
  local rc_file

  case "$shell_name" in
    zsh|bash)
      rc_file="$(_juvy_detect_rc_file "$shell_name")"
      ;;
    *)
      return 1
      ;;
  esac

  touch "$rc_file" 2>/dev/null || return 1

  _juvy_remove_managed_block_from_file "$rc_file" "$_JUVY_SHELL_INTEGRATION_START" "$_JUVY_SHELL_INTEGRATION_END" >/dev/null 2>&1 || true

  if [[ -s "$rc_file" ]]; then
    printf '\n' >> "$rc_file"
  fi

  _juvy_write_shell_integration_block "$rc_file"

  if [[ "$shell_name" == "bash" ]]; then
    _juvy_ensure_bash_profile_bridge || return 1
  fi

  return 0
}

_juvy_nuke() {
  local confirm

  echo "WARNING: This will COMPLETELY DESTROY all juvy data including:"
  echo "  - Configuration directory: $_JUVY_CONFIG_DIR"
  echo "  - Backup directory: $_JUVY_BACKUP_DIR"
  echo "  - Installation directory: $HOME/.juvy"
  echo "  - juvy entry from shell rc file"
  echo ""
  echo "ALL YOUR BACKUPS WILL BE DELETED!"
  echo "This action cannot be undone!"
  echo -n "Are you absolutely sure? [y/N] "
  read -r confirm

  if [[ "$confirm" != "y" ]]; then
    echo "Nuke cancelled"
    return 0
  fi

  # Call rm function first (removes config, installation, .zshrc)
  _juvy_uninstall_internal

  if [[ -d "$_JUVY_BACKUP_DIR" ]]; then
    rm -rf "$_JUVY_BACKUP_DIR"
    echo "Nuked backup directory"
  fi

  echo ""
  echo "juvy has been completely nuked from your system"
  echo "Restart your shell to complete removal"
}

_juvy_uninstall_internal() {
  if [[ -d "$_JUVY_CONFIG_DIR" ]]; then
    rm -rf "$_JUVY_CONFIG_DIR"
    echo "Removed configuration directory"
  fi

  if [[ -d "$HOME/.juvy" ]]; then
    rm -rf "$HOME/.juvy"
    echo "Removed installation directory"
  fi

  # Remove from shell rc files
  local rc_file
  for rc_file in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if _juvy_remove_managed_block_from_file "$rc_file" "$_JUVY_SHELL_INTEGRATION_START" "$_JUVY_SHELL_INTEGRATION_END"; then
      echo "Removed juvy from $rc_file"
    fi
  done
  _juvy_remove_bash_profile_bridge
}

_juvy_is_sensitive_file() {
  local file="$1"
  local filename="${file##*/}"  # basename
  local sensitive_patterns=(
    "*id_rsa*" "*id_ed25519*" "*id_ecdsa*"  # SSH keys
    "*.pem" "*.key" "*.cert"                 # Certificates
    "*credentials*" "*token*" "*secret*"     # Credentials
    "*.env" ".env.*"                         # Environment files
    "*auth*" "*passwd*"                      # Auth files
  )

  local pattern
  for pattern in "${sensitive_patterns[@]}"; do
    # Use case statement for pattern matching (Bash 3.2 compatible)
    case "$filename" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

_juvy_show_security_warning() {
  local file="$1"
  local choice

  echo "Security Warning: This appears to be a sensitive file"
  echo "   File: $file"
  echo ""
  echo "Backing up to cloud storage may expose sensitive data."
  echo "Options:"
  echo "  1) Cancel (recommended)"
  echo "  2) Continue anyway"
  echo ""
  echo -n "Choice [1-2]: "
  read -r choice

  case "$choice" in
    2)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_juvy_validate_path() {
  local input_path="$1"
  local full_path

  if [[ "$input_path" == "~/"* ]]; then
    full_path="${input_path/#\~/$HOME}"
  elif [[ "$input_path" = /* ]]; then
    full_path="$input_path"
  else
    # Path relative to current working directory.
    full_path="$PWD/${input_path#./}"
  fi

  if [[ ! -e "$full_path" ]]; then
    echo "Path does not exist: $input_path" >&2
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
    # Path is relative to current directory or in backup entry format
    if [[ "$input_path" = ~* ]]; then
      full_path="${input_path/#\~/$HOME}"
    else
      full_path="$PWD/${input_path#./}"
    fi
  fi

  if [[ ! -d "$full_path" ]]; then
    return 1
  fi

  # Calculate size in bytes using du (try -sb first, fallback to -sk for macOS)
  size_bytes=$(du -sb "$full_path" 2>/dev/null | cut -f1)
  if [[ -z "$size_bytes" ]]; then
    # macOS doesn't support -sb, use -sk and convert to bytes
    local size_kb
    size_kb=$(du -sk "$full_path" 2>/dev/null | cut -f1)
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
  file_count=$(find "$full_path" -type f 2>/dev/null | wc -l)
  [[ -z "$file_count" ]] && file_count=0
  file_count="${file_count#"${file_count%%[![:space:]]*}"}"

  # Return colon-separated string (no globals)
  echo "$size_bytes:$size_human:$file_count"
}

# Parse directory info string returned by _juvy_calculate_directory_info.
# Usage: _juvy_parse_dir_info "$dir_info" bytes|human|count
_juvy_parse_dir_info() {
  local info="$1"
  local field="$2"

  case "$field" in
    bytes)
      echo "${info%%:*}"
      ;;
    human)
      local rest="${info#*:}"
      echo "${rest%%:*}"
      ;;
    count)
      echo "${info##*:}"
      ;;
  esac
}

_juvy_prompt_large_directory() {
  local path_arg="$1"
  local size_human="$2"
  local file_count="$3"
  local force="$4"
  local response

  if [[ "$force" == "true" ]]; then
    return 0
  fi

  echo "This directory contains:"
  echo "   Files: $file_count"
  echo "   Size: $size_human"
  echo ""
  echo "Large backups may be slow and consume significant storage."
  echo -n "Continue? [y/N] "
  read -r response

  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    return 1
  fi

  return 0
}

_juvy_add() {
  local paths=()
  local p
  local failed_count=0

  _juvy_validate_backup_file_exists || return 1

  # Parse path arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -*)
        echo "Unknown flag: $1" >&2
        echo "Usage: juvy add [path...]" >&2
        return 1
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if command -v "$editor" >/dev/null 2>&1; then
      "$editor" "$_JUVY_BACKUP_FILE"
      echo "Consider running 'juvy doctor' to check your backup file"
    else
      echo "Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
      return 1
    fi
  else
    # Arguments provided, validate and append to file
    for p in "${paths[@]}"; do
      # Validate path exists
      if ! _juvy_validate_path "$p"; then
        (( ++failed_count ))
        continue
      fi

      # Convert to absolute path if relative
      local full_path
      if [[ "$p" == "~/"* ]]; then
        full_path="${p/#\~/$HOME}"
      elif [[ "$p" == /* ]]; then
        full_path="$p"
      else
        full_path="$PWD/${p#./}"
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
        echo "Invalid path format: $p. Accepted formats: absolute paths (e.g., /path/to/file), home-relative paths (e.g., ~/file), or paths relative to the current directory." >&2
        continue
      fi

      # Check if path exists and determine type
      if [[ -d "$full_path" ]]; then
        # Directory - ensure it ends with /
        if [[ "$backup_entry" != */ ]]; then
          backup_entry="$backup_entry/"
        fi

        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
          echo "Path already in backup list: $backup_entry"
          continue
        fi

        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            echo "Skipped adding sensitive directory: $p"
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
              echo "Skipped adding large directory: $p"
              continue
            fi
          fi
        fi

        echo "$backup_entry" >> "$_JUVY_BACKUP_FILE"
        echo "Added directory '$backup_entry' to backup list"

      elif [[ -f "$full_path" ]]; then
        # File - ensure it doesn't end with /
        backup_entry="${backup_entry%/}"

        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
          echo "Path already in backup list: $backup_entry"
          continue
        fi

        # Check for sensitive files
        if _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            echo "Skipped adding sensitive file: $p"
            continue
          fi
        fi

        echo "$backup_entry" >> "$_JUVY_BACKUP_FILE"
        echo "Added file '$backup_entry' to backup list"

      else
        echo "Path not found: $p" >&2
        (( ++failed_count ))
        continue
      fi
    done

    if (( failed_count > 0 )); then
      return 1
    fi
  fi
}

_juvy_remove() {
  local paths=()
  local p
  local delete_from_backup=false

  _juvy_validate_backup_file_exists || return 1

  # Parse path arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --delete)
        delete_from_backup=true
        shift
        ;;
      -*)
        echo "Unknown flag: $1" >&2
        echo "Usage: juvy remove [--delete] [path...]" >&2
        return 1
        ;;
      *)
        paths+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if command -v "$editor" >/dev/null 2>&1; then
      "$editor" "$_JUVY_BACKUP_FILE"
      echo "Consider running 'juvy doctor' to check your backup file"
    else
      echo "Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
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

      if grep -Fxq "$backup_entry" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
        entry_to_remove="$backup_entry"
        found=true
      elif grep -Fxq "${backup_entry}/" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
        entry_to_remove="${backup_entry}/"
        found=true
      elif grep -Fxq "${backup_entry%/}" "$_JUVY_BACKUP_FILE" 2>/dev/null; then
        entry_to_remove="${backup_entry%/}"
        found=true
      fi

      if [[ "$found" == "true" ]]; then
        # Remove the entry from backup file
        grep -Fxv "$entry_to_remove" "$_JUVY_BACKUP_FILE" > "$_JUVY_BACKUP_FILE.tmp"
        mv "$_JUVY_BACKUP_FILE.tmp" "$_JUVY_BACKUP_FILE"
        echo "Removed '$entry_to_remove' from backup list"

        # Check if file exists in backup directory and offer to delete
        local backup_path
        backup_path="$(_juvy_entry_to_backup_path "$entry_to_remove")"

        if [[ -e "$backup_path" ]]; then
          local should_delete=false

          if [[ "$delete_from_backup" == "true" ]]; then
            should_delete=true
          elif [[ -t 0 ]]; then
            # Only prompt if running interactively
            echo -n "Also delete from backup directory? [y/N] "
            local delete_confirm
            read -r delete_confirm
            if [[ "$delete_confirm" == [yY]* ]]; then
              should_delete=true
            fi
          fi

          if [[ "$should_delete" == "true" ]]; then
            rm -rf "$backup_path"
            echo "Deleted '$entry_to_remove' from backup"

            # Commit the deletion if there are changes
            if [[ -n $(_juvy_git status --porcelain) ]]; then
              _juvy_git add -A
              _juvy_git commit -m "Remove: $entry_to_remove" >/dev/null 2>&1
            fi
          fi
        fi
      else
        echo "Path not in backup list: $p"
      fi
    done
  fi
}
