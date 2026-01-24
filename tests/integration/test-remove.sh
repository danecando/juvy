#!/usr/bin/env bash
set -e

source "$(dirname "$0")/../test-framework.sh"

TEST_ROOT=$(mktemp -d)
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

export JUVY_CONFIG_DIR="$HOME/.config/juvy"
mkdir -p "$JUVY_CONFIG_DIR"

BACKUP_DIR="$TEST_ROOT/backup"
mkdir -p "$BACKUP_DIR"
git init -b main "$BACKUP_DIR" >/dev/null 2>&1
git -C "$BACKUP_DIR" config user.name "Test User"
git -C "$BACKUP_DIR" config user.email "test@example.com"

echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"

# Create test files
echo "test1" > "$HOME/.testrc1"
echo "test2" > "$HOME/.testrc2"
mkdir -p "$HOME/.config/testdir"
echo "test3" > "$HOME/.config/testdir/file.txt"

# Add entries to backup file
printf '%s\n' '~/.testrc1' '~/.testrc2' '~/.config/testdir/' > "$JUVY_CONFIG_DIR/backup"

source "$(dirname "$0")/../../juvy.sh"

# Test 1: Verify initial state
line_count=$(wc -l < "$JUVY_CONFIG_DIR/backup")
line_count="${line_count#"${line_count%%[![:space:]]*}"}"  # trim whitespace
if [[ $line_count -ne 3 ]]; then
  echo "Expected 3 lines in backup file, got $line_count" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "remove"
  exit 1
fi

# Test 2: Remove a file
juvy remove '~/.testrc1' >/dev/null

# Verify file was removed from backup list
if grep -Fxq '~/.testrc1' "$JUVY_CONFIG_DIR/backup" 2>/dev/null; then
  echo "~/.testrc1 should have been removed from backup list" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "remove"
  exit 1
fi

# Verify other entries still exist
if ! grep -Fxq '~/.testrc2' "$JUVY_CONFIG_DIR/backup" 2>/dev/null; then
  echo "~/.testrc2 should still be in backup list" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "remove"
  exit 1
fi

# Test 3: Remove a directory (with trailing slash)
juvy remove '~/.config/testdir/' >/dev/null

if grep -Fxq '~/.config/testdir/' "$JUVY_CONFIG_DIR/backup" 2>/dev/null; then
  echo "~/.config/testdir/ should have been removed from backup list" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "remove"
  exit 1
fi

# Test 4: Remove non-existent path (should not error)
output=$(juvy remove '~/.nonexistent' 2>&1)
if [[ "$output" != *"not in backup list"* ]]; then
  echo "Expected 'not in backup list' message for non-existent path" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "remove"
  exit 1
fi

# Test 5: Verify only ~/.testrc2 remains
line_count=$(wc -l < "$JUVY_CONFIG_DIR/backup")
line_count="${line_count#"${line_count%%[![:space:]]*}"}"  # trim whitespace
if [[ $line_count -ne 1 ]]; then
  echo "Expected 1 line in backup file after removals, got $line_count" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "remove"
  exit 1
fi

cleanup_dir "$TEST_ROOT"
report_pass "remove"
