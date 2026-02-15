#!/usr/bin/env bash
# juvy installer script

set -e

JUVY_DIR="$HOME/.juvy"
JUVY_SCRIPT="$JUVY_DIR/juvy"
JUVY_REPO_BASE="https://raw.githubusercontent.com/danecando/juvy/main"
JUVY_SHELL_INTEGRATION_START="# >>> juvy auto backup >>>"
JUVY_SHELL_INTEGRATION_END="# <<< juvy auto backup <<<"

# Detect current shell name
detect_shell_name() {
  local current_shell="${SHELL##*/}"
  if [[ -n "$current_shell" ]]; then
    echo "$current_shell"
  else
    echo "unknown"
  fi
}

# Detect rc file for a given shell
detect_rc_file() {
  local shell_name="$1"

  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

remove_managed_block_from_file() {
  local file_path="$1"
  local start_marker="$2"
  local end_marker="$3"
  local temp_file

  [[ -f "$file_path" ]] || return 0

  temp_file="$file_path.tmp"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { in_block=1; next }
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

write_shell_integration_block() {
  local rc_file="$1"

  cat >> "$rc_file" << EOF
$JUVY_SHELL_INTEGRATION_START
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
$JUVY_SHELL_INTEGRATION_END
EOF
}

ensure_bash_profile_bridge() {
  local bash_profile="$HOME/.bash_profile"
  local bridge_start="# >>> juvy bashrc bridge >>>"
  local bridge_end="# <<< juvy bashrc bridge <<<"

  touch "$bash_profile" 2>/dev/null || return 1
  remove_managed_block_from_file "$bash_profile" "$bridge_start" "$bridge_end" >/dev/null 2>&1 || true

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

upsert_shell_integration() {
  local shell_name="$1"
  local rc_file

  rc_file="$(detect_rc_file "$shell_name")"
  touch "$rc_file" 2>/dev/null || return 1

  remove_managed_block_from_file "$rc_file" "$JUVY_SHELL_INTEGRATION_START" "$JUVY_SHELL_INTEGRATION_END" >/dev/null 2>&1 || true

  if [[ -s "$rc_file" ]]; then
    printf '\n' >> "$rc_file"
  fi

  write_shell_integration_block "$rc_file"

  if [[ "$shell_name" == "bash" ]]; then
    ensure_bash_profile_bridge || return 1
  fi

  return 0
}

# Check prerequisites
if ! command -v bash >/dev/null 2>&1; then
  echo "juvy requires bash" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "juvy requires rsync" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "juvy requires git" >&2
  exit 1
fi

is_update=false
if [[ -d "$JUVY_DIR" ]]; then
  is_update=true
fi

# Create juvy directory and download
mkdir -p "$JUVY_DIR"

if ! curl -sSL "$JUVY_REPO_BASE/juvy.sh" -o "$JUVY_SCRIPT"; then
  echo "Failed to download juvy" >&2
  exit 1
fi

chmod +x "$JUVY_SCRIPT"

# Configure shell integration
current_shell="$(detect_shell_name)"
target_shell="$current_shell"
if [[ "$target_shell" != "zsh" && "$target_shell" != "bash" ]]; then
  if [[ -f "$HOME/.zshrc" ]]; then
    target_shell="zsh"
  else
    target_shell="bash"
  fi
  echo "Detected shell '$current_shell'. Configuring $target_shell integration."
fi

if ! upsert_shell_integration "$target_shell"; then
  echo "Failed to configure shell integration for $target_shell" >&2
  exit 1
fi

# Add to current PATH for immediate use
export PATH="$JUVY_DIR:$PATH"

if [[ "$is_update" == "true" ]]; then
  echo "juvy updated!"
elif [[ -f "$HOME/.config/juvy/config" ]] && [[ -f "$HOME/.config/juvy/backup" ]]; then
  echo "juvy installed!"
else
  echo "juvy installed! Run 'juvy init' to get started."
fi
