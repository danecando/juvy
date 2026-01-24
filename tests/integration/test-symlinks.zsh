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

# Create actual file and symlink pointing to it
mkdir -p "$HOME/actual"
echo "actual content" > "$HOME/actual/real-file.txt"
ln -s "$HOME/actual/real-file.txt" "$HOME/.my-symlink"

# Add symlink to backup list
echo "~/.my-symlink" > "$JUVY_CONFIG_DIR/backup"

# Source juvy
source "$(dirname $0)/../../juvy.zsh"

# Run backup
juvy backup >/dev/null

BACKUP_PATH="$BACKUP_DIR$HOME/.my-symlink"

# Verify symlink exists in backup
assert_file_exists "$BACKUP_PATH"

# Verify it's a symlink (not a regular file)
if [[ ! -L "$BACKUP_PATH" ]]; then
  echo "Expected symlink in backup, got regular file" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "symlinks"
  exit 1
fi

# Verify symlink points to correct target
BACKUP_TARGET=$(readlink "$BACKUP_PATH")
ORIGINAL_TARGET=$(readlink "$HOME/.my-symlink")
if [[ "$BACKUP_TARGET" != "$ORIGINAL_TARGET" ]]; then
  echo "Symlink target mismatch: expected '$ORIGINAL_TARGET', got '$BACKUP_TARGET'" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "symlinks"
  exit 1
fi

# Delete symlink and restore
rm "$HOME/.my-symlink"

echo y | juvy restore >/dev/null

# Verify symlink is restored
assert_file_exists "$HOME/.my-symlink"

# Verify it's still a symlink after restore
if [[ ! -L "$HOME/.my-symlink" ]]; then
  echo "Expected symlink after restore, got regular file" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "symlinks"
  exit 1
fi

# Verify symlink still points correctly
RESTORED_TARGET=$(readlink "$HOME/.my-symlink")
if [[ "$RESTORED_TARGET" != "$ORIGINAL_TARGET" ]]; then
  echo "Restored symlink target mismatch: expected '$ORIGINAL_TARGET', got '$RESTORED_TARGET'" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "symlinks"
  exit 1
fi

cleanup_dir "$TEST_ROOT"

report_pass "symlinks"
