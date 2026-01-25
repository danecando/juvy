#!/usr/bin/env bash
# juvy installer script

set -e

JUVY_DIR="$HOME/.juvy"
JUVY_SCRIPT="$JUVY_DIR/juvy"
JUVY_REPO_BASE="https://raw.githubusercontent.com/danecando/juvy/main"

print_error() {
  echo "$1" >&2
}

print_success() {
  echo "$1"
}

print_info() {
  echo "$1"
}

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
  print_error "juvy requires bash or zsh. Your current shell is $SHELL"
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  print_error "juvy requires rsync, which was not found"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  print_error "juvy requires git, which was not found"
  exit 1
fi

# Check for existing installation
if [[ -d "$JUVY_DIR" ]]; then
  print_info "Updating existing juvy installation..."
fi

# Create juvy directory
print_info "Creating juvy directory..."
mkdir -p "$JUVY_DIR"

# Download juvy script
print_info "Downloading juvy..."
if curl -sSL "$JUVY_REPO_BASE/juvy.sh" -o "$JUVY_SCRIPT"; then
  print_success "Downloaded juvy to $JUVY_SCRIPT"
else
  print_error "Failed to download juvy"
  exit 1
fi

# Make it executable
chmod +x "$JUVY_SCRIPT"

# Detect the appropriate rc file
RC_FILE="$(detect_rc_file)"

# Add to PATH in rc file if not already there
if ! grep -q '\.juvy' "$RC_FILE" 2>/dev/null; then
  print_info "Adding juvy to PATH in $RC_FILE..."
  {
    echo ""
    echo "# juvy dotfile backup tool"
    echo 'export PATH="$HOME/.juvy:$PATH"'
    echo '( juvy backup >/dev/null 2>&1 & )'
  } >> "$RC_FILE"
  print_success "Added juvy to PATH in $RC_FILE"
else
  print_info "juvy already in $RC_FILE"
fi

# Add to current PATH for immediate use
export PATH="$JUVY_DIR:$PATH"

# Check for existing configuration
if [[ -f "$HOME/.config/juvy/config" ]] && [[ -f "$HOME/.config/juvy/backup" ]]; then
  print_success "Existing juvy configuration found"
  print_info "Run 'juvy backup' to backup your files"
else
  echo ""
  print_info "Setup complete! Next steps:"
  echo "  1. Restart your shell"
  echo "  2. Configure juvy: juvy init"
  echo "  3. Start backing up: juvy backup"
fi

echo ""
print_success "juvy installation complete!"
print_info "Restart your shell"
