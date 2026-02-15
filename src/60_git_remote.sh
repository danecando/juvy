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

  echo "Syncing and pushing to remote..."

  # Check if we have commits to push
  if ! _juvy_git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "No commits to push" >&2
    return 1
  fi

  if _juvy_remote_sync_and_push "false"; then
    echo "Successfully pushed to remote"
    return 0
  else
    local exit_code=$?
    echo "Failed to push to remote" >&2

    case "$exit_code" in
      3)
        echo "Remote history could not be reconciled automatically (rebase conflict)." >&2
        echo "Resolve conflicts in the backup repo, then run: juvy remote push" >&2
        echo "Useful commands: juvy git status, juvy git rebase --continue, juvy git rebase --abort" >&2
        ;;
      *)
        echo "Check your authentication and network connection" >&2
        echo "For detailed error: juvy git push $remote_name $branch" >&2
        ;;
    esac

    return $exit_code
  fi
}

_juvy_remote_push_auto() {
  # Silent version of sync + push for auto-push during backup
  if _juvy_remote_sync_and_push "true"; then
    return 0
  else
    local exit_code=$?
    if [[ "$exit_code" -eq 3 ]]; then
      _juvy_log_error "Auto-push failed: remote rebase conflict requires manual resolution"
    else
      _juvy_log_error "Auto-push failed during backup"
    fi
    return 1
  fi
}

_juvy_remote_status() {
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"
  local state_data state ahead behind

  echo "Remote Configuration:"

  if [[ -n "$_JUVY_REMOTE_URL" ]]; then
    echo "   URL: $_JUVY_REMOTE_URL"
    echo "   Name: $remote_name"
    echo "   Auto-push: ${_JUVY_REMOTE_PUSH:-false}"
    echo ""

    state_data="$(_juvy_remote_get_sync_state "$branch" "true")"
    state="${state_data%%|*}"
    state_data="${state_data#*|}"
    ahead="${state_data%%|*}"
    behind="${state_data#*|}"

    case "$state" in
      in_sync)
        echo "Remote is reachable"
        echo "Local and remote are in sync"
        ;;
      ahead)
        echo "Remote is reachable"
        echo "$ahead commit(s) waiting to be pushed"
        ;;
      behind)
        echo "Remote is reachable"
        echo "Local backup is behind remote by $behind commit(s)"
        echo "Run 'juvy remote push' to sync (juvy will rebase local commits automatically)"
        ;;
      diverged)
        echo "Remote is reachable"
        echo "Local and remote have diverged (ahead $ahead, behind $behind)"
        echo "Run 'juvy remote push' to auto-rebase and push"
        ;;
      no_remote_branch)
        echo "Remote is reachable"
        echo "Remote branch '$branch' does not exist yet"
        echo "Run 'juvy remote push' to create it"
        ;;
      no_local_commits)
        echo "Remote is reachable"
        echo "No local commits yet"
        ;;
      unreachable)
        echo "Remote is not reachable"
        ;;
      *)
        echo "Remote status unavailable"
        ;;
    esac
  else
    echo "   No remote configured"
    echo ""
    echo "Add a remote with: juvy remote <url>"
  fi
}

_juvy_remote_sync_and_push() {
  local quiet="${1:-false}"
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local branch="main"
  local remote_ref="$remote_name/$branch"
  local attempts=0
  local max_attempts=2

  while (( attempts < max_attempts )); do
    (( ++attempts ))

    if ! _juvy_git fetch "$remote_name" >/dev/null 2>&1; then
      [[ "$quiet" != "true" ]] && echo "Unable to fetch remote updates" >&2
      return 1
    fi

    if _juvy_git rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
      if ! _juvy_git merge-base --is-ancestor "$remote_ref" HEAD >/dev/null 2>&1; then
        if ! _juvy_git rebase "$remote_ref" >/dev/null 2>&1; then
          _juvy_git rebase --abort >/dev/null 2>&1 || true
          [[ "$quiet" != "true" ]] && echo "Automatic rebase failed due to conflicts" >&2
          return 3
        fi
      fi
    fi

    if _juvy_git push --set-upstream "$remote_name" "HEAD:$branch" >/dev/null 2>&1; then
      return 0
    fi
  done

  [[ "$quiet" != "true" ]] && echo "Push failed after retrying with remote sync" >&2
  return 1
}

_juvy_remote_get_sync_state() {
  local branch="${1:-main}"
  local do_fetch="${2:-true}"
  local remote_name="${_JUVY_REMOTE_NAME:-origin}"
  local remote_ref="$remote_name/$branch"
  local ahead=0
  local behind=0

  if [[ -z "$_JUVY_REMOTE_URL" ]]; then
    echo "no_remote|0|0"
    return 0
  fi

  if ! _juvy_git remote get-url "$remote_name" >/dev/null 2>&1; then
    echo "no_remote|0|0"
    return 0
  fi

  if ! _juvy_git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "no_local_commits|0|0"
    return 0
  fi

  if [[ "$do_fetch" == "true" ]]; then
    if ! _juvy_git ls-remote "$remote_name" >/dev/null 2>&1; then
      echo "unreachable|0|0"
      return 0
    fi
    if ! _juvy_git fetch "$remote_name" >/dev/null 2>&1; then
      echo "unreachable|0|0"
      return 0
    fi
  fi

  if ! _juvy_git rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
    ahead="$(_juvy_git rev-list --count HEAD 2>/dev/null || echo 0)"
    echo "no_remote_branch|$ahead|0"
    return 0
  fi

  ahead="$(_juvy_git rev-list --count "$remote_ref..HEAD" 2>/dev/null || echo 0)"
  behind="$(_juvy_git rev-list --count "HEAD..$remote_ref" 2>/dev/null || echo 0)"

  if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
    echo "diverged|$ahead|$behind"
  elif [[ "$ahead" -gt 0 ]]; then
    echo "ahead|$ahead|0"
  elif [[ "$behind" -gt 0 ]]; then
    echo "behind|0|$behind"
  else
    echo "in_sync|0|0"
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
