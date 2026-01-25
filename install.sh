#!/usr/bin/env bash
# juvy installer script

set -e

JUVY_DIR="$HOME/.juvy"
JUVY_SCRIPT="$JUVY_DIR/juvy"
JUVY_REPO_BASE="https://raw.githubusercontent.com/danecando/juvy/main"

# Detect current shell for rc file
detect_rc_file() {
  local current_shell="${SHELL##*/}"
  case "$current_shell" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

# Check prerequisites
current_shell="${SHELL##*/}"
if [[ "$current_shell" != "bash" && "$current_shell" != "zsh" ]]; then
  echo "juvy requires bash or zsh" >&2
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

# Add to PATH in rc file if not already there
RC_FILE="$(detect_rc_file)"
if ! grep -q '\.juvy' "$RC_FILE" 2>/dev/null; then
  {
    echo ""
    echo "# juvy dotfile backup tool"
    echo 'export PATH="$HOME/.juvy:$PATH"'
    echo '( juvy backup >/dev/null 2>&1 & )'
  } >> "$RC_FILE"
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
