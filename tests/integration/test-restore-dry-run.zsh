#!/usr/bin/env zsh
set -e

# Test restore --dry-run functionality
# Verifies that dry-run mode shows what would be restored without making changes

source "$(dirname $0)/../test-framework.zsh"

TEST_ROOT=$(mktemp -d)
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

FIXTURES_DIR="$(dirname $0)/../fixtures"

# Copy fixture dotfile
mkdir -p "$HOME"
cp "$FIXTURES_DIR/sample-dotfiles/.zshrc" "$HOME/.zshrc"

# Prepare juvy config - only JUVY_CONFIG_DIR env var is needed
export JUVY_CONFIG_DIR="$HOME/.config/juvy"
mkdir -p "$JUVY_CONFIG_DIR"

BACKUP_DIR="$TEST_ROOT/backup"
mkdir -p "$BACKUP_DIR"
git init -b main "$BACKUP_DIR" >/dev/null 2>&1
git -C "$BACKUP_DIR" config user.name "Test User"
git -C "$BACKUP_DIR" config user.email "test@example.com"

echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"
echo "~/.zshrc" > "$JUVY_CONFIG_DIR/backup"

# Source juvy
source "$(dirname $0)/../../juvy.zsh"

# Run backup first
juvy backup >/dev/null

# Modify the source file
echo "# Modified content" >> "$HOME/.zshrc"

# Save the current content of the file
BEFORE_CONTENT=$(cat "$HOME/.zshrc")

# Run restore with --dry-run
OUTPUT=$(juvy restore --dry-run 2>&1)

# The file should NOT have been changed (still has modified content)
AFTER_CONTENT=$(cat "$HOME/.zshrc")

if [[ "$BEFORE_CONTENT" != "$AFTER_CONTENT" ]]; then
  report_fail "restore-dry-run: file should not be modified in dry-run mode"
  cleanup_dir "$TEST_ROOT"
  exit 1
fi

# Output should mention dry-run
if [[ "$OUTPUT" != *"dry-run"* && "$OUTPUT" != *"Dry-run"* ]]; then
  report_fail "restore-dry-run: output should mention dry-run mode"
  cleanup_dir "$TEST_ROOT"
  exit 1
fi

cleanup_dir "$TEST_ROOT"

report_pass "restore-dry-run"
