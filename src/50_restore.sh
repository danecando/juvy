## RESTORE FUNCTIONS ##########################################################
# Restore all files from the latest backup

_juvy_restore() {
  local dry_run="false"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n)
        dry_run="true"
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        echo "Usage: juvy restore [--dry-run]" >&2
        return 1
        ;;
      *)
        shift
        ;;
    esac
  done

  _juvy_validate_backup_dir_exists || return 1
  _juvy_validate_backup_file_exists || return 1

  local file_count dir_count total_size last_backup

  if ! _juvy_show_restore_preview; then
    echo "No files found to restore" >&2
    return 1
  fi

  # In dry-run mode, show what would be restored and exit
  if [[ "$dry_run" == "true" ]]; then
    echo ""
    echo "Dry-run mode: showing what would be restored..."
    echo ""
    _juvy_perform_restore "$dry_run"
    echo ""
    echo "No files were modified (dry-run mode)"
    return 0
  fi

  echo ""
  echo "Current files will be backed up to ~/.config/juvy/safety-backup/"
  echo ""
  echo -n "Proceed with restore? [Y/n] "
  local confirm
  read -r confirm

  if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    echo "Restore cancelled"
    return 0
  fi

  echo ""
  echo "Creating safety backup..."
  local safety_backup_path
  if ! safety_backup_path="$(_juvy_create_safety_backup)"; then
    echo "Failed to create safety backup" >&2
    return 1
  fi

  echo "Restoring files..."
  if ! _juvy_perform_restore "$dry_run"; then
    echo "Restore failed" >&2
    return 1
  fi

  echo "Setting permissions..."
  echo "Restore complete!"
  echo ""
  echo "To undo: juvy restore \"$safety_backup_path\""
}

_juvy_show_restore_preview() {
  local entry file_count=0 dir_count=0 total_files=0
  local backup_path source_path file_size last_backup

  last_backup="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  if [[ -z "$last_backup" ]]; then
    last_backup="Unknown"
  fi

  echo "Restore Summary:"

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    backup_path="$(_juvy_entry_to_backup_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        dir_file_count="${dir_file_count#"${dir_file_count%%[![:space:]]*}"}"
        (( total_files += dir_file_count ))
        (( ++dir_count ))
      fi
    else
      if [[ -f "$backup_path" ]]; then
        (( ++total_files ))
        (( ++file_count ))
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  if (( total_files == 0 )); then
    return 1
  fi

  echo "   $total_files files will be restored from backup"
  echo "   Last backup: $last_backup"
  echo ""

  echo "Files to restore:"
  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    backup_path="$(_juvy_entry_to_backup_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        dir_file_count="${dir_file_count#"${dir_file_count%%[![:space:]]*}"}"
        echo "  ~$entry ($dir_file_count files)"
      fi
    else
      if [[ -f "$backup_path" ]]; then
        file_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
        [[ -z "$file_size" ]] && file_size="0B"
        echo "  ~$entry ($file_size)"
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  return 0
}

_juvy_create_safety_backup() {
  local timestamp safety_dir entry backup_path source_path dest_path dest_dir

  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  safety_dir="$_JUVY_CONFIG_DIR/safety-backup/$timestamp"

  if ! mkdir -p "$safety_dir" > /dev/null 2>&1; then
    echo "Failed to create safety backup directory: $safety_dir" >&2
    return 1
  fi

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    source_path="$(_juvy_entry_to_source_path "$entry")"

    if [[ -e "$source_path" ]]; then
      dest_path="$safety_dir$entry"
      dest_dir="$(dirname "$dest_path")"

      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        echo "Failed to create safety backup directory: $dest_dir" >&2
        return 1
      fi

      if [[ "$entry" == */ ]]; then
        if [[ -d "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_dir/" > /dev/null 2>&1; then
            echo "Failed to backup directory: $source_path" >&2
            return 1
          fi
        fi
      else
        if [[ -f "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_path" > /dev/null 2>&1; then
            echo "Failed to backup file: $source_path" >&2
            return 1
          fi
        fi
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  echo "$safety_dir"
  return 0
}

_juvy_perform_restore() {
  local dry_run="${1:-false}"
  local backup_dir="$_JUVY_BACKUP_DIR"
  local home_paths=()
  local system_paths=()
  local source_path entry

  if [[ "$dry_run" == "true" ]]; then
    echo "Showing what would be restored from backup..."
  else
    echo "Restoring files from backup..."
  fi

  _juvy_collect_backup_entries

  for entry in ${_JUVY_INCLUDE_PATHS[@]+"${_JUVY_INCLUDE_PATHS[@]}"}; do
    source_path="$(_juvy_entry_to_source_path "$entry")"
    if [[ "$source_path" == "$HOME/"* ]]; then
      home_paths+=("$entry")
    else
      system_paths+=("$entry")
    fi
  done

  if [[ ${#home_paths[@]} -gt 0 ]]; then
    local home_filter_file
    home_filter_file="$(mktemp)"

    if ! _juvy_build_rsync_filter_file "$HOME" home_paths _JUVY_EXCLUDE_PATTERNS "$home_filter_file"; then
      echo "Failed to build restore filter for home paths" >&2
      rm -f "$home_filter_file"
      return 1
    fi

    if ! _juvy_rsync_restore_with_filters "$backup_dir$HOME" "$HOME" "$home_filter_file" "$dry_run"; then
      echo "Failed to restore home files" >&2
      rm -f "$home_filter_file"
      return 1
    fi

    rm -f "$home_filter_file"
  fi

  if [[ ${#system_paths[@]} -gt 0 ]]; then
    local system_filter_file
    local extra_excludes=()
    system_filter_file="$(mktemp)"
    extra_excludes=("/.git/")

    if ! _juvy_build_rsync_filter_file "/" system_paths _JUVY_EXCLUDE_PATTERNS "$system_filter_file" extra_excludes; then
      echo "Failed to build restore filter for system paths" >&2
      rm -f "$system_filter_file"
      return 1
    fi

    if ! _juvy_rsync_restore_with_filters "$backup_dir" "/" "$system_filter_file" "$dry_run"; then
      echo "Failed to restore system files" >&2
      rm -f "$system_filter_file"
      return 1
    fi

    rm -f "$system_filter_file"
  fi

  if [[ "$dry_run" != "true" ]]; then
    echo "Files restored successfully"
  fi
  return 0
}

_juvy_list() {
  local total_files=0 total_dirs=0 total_size=0
  local entry source_path file_size file_date display_size file_count

  _juvy_validate_backup_file_exists || return 1

  if [[ ! -s "$_JUVY_BACKUP_FILE" ]]; then
    echo "No files are currently tracked."
    echo "   Use 'juvy add <path>' to add files or directories."
    return 0
  fi

  echo "Tracked Files and Directories:"
  echo ""

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    source_path="$(_juvy_entry_to_source_path "$entry")"

    if [[ "$entry" == */ ]]; then
      if [[ -d "$source_path" ]]; then
        local dir_info
        if dir_info="$(_juvy_calculate_directory_info "$source_path")"; then
          file_count="$(_juvy_parse_dir_info "$dir_info" count)"
          display_size="$(_juvy_parse_dir_info "$dir_info" human)"
          total_size=$((total_size + $(_juvy_parse_dir_info "$dir_info" bytes)))
          (( ++total_dirs ))
        else
          file_count="?"
          display_size="?"
        fi

        if [[ -d "$source_path" ]]; then
          file_date="$(_juvy_get_file_mtime_human "$source_path")"
          [[ -z "$file_date" ]] && file_date="Unknown"
        else
          file_date="Missing"
        fi

        printf "  [D] %-30s %8s  %s (%s files)\n" "$entry" "$display_size" "$file_date" "$file_count"
      else
        printf "  [X] %-30s %8s  %s (missing)\n" "$entry" "-" "-"
      fi
    else
      if [[ -f "$source_path" ]]; then
        file_size="$(du -h "$source_path" 2>/dev/null | cut -f1)"
        [[ -z "$file_size" ]] && file_size="0B"

        file_date="$(_juvy_get_file_mtime_human "$source_path")"
        [[ -z "$file_date" ]] && file_date="Unknown"

        total_size=$((total_size + $(_juvy_get_file_size "$source_path")))
        (( ++total_files ))

        printf "  [F] %-30s %8s  %s\n" "$entry" "$file_size" "$file_date"
      else
        printf "  [X] %-30s %8s  %s (missing)\n" "~$entry" "-" "-"
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  echo ""
  if (( total_size >= 1073741824 )); then
    display_size="$(( total_size / 1073741824 )).$(( (total_size % 1073741824) / 107374182 ))GB"
  elif (( total_size >= 1048576 )); then
    display_size="$(( total_size / 1048576 )).$(( (total_size % 1048576) / 104857 ))MB"
  elif (( total_size >= 1024 )); then
    display_size="$(( total_size / 1024 ))KB"
  else
    display_size="${total_size}B"
  fi

  echo "Summary: $((total_files + total_dirs)) items tracked, ~$display_size total"
}

# Cross-platform file mtime (human readable)
_juvy_get_file_mtime_human() {
  local file="$1"
  case "$_JUVY_PLATFORM" in
    macos) stat -f '%Sm' "$file" 2>/dev/null ;;
    *)     stat -c '%y' "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 ;;
  esac
}

# Cross-platform file mtime (epoch)
_juvy_get_file_mtime() {
  local file="$1"
  case "$_JUVY_PLATFORM" in
    macos) stat -f '%m' "$file" 2>/dev/null ;;
    *)     stat -c '%Y' "$file" 2>/dev/null ;;
  esac
}

# Cross-platform file size
_juvy_get_file_size() {
  local file="$1"
  case "$_JUVY_PLATFORM" in
    macos) stat -f '%z' "$file" 2>/dev/null || echo 0 ;;
    *)     stat -c '%s' "$file" 2>/dev/null || echo 0 ;;
  esac
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
    echo "Last backup: $last_backup_date ($last_backup_relative)"
  else
    echo "No backup history found"
  fi

  # Check for changes in backup directory (uncommitted changes)
  local backup_changes="$(_juvy_git status --porcelain 2>/dev/null)"

  # Check for changes in actual tracked files
  local live_changes=0
  local changed_files=()
  local deleted_files=()
  local new_files=()
  local entry source_path backup_path

  while IFS= read -r entry; do
    entry="$(_juvy_parse_entry_basic "$entry")" || continue

    source_path="$(_juvy_entry_to_source_path "$entry")"
    backup_path="$(_juvy_entry_to_backup_path "$entry")"

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
            (( ++live_changes ))
          fi
        fi
      elif [[ -d "$source_path" && ! -d "$backup_path" ]]; then
        # Directory exists but not backed up
        new_files+=("$entry")
        (( ++live_changes ))
      elif [[ ! -d "$source_path" && -d "$backup_path" ]]; then
        # Directory was deleted
        deleted_files+=("$entry")
        (( ++live_changes ))
      fi
    else
      # File entry
      if [[ -f "$source_path" && -f "$backup_path" ]]; then
        # Compare modification times first (fast check)
        local source_mtime="$(_juvy_get_file_mtime "$source_path")"
        local backup_mtime="$(_juvy_get_file_mtime "$backup_path")"

        if [[ -n "$source_mtime" && -n "$backup_mtime" && "$source_mtime" != "$backup_mtime" ]]; then
          # Times differ, check if content actually changed
          if ! diff -q "$source_path" "$backup_path" >/dev/null 2>&1; then
            changed_files+=("$entry")
            (( ++live_changes ))
          fi
        elif [[ -z "$source_mtime" || -z "$backup_mtime" ]]; then
          # Fallback to content comparison if stat fails
          if ! diff -q "$source_path" "$backup_path" >/dev/null 2>&1; then
            changed_files+=("$entry")
            (( ++live_changes ))
          fi
        fi
      elif [[ -f "$source_path" && ! -f "$backup_path" ]]; then
        # File exists but not backed up
        new_files+=("$entry")
        (( ++live_changes ))
      elif [[ ! -f "$source_path" && -f "$backup_path" ]]; then
        # File was deleted
        deleted_files+=("$entry")
        (( ++live_changes ))
      fi
    fi
  done < "$_JUVY_BACKUP_FILE"

  # Display results
  if [[ -z "$backup_changes" && $live_changes -eq 0 ]]; then
    echo "No changes since last backup"
    return 0
  fi

  # Show uncommitted changes in backup directory
  if [[ -n "$backup_changes" ]]; then
    echo "Uncommitted changes in backup directory:"

    local status_prefix file_path display_path line
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
        " M"|"M ")
          echo "  [M] $display_path (modified)"
          ;;
        " A"|"A ")
          echo "  [A] $display_path (added)"
          ;;
        " D"|"D ")
          echo "  [D] $display_path (deleted)"
          ;;
        "??")
          echo "  [?] $display_path (untracked)"
          ;;
        *)
          echo "  [*] $display_path (changed)"
          ;;
      esac
    done <<< "$backup_changes"

    if [[ $live_changes -gt 0 ]]; then
      echo ""
    fi
  fi

  # Show changes in actual tracked files
  if [[ $live_changes -gt 0 ]]; then
    echo "Modified files since last backup:"

    # Show modified files
    local file
    for file in "${changed_files[@]}"; do
      echo "  [M] $file (modified)"
    done

    # Show new files (exist but not in backup)
    for file in "${new_files[@]}"; do
      echo "  [+] $file (new)"
    done

    # Show deleted files (in backup but deleted from system)
    for file in "${deleted_files[@]}"; do
      echo "  [-] $file (deleted)"
    done
  fi

  echo ""
  echo "Run 'juvy backup' to save changes"
  echo "Run 'juvy status [file]' for detailed changes"

  # Show remote status if configured
  if [[ -n "$_JUVY_REMOTE_URL" ]]; then
    echo ""
    echo "Remote: $_JUVY_REMOTE_URL"
    if [[ "$_JUVY_REMOTE_PUSH" == "true" ]]; then
      echo "   Auto-push: enabled"
    else
      echo "   Auto-push: disabled"
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
    echo "File not found in backup: $file_arg" >&2
    echo "   Use 'juvy add $file_arg' to track this file" >&2
    return 1
  fi

  if [[ ! -f "$source_file_path" ]]; then
    echo "Source file not found: $file_arg" >&2
    return 1
  fi

  local last_backup_date
  last_backup_date="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  [[ -z "$last_backup_date" ]] && last_backup_date="Unknown"

  echo "Comparing: $file_arg"
  echo "   Backup: $last_backup_date"
  echo "   Current: $(_juvy_get_file_mtime_human "$source_file_path")"
  echo ""

  if diff -u "$backup_file_path" "$source_file_path" 2>/dev/null; then
    echo "No differences found"
  fi
}



_juvy_get_relative_time() {
  local backup_date="$1"
  local date_bin backup_epoch current_epoch diff_seconds

  if command -v gdate >/dev/null 2>&1; then
    date_bin="gdate"
  else
    date_bin="date"
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

