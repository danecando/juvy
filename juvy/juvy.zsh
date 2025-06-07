emulate -L zsh

JUVY_VERSION="1.0.1"
JUVY_CONFIG_DIR="$HOME/.config/juvy"
JUVY_CONFIG="$JUVY_CONFIG_DIR/config"
JUVY_BACKUP="$JUVY_CONFIG_DIR/backup"
JUVY_LOG="$JUVY_CONFIG_DIR/log"

if [[ -f "$JUVY_CONFIG" ]]; then
  source "$JUVY_CONFIG"
fi

: ${JUVY_BACKUP_DIR:="$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy"}

juvy() {
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
    (backup)
      _juvy_backup "$@"
      ;;
    (check)
      _juvy_check "$@"
      ;;
    (version|--version|-v)
      print "juvy $JUVY_VERSION"
      ;;
    (git)
      shift
      _juvy_git "$@"
      ;;
    (update)
      _juvy_update "$@"
      ;;
    (nuke)
      _juvy_nuke "$@"
      ;;
    (restore)
      _juvy_restore "$@"
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

_juvy_init() {
  if [[ ! -d "$JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi

  if [[ ! -f "$JUVY_BACKUP" ]]; then
    print "/.zshrc\n/.gitconfig" >> "$JUVY_BACKUP"
  fi

  if [[ ! -f "$JUVY_CONFIG" ]]; then
    touch "$JUVY_CONFIG"
  fi

  _juvy_init_backups
}

_juvy_init_backups() { 
  local dir
  
  if ! grep -q "JUVY_BACKUP_DIR=" "$JUVY_CONFIG" 2>/dev/null; then
    printf "juvy: Where do you want backups to be stored? (enter for default: %s) " "$JUVY_BACKUP_DIR"
    read -r "dir?"

    if [[ -n $dir ]]; then
      if mkdir -p "$dir" > /dev/null 2>&1; then
        JUVY_BACKUP_DIR="$dir"
      else
        printf "juvy: Unable to create backup directory (%s). Falling back to default (%s)\n" "$dir" "$JUVY_BACKUP_DIR"
      fi
    fi

    print -r "JUVY_BACKUP_DIR=$(printf %q "$JUVY_BACKUP_DIR")" > "$JUVY_CONFIG"
  fi 

  if [[ ! -d "$JUVY_BACKUP_DIR/.git" ]]; then
    git init -b main "$JUVY_BACKUP_DIR"
  fi
}

_juvy_uninstall() {
  local confirm
  
  print "This will remove juvy from your system (but preserve backups):"
  print "  • Configuration directory: $JUVY_CONFIG_DIR"
  print "  • Installation directory: $HOME/.juvy"
  print "  • juvy entry from ~/.zshrc"
  print ""
  print "❗ Backup directory will be preserved: $JUVY_BACKUP_DIR"
  print "Are you sure you want to proceed? [y/N] "
  read -r "confirm?"
  
  if [[ "$confirm" != "y" ]]; then
    print "Remove cancelled"
    return 0
  fi
  
  _juvy_uninstall_internal
  
  print ""
  print "✅ juvy has been removed from your system"
  print "💾 Your backups are preserved in: $JUVY_BACKUP_DIR"
  print "ℹ️  Restart your shell or run: source ~/.zshrc"
}

_juvy_validate_backup_file() {
  local invalid_paths=()
  local large_paths=()
  local line_num=0
  local path full_path
  
  print "🔍 Validating backup file..."
  
  while IFS= read -r path; do
    (( line_num++ ))
    
    # Skip empty lines and comments
    [[ -z "$path" || "$path" =~ '^[[:space:]]*#' ]] && continue
    
    # Convert to full path for validation
    if [[ "$path" = /* ]]; then
      full_path="$HOME$path"
    else
      full_path="$HOME/$path"
    fi
    
    if [[ ! -e "$full_path" ]]; then
      invalid_paths+=("Line $line_num: $path")
    elif [[ -d "$full_path" ]]; then
      # Check directory size
      if _juvy_calculate_directory_info "$path"; then
        if (( JUVY_DIR_SIZE_BYTES > 104857600 )); then
          large_paths+=("Line $line_num: $path ($JUVY_DIR_SIZE_HUMAN, $JUVY_DIR_FILE_COUNT files)")
        fi
      fi
    fi
  done < "$JUVY_BACKUP"
  
  # Report issues
  if (( ${#invalid_paths[@]} > 0 )); then
    print "⚠️  Invalid paths found in backup file:" >&2
    for invalid in "${invalid_paths[@]}"; do
      print "   $invalid" >&2
    done
    print "   These paths will be skipped during backup" >&2
    print ""
  fi
  
  if (( ${#large_paths[@]} > 0 )); then
    print "⚠️  Large directories found in backup file:" >&2
    for large in "${large_paths[@]}"; do
      print "   $large" >&2
    done
    print "   These may slow down backup and consume significant storage" >&2
    print ""
  fi
  
  return 0
}

_juvy_backup() {
  if [[ ! -d "$JUVY_BACKUP_DIR" ]]; then
    printf "juvy: Set JUVY_BACKUP_DIR value in %s\n" "$JUVY_CONFIG" >&2
    return 1
  fi
  
  if [[ ! -f "$JUVY_BACKUP" ]]; then
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  
  print "🔄 Starting backup process..."
  
  # Validate backup file before starting rsync
  _juvy_validate_backup_file
  
  # Process backup entries with support for directories and files
  if ! _juvy_process_backup_entries; then
    print "❌ Backup failed" >&2
    return 1
  fi
  
  print "✅ Files synced successfully"
  
  # Check if there are changes to commit
  if [[ -n $(_juvy_git status --porcelain) ]]; then
    _juvy_git add .
    if ! _juvy_git commit -m "Backup: $(_juvy_timestamp)"; then
      print "⚠️  Git commit failed, but files were synced" >&2
      _juvy_log_error "Git commit failed after successful rsync"
      return 1
    fi
    print "✅ Changes committed to git"
  else
    print "ℹ️  No changes to commit"
  fi
  
  print "✅ Backup completed successfully"
}

_juvy_check() {
  if [[ ! -f "$JUVY_BACKUP" ]]; then
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  
  _juvy_validate_backup_file
  print "✅ Backup file validation completed"
}

_juvy_process_backup_entries() {
  local entry
  local source_path
  local dest_dir
  local file_count=0
  local dir_count=0
  
  # Read backup file line by line
  while IFS= read -r entry; do
    # Skip empty lines and comments
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    
    # Remove leading/trailing whitespace
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    
    [[ -z "$entry" ]] && continue
    
    source_path="$HOME$entry"
    
    if [[ "$entry" == */ ]]; then
      # Directory entry (ends with /)
      if [[ ! -d "$source_path" ]]; then
        print "⚠️  Directory not found: $source_path" >&2
        continue
      fi
      
      print "📁 Backing up directory: $entry"
      
      # For directories, create destination directory and sync contents
      dest_dir="$JUVY_BACKUP_DIR$entry"
      
      # Create destination directory structure
      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        print "❌ Failed to create destination directory: $dest_dir" >&2
        return 1
      fi
      
      # Use rsync to copy directory contents recursively
      if ! _juvy_rsync_directory "$source_path" "$dest_dir"; then
        print "❌ Failed to backup directory: $entry" >&2
        return 1
      fi
      
      (( dir_count++ ))
    else
      # File entry
      if [[ ! -f "$source_path" ]]; then
        print "⚠️  File not found: $source_path" >&2
        continue
      fi
      
      print "📄 Backing up file: $entry"
      
      # For files, create destination directory and copy file
      dest_dir="$JUVY_BACKUP_DIR$(dirname "$entry")"
      
      # Create destination directory structure
      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        print "❌ Failed to create destination directory: $dest_dir" >&2
        return 1
      fi
      
      # Use rsync to copy individual file
      if ! _juvy_rsync_file "$source_path" "$dest_dir/"; then
        print "❌ Failed to backup file: $entry" >&2
        return 1
      fi
      
      (( file_count++ ))
    fi
  done < "$JUVY_BACKUP"
  
  print "ℹ️  Processed $file_count files and $dir_count directories"
  return 0
}

_juvy_rsync_directory() {
  local source="$1"
  local dest="$2"
  local max_retries=3
  local retry_count=0
  local rsync_output
  local rsync_exit_code
  
  while (( retry_count < max_retries )); do
    # Use rsync with -a (archive mode) and --delete to sync directory contents
    if rsync_output=$(rsync -av --delete "$source" "$dest" 2>&1); then
      return 0
    fi
    
    rsync_exit_code=$?
    
    # Handle retries for transient errors (same logic as existing function)
    case $rsync_exit_code in
      (30|11)  # Timeout or I/O error
        (( retry_count++ ))
        if (( retry_count < max_retries )); then
          print "⚠️  rsync error, retrying ($retry_count/$max_retries)..." >&2
          _juvy_log_error "rsync directory error (exit code $rsync_exit_code), retry $retry_count/$max_retries: $rsync_output"
          sleep 2
          continue
        fi
        ;;
    esac
    
    _juvy_log_error "rsync directory failed (exit code $rsync_exit_code): $rsync_output"
    return $rsync_exit_code
  done
}

_juvy_rsync_file() {
  local source="$1"
  local dest="$2"
  local max_retries=3
  local retry_count=0
  local rsync_output
  local rsync_exit_code
  
  while (( retry_count < max_retries )); do
    # Use rsync with -a (archive mode) for individual file
    if rsync_output=$(rsync -av "$source" "$dest" 2>&1); then
      return 0
    fi
    
    rsync_exit_code=$?
    
    # Handle retries for transient errors (same logic as existing function)
    case $rsync_exit_code in
      (30|11)  # Timeout or I/O error
        (( retry_count++ ))
        if (( retry_count < max_retries )); then
          print "⚠️  rsync error, retrying ($retry_count/$max_retries)..." >&2
          _juvy_log_error "rsync file error (exit code $rsync_exit_code), retry $retry_count/$max_retries: $rsync_output"
          sleep 2
          continue
        fi
        ;;
    esac
    
    _juvy_log_error "rsync file failed (exit code $rsync_exit_code): $rsync_output"
    return $rsync_exit_code
  done
}

_juvy_timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

_juvy_log_error() {
  local message="$1"
  local timestamp
  
  timestamp="$(_juvy_timestamp)"
  
  # Ensure log directory exists
  if [[ ! -d "$JUVY_CONFIG_DIR" ]]; then
    mkdir -p "$JUVY_CONFIG_DIR" > /dev/null 2>&1
  fi
  
  # Log error with timestamp
  print "[$timestamp] $message" >> "$JUVY_LOG"
}

_juvy_rsync_with_retry() {
  local source="$1"
  local dest="$2"
  local files_from="$3"
  local max_retries=3
  local retry_count=0
  local rsync_output
  local rsync_exit_code
  
  while (( retry_count < max_retries )); do
    # Capture both stdout and stderr
    if rsync_output=$(rsync -a --files-from="$files_from" "$source" "$dest" 2>&1); then
      return 0
    fi
    
    rsync_exit_code=$?
    
    # Check if this is a transient error that should be retried
    case $rsync_exit_code in
      (30)  # Timeout in data send/receive
        (( retry_count++ ))
        if (( retry_count < max_retries )); then
          print "⚠️  rsync timeout, retrying ($retry_count/$max_retries)..." >&2
          _juvy_log_error "rsync timeout (exit code $rsync_exit_code), retry $retry_count/$max_retries: $rsync_output"
          sleep 2
          continue
        fi
        ;;
      (11)  # File I/O error - might be transient
        (( retry_count++ ))
        if (( retry_count < max_retries )); then
          print "⚠️  rsync I/O error, retrying ($retry_count/$max_retries)..." >&2
          _juvy_log_error "rsync I/O error (exit code $rsync_exit_code), retry $retry_count/$max_retries: $rsync_output"
          sleep 1
          continue
        fi
        ;;
    esac
    
    # For non-transient errors or after max retries, show user-friendly message
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
      (30)
        print "❌ rsync timeout in data send/receive" >&2
        ;;
      (*)
        print "❌ rsync failed with error code $rsync_exit_code" >&2
        ;;
    esac
    
    print "See $JUVY_LOG for details" >&2
    _juvy_log_error "rsync failed (exit code $rsync_exit_code): $rsync_output"
    return $rsync_exit_code
  done
}

_juvy_git() {
  if [[ -d "$JUVY_BACKUP_DIR" ]]; then
    git -C "$JUVY_BACKUP_DIR" "$@"
  fi
}

_juvy_update() {
  local temp_script="/tmp/juvy_update.zsh"
  local juvy_script="$HOME/.juvy/juvy.zsh"
  local repo_url="https://raw.githubusercontent.com/danecando/juvy/main/juvy/juvy.zsh"
  local latest_version update
  
  print "Checking for updates..."
  
  if ! curl -sSL "$repo_url" -o "$temp_script"; then
    print "❌ Failed to download latest version" >&2
    return 1
  fi
  
  latest_version=$(grep "^JUVY_VERSION=" "$temp_script" | cut -d'"' -f2)
  
  if [[ -z "$latest_version" ]]; then
    print "❌ Failed to extract version from downloaded script" >&2
    rm -f "$temp_script"
    return 1
  fi
  
  if [[ "$latest_version" == "$JUVY_VERSION" ]]; then
    print "✅ juvy is already up to date (v$JUVY_VERSION)"
    rm -f "$temp_script"
    return 0
  fi
  
  print "📦 Update available: v$JUVY_VERSION → v$latest_version"
  print "Do you want to update? [Y/n] "
  read -r "update?"
  
  if [[ "$update" == "n" ]]; then
    print "Update cancelled"
    rm -f "$temp_script"
    return 0
  fi
  
  if mv "$temp_script" "$juvy_script"; then
    print "✅ Updated juvy to v$latest_version"
    print "ℹ️  Restart your shell or run: source ~/.zshrc"
  else
    print "❌ Failed to update juvy" >&2
    rm -f "$temp_script"
    return 1
  fi
}

_juvy_nuke() {
  local confirm
  
  print "🚨 WARNING: This will COMPLETELY DESTROY all juvy data including:"
  print "  • Configuration directory: $JUVY_CONFIG_DIR"
  print "  • Backup directory: $JUVY_BACKUP_DIR"
  print "  • Installation directory: $HOME/.juvy"
  print "  • juvy entry from ~/.zshrc"
  print ""
  print "💥 ALL YOUR BACKUPS WILL BE DELETED!"
  print "❗ This action cannot be undone!"
  print "Are you absolutely sure? [y/N] "
  read -r "confirm?"
  
  if [[ "$confirm" != "y" ]]; then
    print "Nuke cancelled"
    return 0
  fi
  
  # Call rm function first (removes config, installation, .zshrc)
  _juvy_uninstall_internal
  
  # Remove backup directory
  if [[ -d "$JUVY_BACKUP_DIR" ]]; then
    rm -rf "$JUVY_BACKUP_DIR"
    print "💥 Nuked backup directory"
  fi
  
  print ""
  print "💥 juvy has been completely nuked from your system"
  print "ℹ️  Restart your shell or run: source ~/.zshrc"
}

_juvy_uninstall_internal() {
  # Remove configuration directory
  if [[ -d "$JUVY_CONFIG_DIR" ]]; then
    rm -rf "$JUVY_CONFIG_DIR"
    print "🗑️  Removed configuration directory"
  fi
  
  # Remove installation directory
  if [[ -d "$HOME/.juvy" ]]; then
    rm -rf "$HOME/.juvy"
    print "🗑️  Removed installation directory"
  fi
  
  # Remove from .zshrc
  if [[ -f "$HOME/.zshrc" ]] && grep -q "source.*\.juvy/juvy\.zsh" "$HOME/.zshrc"; then
    # Create a temporary file without the juvy lines
    {
      grep -v "source.*\.juvy/juvy\.zsh" "$HOME/.zshrc" | grep -v "# juvy dotfile backup tool"
    } > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
    print "🗑️  Removed juvy from .zshrc"
  fi
}

_juvy_is_sensitive_file() {
  local file="$1"
  local -a sensitive_patterns
  
  sensitive_patterns=(
    "*id_rsa*" "*id_ed25519*" "*id_ecdsa*"  # SSH keys
    "*.pem" "*.key" "*.cert"                 # Certificates
    "*credentials*" "*token*" "*secret*"     # Credentials
    "*.env" ".env.*"                         # Environment files
    "*auth*" "*passwd*"                      # Auth files
  )
  
  local pattern
  for pattern in "${sensitive_patterns[@]}"; do
    if [[ "${file:t}" == ${~pattern} ]]; then
      return 0
    fi
  done
  return 1
}

_juvy_show_security_warning() {
  local file="$1"
  local choice
  
  print "🔒 Security Warning: This appears to be a sensitive file"
  print "   File: $file"
  print ""
  print "Backing up to cloud storage may expose sensitive data."
  print "Options:"
  print "  1) Cancel (recommended)"
  print "  2) Continue anyway"
  print ""
  print -n "Choice [1-2]: "
  read -r "choice?"
  
  case "$choice" in
    (2)
      return 0
      ;;
    (*)
      return 1
      ;;
  esac
}

_juvy_validate_path() {
  local path="$1"
  local full_path
  
  # Convert to full path for validation
  if [[ "$path" = /* ]]; then
    full_path="$path"
  else
    # Path relative to HOME (remove leading ./ or /)
    path="${path#./}"
    path="${path#/}"
    full_path="$HOME/$path"
  fi
  
  if [[ ! -e "$full_path" ]]; then
    print "❌ Path does not exist: $path" >&2
    return 1
  fi
  
  return 0
}

_juvy_calculate_directory_info() {
  local path="$1"
  local full_path
  local size_bytes size_human file_count
  
  # Convert to full path
  if [[ "$path" = /* ]]; then
    full_path="$path"
  else
    path="${path#./}"
    path="${path#/}" 
    full_path="$HOME/$path"
  fi
  
  if [[ ! -d "$full_path" ]]; then
    return 1
  fi
  
  # Calculate size in bytes using du
  size_bytes=$(du -sb "$full_path" 2>/dev/null | cut -f1)
  
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
  
  # Return values via global variables for zsh compatibility
  JUVY_DIR_SIZE_BYTES="$size_bytes"
  JUVY_DIR_SIZE_HUMAN="$size_human"
  JUVY_DIR_FILE_COUNT="$file_count"
  
  return 0
}

_juvy_prompt_large_directory() {
  local path="$1"
  local size_human="$2" 
  local file_count="$3"
  local force="$4"
  local response
  
  if [[ "$force" == "true" ]]; then
    return 0
  fi
  
  print "⚠️  This directory contains:"
  print "   Files: $file_count"
  print "   Size: $size_human"
  print ""
  print "Large backups may be slow and consume significant storage."
  print "Continue? [y/N] "
  read -r "response?"
  
  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    return 1
  fi
  
  return 0
}

_juvy_add() {
  local force_flag="false"
  local paths=()
  
  if [[ ! -f "$JUVY_BACKUP" ]]; then
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  
  # Parse arguments for --force flag
  while [[ $# -gt 0 ]]; do
    case "$1" in
      (--force)
        force_flag="true"
        shift
        ;;
      (-*)
        print "❌ Unknown flag: $1" >&2
        print "Usage: juvy add [--force] [path...]" >&2
        return 1
        ;;
      (*)
        paths+=("$1")
        shift
        ;;
    esac
  done
  
  if [[ ${#paths[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if (( $+commands[$editor] )); then
      "$editor" "$JUVY_BACKUP"
      print "💡 Consider running 'juvy backup' to validate your backup file"
    else
      print "❌ Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
      return 1
    fi
  else
    # Arguments provided, validate and append to file
    for path in "${paths[@]}"; do
      # Validate path exists
      if ! _juvy_validate_path "$path"; then
        continue
      fi
      
      # Convert to absolute path if relative
      local full_path
      if [[ "$path" == /* ]]; then
        full_path="$path"
      else
        full_path="$PWD/$path"
      fi
      
      # Convert to relative path from HOME
      local backup_entry
      if [[ "$full_path" == "$HOME"* ]]; then
        backup_entry="${full_path#$HOME}"
      else
        print "❌ Path must be within home directory: $path" >&2
        continue
      fi
      
      # Normalize path (remove leading slash if present)
      backup_entry="${backup_entry#/}"
      backup_entry="/$backup_entry"
      
      # Check if path exists and determine type
      if [[ -d "$full_path" ]]; then
        # Directory - ensure it ends with /
        if [[ "$backup_entry" != */ ]]; then
          backup_entry="$backup_entry/"
        fi
        
        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$JUVY_BACKUP" 2>/dev/null; then
          print "ℹ️  Path already in backup list: $backup_entry"
          continue
        fi
        
        # Check for sensitive files (unless --force is used)
        if [[ "$force_flag" != "true" ]] && _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            print "❌ Skipped adding sensitive directory: $path"
            continue
          fi
        fi
        
        # For directories, check size and prompt if needed
        if _juvy_calculate_directory_info "$path"; then
          # Check if directory is larger than 100MB (104857600 bytes)
          if (( JUVY_DIR_SIZE_BYTES > 104857600 )); then
            if ! _juvy_prompt_large_directory "$path" "$JUVY_DIR_SIZE_HUMAN" "$JUVY_DIR_FILE_COUNT" "$force_flag"; then
              print "❌ Skipped adding large directory: $path"
              continue
            fi
          fi
        fi
        
        print "$backup_entry" >> "$JUVY_BACKUP"
        print "✅ Added directory '$backup_entry' to backup list"
        
      elif [[ -f "$full_path" ]]; then
        # File - ensure it doesn't end with /
        backup_entry="${backup_entry%/}"
        
        # Check if path is already in backup file
        if grep -Fxq "$backup_entry" "$JUVY_BACKUP" 2>/dev/null; then
          print "ℹ️  Path already in backup list: $backup_entry"
          continue
        fi
        
        # Check for sensitive files (unless --force is used)
        if [[ "$force_flag" != "true" ]] && _juvy_is_sensitive_file "$backup_entry"; then
          if ! _juvy_show_security_warning "$backup_entry"; then
            print "❌ Skipped adding sensitive file: $path"
            continue
          fi
        fi
        
        print "$backup_entry" >> "$JUVY_BACKUP"
        print "✅ Added file '$backup_entry' to backup list"
        
      else
        print "❌ Path not found: $path" >&2
        continue
      fi
    done
  fi
}

_juvy_restore() {
  if [[ ! -d "$JUVY_BACKUP_DIR" ]]; then
    print "❌ Backup directory not found: $JUVY_BACKUP_DIR" >&2
    print "Run 'juvy init' to set up backup directory" >&2
    return 1
  fi
  
  if [[ ! -f "$JUVY_BACKUP" ]]; then
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  
  if [[ ! -d "$JUVY_BACKUP_DIR/.git" ]]; then
    print "❌ Backup directory is not a git repository" >&2
    return 1
  fi
  
  local file_count dir_count total_size last_backup
  
  if ! _juvy_show_restore_preview; then
    print "❌ No files found to restore" >&2
    return 1
  fi
  
  print ""
  print "⚠️  Current files will be backed up to ~/.config/juvy/safety-backup/"
  print ""
  print -n "Proceed with restore? [Y/n] "
  local confirm
  read -r "confirm?"
  
  if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    print "Restore cancelled"
    return 0
  fi
  
  print ""
  print "✓ Creating safety backup..."
  local safety_backup_path
  if ! safety_backup_path="$(_juvy_create_safety_backup)"; then
    print "❌ Failed to create safety backup" >&2
    return 1
  fi
  
  print "✓ Restoring files..."
  if ! _juvy_perform_restore; then
    print "❌ Restore failed" >&2
    return 1
  fi
  
  print "✓ Setting permissions..."
  print "✅ Restore complete!"
  print ""
  print "💡 To undo: juvy restore \"$safety_backup_path\""
}

_juvy_show_restore_preview() {
  local entry file_count=0 dir_count=0 total_files=0
  local backup_path source_path file_size last_backup
  
  last_backup="$(_juvy_git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  if [[ -z "$last_backup" ]]; then
    last_backup="Unknown"
  fi
  
  print "📋 Restore Summary:"
  
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" ]] && continue
    
    backup_path="$JUVY_BACKUP_DIR$entry"
    
    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        (( total_files += dir_file_count ))
        (( dir_count++ ))
      fi
    else
      if [[ -f "$backup_path" ]]; then
        (( total_files++ ))
        (( file_count++ ))
      fi
    fi
  done < "$JUVY_BACKUP"
  
  if (( total_files == 0 )); then
    return 1
  fi
  
  print "   $total_files files will be restored from backup"
  print "   Last backup: $last_backup"
  print ""
  
  print "Files to restore:"
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" ]] && continue
    
    backup_path="$JUVY_BACKUP_DIR$entry"
    
    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        local dir_file_count
        dir_file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
        print "  ~$entry ($dir_file_count files)"
      fi
    else
      if [[ -f "$backup_path" ]]; then
        file_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
        [[ -z "$file_size" ]] && file_size="0B"
        print "  ~$entry ($file_size)"
      fi
    fi
  done < "$JUVY_BACKUP"
  
  return 0
}

_juvy_create_safety_backup() {
  local timestamp safety_dir entry backup_path source_path dest_path dest_dir
  
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  safety_dir="$JUVY_CONFIG_DIR/safety-backup/$timestamp"
  
  if ! mkdir -p "$safety_dir" > /dev/null 2>&1; then
    print "❌ Failed to create safety backup directory: $safety_dir" >&2
    return 1
  fi
  
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" ]] && continue
    
    source_path="$HOME$entry"
    
    if [[ -e "$source_path" ]]; then
      dest_path="$safety_dir$entry"
      dest_dir="$(dirname "$dest_path")"
      
      if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
        print "❌ Failed to create safety backup directory: $dest_dir" >&2
        return 1
      fi
      
      if [[ "$entry" == */ ]]; then
        if [[ -d "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_dir/" > /dev/null 2>&1; then
            print "❌ Failed to backup directory: $source_path" >&2
            return 1
          fi
        fi
      else
        if [[ -f "$source_path" ]]; then
          if ! rsync -a "$source_path" "$dest_path" > /dev/null 2>&1; then
            print "❌ Failed to backup file: $source_path" >&2
            return 1
          fi
        fi
      fi
    fi
  done < "$JUVY_BACKUP"
  
  print "$safety_dir"
  return 0
}

_juvy_perform_restore() {
  local entry backup_path source_path dest_dir
  
  while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" ]] && continue
    
    backup_path="$JUVY_BACKUP_DIR$entry"
    source_path="$HOME$entry"
    
    if [[ "$entry" == */ ]]; then
      if [[ -d "$backup_path" ]]; then
        dest_dir="$(dirname "$source_path")"
        if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
          print "❌ Failed to create directory: $dest_dir" >&2
          return 1
        fi
        
        if ! rsync -a "$backup_path" "$dest_dir/" > /dev/null 2>&1; then
          print "❌ Failed to restore directory: $entry" >&2
          return 1
        fi
      fi
    else
      if [[ -f "$backup_path" ]]; then
        dest_dir="$(dirname "$source_path")"
        if ! mkdir -p "$dest_dir" > /dev/null 2>&1; then
          print "❌ Failed to create directory: $dest_dir" >&2
          return 1
        fi
        
        if ! rsync -a "$backup_path" "$source_path" > /dev/null 2>&1; then
          print "❌ Failed to restore file: $entry" >&2
          return 1
        fi
      fi
    fi
  done < "$JUVY_BACKUP"
  
  return 0
}

_juvy_help() {
  print "juvy $JUVY_VERSION - dotfile backup utility"
  print ""
  print "Usage: juvy <command>"
  print ""
  print "Commands:"
  print "  init        Initialize juvy configuration"
  print "  add         Add files/directories to backup list (or edit with \$EDITOR)"
  print "              Files: 'add ~/.zshrc' or 'add /path/to/file'"
  print "              Directories: 'add ~/.config/nvim/' (trailing slash auto-added)"
  print "              Validates paths and warns about large directories (>100MB)"
  print "              Detects sensitive files (SSH keys, certificates, etc.)"
  print "              Use 'add --force <path>' to bypass security warnings"
  print "  backup      Backup files and directories to configured directory"
  print "  restore     Restore all files from latest backup"
  print "  check       Validate backup file without running backup"
  print "  git         Run git commands in backup directory"
  print "  update      Update juvy to the latest version"
  print "  version     Show version information"
  print "  uninstall   Remove juvy from system (preserves backups)"
  print "  nuke        Completely destroy juvy and all backups"
  print ""
  print "Add command options:"
  print "  --force     Skip confirmation prompts for large directories and security warnings"
}
