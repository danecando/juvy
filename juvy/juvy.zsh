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
  
  # Use enhanced rsync with error handling and retry logic
  if ! _juvy_rsync_with_retry "$HOME" "$JUVY_BACKUP_DIR" "$JUVY_BACKUP"; then
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

_juvy_add() {
  local force_flag=0
  local -a files_to_add
  
  # Parse arguments for --force flag
  while [[ $# -gt 0 ]]; do
    case "$1" in
      (--force)
        force_flag=1
        shift
        ;;
      (*)
        files_to_add+=("$1")
        shift
        ;;
    esac
  done
  
  if [[ ! -f "$JUVY_BACKUP" ]]; then
    print "❌ Backup file not found. Run 'juvy init' first." >&2
    return 1
  fi
  
  if [[ ${#files_to_add[@]} -eq 0 ]]; then
    # No arguments, open in editor
    local editor="${EDITOR:-nano}"
    if (( $+commands[$editor] )); then
      "$editor" "$JUVY_BACKUP"
    else
      print "❌ Editor '$editor' not found. Set EDITOR environment variable or install nano." >&2
      return 1
    fi
  else
    # Arguments provided, check for sensitive files and append to file
    local file
    for file in "${files_to_add[@]}"; do
      # Check if file is sensitive (unless forced)
      if [[ $force_flag -eq 0 ]] && _juvy_is_sensitive_file "$file"; then
        if ! _juvy_show_security_warning "$file"; then
          print "❌ Cancelled adding '$file'"
          continue
        fi
      fi
      
      print "$file" >> "$JUVY_BACKUP"
      print "✅ Added '$file' to backup list"
    done
  fi
}

_juvy_help() {
  print "juvy $JUVY_VERSION - dotfile backup utility"
  print ""
  print "Usage: juvy <command>"
  print ""
  print "Commands:"
  print "  init        Initialize juvy configuration"
  print "  add         Add files to backup list (or edit with \$EDITOR)"
  print "              Use 'add --force <file>' to bypass security warnings"
  print "  backup      Backup files to configured directory"
  print "  git         Run git commands in backup directory"
  print "  update      Update juvy to the latest version"
  print "  version     Show version information"
  print "  uninstall   Remove juvy from system (preserves backups)"
  print "  nuke        Completely destroy juvy and all backups"
}
