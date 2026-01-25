## GIT/REMOTE FUNCTIONS ######################################################


# Manage git remote configuration commands

_juvy_remote() {
  case $1 in
    off)
      _juvy_remote_off
      ;;
    push)
      _juvy_remote_push
      ;;
    *)
      if [[ -z $1 ]]; then
        _juvy_remote_status
      elif _juvy_validate_git_url "$1"; then
        _juvy_remote_set "$1"
      else
        echo "juvy remote: Invalid URL or unknown command '$1'" >&2
        echo "Usage:" >&2
        echo "  juvy remote          # Show current status" >&2
        echo "  juvy remote <url>    # Set/change remote" >&2
        echo "  juvy remote off      # Remove remote" >&2
        echo "  juvy remote push     # Manual push" >&2
        return 1
      fi
      ;;
  esac
}

_juvy_remote_set() {
  local url="$1"
  local auto_push="true"
  local remote_name="origin"

  _juvy_validate_backup_dir_exists || return 1

  _juvy_info "Setting up git remote..."

  # Remove existing remote if it exists
  if _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    _juvy_git remote remove "$remote_name" 2>/dev/null
  fi

  # Add remote to git repository
  if ! _juvy_git remote add "$remote_name" "$url"; then
    _juvy_error "Failed to add remote"
    return 1
  fi

  # Test connection
  _juvy_info "Testing connection to remote..."
  if ! _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
    echo "Warning: Could not connect to remote (check URL and authentication)" >&2
    echo "   You can still proceed, but push/pull operations may fail" >&2
  else
    echo "Remote connection successful"
  fi

  # Update config file
  _juvy_update_config "JUVY_REMOTE_URL" "$url"
  _juvy_update_config "JUVY_REMOTE_PUSH" "$auto_push"
  _juvy_update_config "JUVY_REMOTE_NAME" "$remote_name"

  echo "Remote configured with auto-sync enabled"
  echo ""
  echo "Your backups will now automatically sync to the remote repository"
}

_juvy_remote_off() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"

  # Check if remote exists
  if ! _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    echo "No remote configured to disable" >&2
    return 0
  fi

  # Remove remote from git
  if ! _juvy_git remote remove "$remote_name"; then
    echo "Failed to remove remote" >&2
    return 1
  fi

  # Remove from config
  _juvy_remove_config "JUVY_REMOTE_URL"
  _juvy_remove_config "JUVY_REMOTE_PUSH"
  _juvy_remove_config "JUVY_REMOTE_NAME"

  echo "Remote disabled - auto-sync turned off"
}

_juvy_remote_push() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"

  if [[ -z "$_JUVY_REMOTE_URL" ]]; then
    echo "No remote configured. Add one with: juvy remote <url>" >&2
    return 1
  fi

  echo "Pushing to remote..."

  # Check if we have commits to push
  if ! _juvy_git log --oneline -1 >/dev/null 2>&1; then
    echo "No commits to push" >&2
    return 1
  fi

  # Push to remote
  if _juvy_git push "$remote_name" "$branch"; then
    echo "Successfully pushed to remote"
    return 0
  else
    local exit_code=$?
    echo "Failed to push to remote" >&2

    # Provide helpful error messages
    if [[ $exit_code -eq 128 ]]; then
      echo "This might be the first push. Try: juvy git push -u $remote_name $branch" >&2
    else
      echo "Check your authentication and network connection" >&2
      echo "For detailed error: juvy git push $remote_name $branch" >&2
    fi

    return $exit_code
  fi
}

_juvy_remote_push_auto() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"

  # Silent version of push for auto-push during backup
  if _juvy_git push "$remote_name" "$branch" >/dev/null 2>&1; then
    return 0
  else
    # Log the error but don't print to stderr (backup should continue)
    _juvy_log_error "Auto-push failed during backup"
    return 1
  fi
}

_juvy_remote_status() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"

  echo "Remote Configuration:"

  if [[ -n "$_JUVY_REMOTE_URL" ]]; then
    echo "   URL: $_JUVY_REMOTE_URL"
    echo "   Name: $remote_name"
    echo "   Auto-push: ${_JUVY_REMOTE_PUSH:-false}"
    echo ""

    # Check if remote is reachable
    if _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
      echo "Remote is reachable"

      # Check for unpushed commits
      local unpushed
      unpushed="$(_juvy_git log --oneline "$remote_name/$branch"..HEAD 2>/dev/null | wc -l)"
      unpushed="${unpushed#"${unpushed%%[![:space:]]*}"}"

      if [[ "$unpushed" -gt 0 ]]; then
        echo "$unpushed commit(s) waiting to be pushed"
      else
        echo "Local and remote are in sync"
      fi
    else
      echo "Remote is not reachable"
    fi
  else
    echo "   No remote configured"
    echo ""
    echo "Add a remote with: juvy remote <url>"
  fi
}

_juvy_validate_git_url() {
  local url="$1"

  # Basic URL validation
  case "$url" in
    git@*:*/*|https://*/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_juvy_update_config() {
  local key="$1"
  local value="$2"

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    grep -v "^$key=" "$_JUVY_CONFIG_FILE" > "$_JUVY_CONFIG_FILE.tmp" 2>/dev/null || touch "$_JUVY_CONFIG_FILE.tmp"
    mv "$_JUVY_CONFIG_FILE.tmp" "$_JUVY_CONFIG_FILE"
  fi

  # Add new key=value with robust quoting
  # Use single quotes for safety, but handle single quotes in the value
  if [[ "$value" == *"'"* ]]; then
    # Value contains single quotes, use double quotes with minimal escaping
    local escaped_value="${value//\\/\\\\}"    # Escape backslashes
    escaped_value="${escaped_value//\"/\\\"}"  # Escape double quotes
    escaped_value="${escaped_value//\$/\\\$}"  # Escape dollar signs
    escaped_value="${escaped_value//\`/\\\`}"  # Escape backticks
    echo "$key=\"$escaped_value\"" >> "$_JUVY_CONFIG_FILE"
  else
    # Value doesn't contain single quotes, use single quotes (safest)
    echo "$key='$value'" >> "$_JUVY_CONFIG_FILE"
  fi
}

_juvy_remove_config() {
  local key="$1"

  if [[ -f "$_JUVY_CONFIG_FILE" ]]; then
    grep -v "^$key=" "$_JUVY_CONFIG_FILE" > "$_JUVY_CONFIG_FILE.tmp" 2>/dev/null || touch "$_JUVY_CONFIG_FILE.tmp"
    mv "$_JUVY_CONFIG_FILE.tmp" "$_JUVY_CONFIG_FILE"
  fi
}

