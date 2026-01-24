#!/usr/bin/env zsh
set -e

# Load testing utilities
source "$(dirname $0)/../test-framework.zsh"

TEST_ROOT=$(mktemp -d)
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

# Prepare juvy config
export JUVY_CONFIG_DIR="$HOME/.config/juvy"
mkdir -p "$JUVY_CONFIG_DIR"

BACKUP_DIR="$TEST_ROOT/backup"
mkdir -p "$BACKUP_DIR"
git init -b main "$BACKUP_DIR" >/dev/null 2>&1
git -C "$BACKUP_DIR" config user.name "Test User"
git -C "$BACKUP_DIR" config user.email "test@example.com"

echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"

# Create files with special characters in names
SPACE_FILE="$HOME/my config file.txt"
echo "content with spaces" > "$SPACE_FILE"

# Add file with spaces to backup list (must be quoted properly in backup file)
echo "~/my config file.txt" > "$JUVY_CONFIG_DIR/backup"

# Source juvy
source "$(dirname $0)/../../juvy.zsh"

# Run backup
juvy backup >/dev/null

# Verify file with spaces was backed up correctly
BACKUP_PATH="$BACKUP_DIR$HOME/my config file.txt"
assert_file_exists "$BACKUP_PATH"
assert_files_identical "$SPACE_FILE" "$BACKUP_PATH"

# Delete original and restore
rm "$SPACE_FILE"

echo y | juvy restore >/dev/null

# Verify file was restored with correct name
assert_file_exists "$SPACE_FILE"
assert_files_identical "$SPACE_FILE" "$BACKUP_PATH"

# Verify content is correct
RESTORED_CONTENT="$(cat "$SPACE_FILE")"
if [[ "$RESTORED_CONTENT" != "content with spaces" ]]; then
  echo "Content mismatch after restore" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "special-chars"
  exit 1
fi

cleanup_dir "$TEST_ROOT"

report_pass "special-chars"
