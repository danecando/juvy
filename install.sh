#!/usr/bin/env zsh
# juvy installer script

set -e

JUVY_DIR="$HOME/.juvy"
JUVY_SCRIPT="$JUVY_DIR/juvy.zsh"
JUVY_REPO_BASE="https://raw.githubusercontent.com/danecando/juvy/main"

print_error() {
  print "❌ $1" >&2
}

print_success() {
  print "✅ $1"
}

print_info() {
  print "ℹ️  $1"
}

# Check prerequisites
if [[ "$SHELL" != *"zsh"* ]]; then
  print_error "juvy requires zsh. Your current shell is $SHELL"
  exit 1
fi

if ! (( $+commands[rsync] )); then
  print_error "juvy requires rsync, which was not found"
  exit 1
fi

if ! (( $+commands[git] )); then
  print_error "juvy requires git, which was not found"
  exit 1
fi

# Check for existing installation
if [[ -d "$JUVY_DIR" ]]; then
  print_info "Existing juvy installation found at $JUVY_DIR"
  print "Do you want to update it? [y/N] "
  read -r "update?"
  if [[ "$update" != "y" ]]; then
    print_info "Installation cancelled"
    exit 0
  fi
fi

# Create juvy directory
print_info "Creating juvy directory..."
mkdir -p "$JUVY_DIR"

# Download juvy script
print_info "Downloading juvy..."
if curl -sSL "$JUVY_REPO_BASE/juvy/juvy.zsh" -o "$JUVY_SCRIPT"; then
  print_success "Downloaded juvy to $JUVY_SCRIPT"
else
  print_error "Failed to download juvy"
  exit 1
fi

# Make it executable
chmod +x "$JUVY_SCRIPT"

# Add to .zshrc if not already there
if ! grep -q "source.*\.juvy/juvy\.zsh" "$HOME/.zshrc" 2>/dev/null; then
  print_info "Adding juvy to .zshrc..."
  {
    echo ""
    echo "# juvy dotfile backup tool"
    echo "source $JUVY_SCRIPT"
  } >> "$HOME/.zshrc"
  print_success "Added juvy to .zshrc"
else
  print_info "juvy already in .zshrc"
fi

# Source juvy for immediate use
source "$JUVY_SCRIPT"

# Check for existing configuration
if [[ -f "$HOME/.config/juvy/config" ]] && [[ -f "$HOME/.config/juvy/backup" ]]; then
  print_success "Existing juvy configuration found"
  print_info "Run 'juvy backup' to backup your files"
else
  print ""
  print_info "Setup complete! Next steps:"
  print "  1. Restart your shell or run: source ~/.zshrc"
  print "  2. Configure juvy: juvy init"
  print "  3. Start backing up: juvy backup"
fi

print ""
print_success "juvy installation complete!"
print_info "Restart your shell or run: source ~/.zshrc"
