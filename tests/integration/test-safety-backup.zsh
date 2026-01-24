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

# Create initial file with original content
ORIGINAL_CONTENT="original content version 1"
echo "$ORIGINAL_CONTENT" > "$HOME/.testfile"

# Add file to backup list
echo "~/.testfile" > "$JUVY_CONFIG_DIR/backup"

# Source juvy
source "$(dirname $0)/../../juvy.zsh"

# Run initial backup
juvy backup >/dev/null

# Modify the file
MODIFIED_CONTENT="modified content version 2"
echo "$MODIFIED_CONTENT" > "$HOME/.testfile"

# Verify file was modified
if [[ "$(cat "$HOME/.testfile")" != "$MODIFIED_CONTENT" ]]; then
  echo "File modification failed" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "safety-backup"
  exit 1
fi

# Run restore with 'y' confirmation
echo y | juvy restore >/dev/null

# Verify safety backup directory was created
SAFETY_BACKUP_BASE="$JUVY_CONFIG_DIR/safety-backup"
if [[ ! -d "$SAFETY_BACKUP_BASE" ]]; then
  echo "Safety backup directory was not created" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "safety-backup"
  exit 1
fi

# Find the timestamped safety backup directory
SAFETY_DIRS=("$SAFETY_BACKUP_BASE"/*(/N))
if [[ ${#SAFETY_DIRS[@]} -eq 0 ]]; then
  echo "No timestamped safety backup directory found" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "safety-backup"
  exit 1
fi

# Use most recent safety backup
SAFETY_DIR="${SAFETY_DIRS[-1]}"

# Verify safety backup contains the modified version (pre-restore state)
# Find the actual safety backup file (path includes the tilde from entry)
SAFETY_FILE=$(find "$SAFETY_DIR" -name ".testfile" -type f 2>/dev/null | head -1)
if [[ -z "$SAFETY_FILE" || ! -f "$SAFETY_FILE" ]]; then
  echo "Safety backup file not found in $SAFETY_DIR" >&2
  echo "Contents: $(ls -laR "$SAFETY_DIR" 2>&1)" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "safety-backup"
  exit 1
fi

SAFETY_CONTENT="$(cat "$SAFETY_FILE")"
if [[ "$SAFETY_CONTENT" != "$MODIFIED_CONTENT" ]]; then
  echo "Safety backup should contain modified version" >&2
  echo "Expected: $MODIFIED_CONTENT" >&2
  echo "Got: $SAFETY_CONTENT" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "safety-backup"
  exit 1
fi

# Verify restored file matches original (from backup)
RESTORED_CONTENT="$(cat "$HOME/.testfile")"
if [[ "$RESTORED_CONTENT" != "$ORIGINAL_CONTENT" ]]; then
  echo "Restored file should match original backup content" >&2
  echo "Expected: $ORIGINAL_CONTENT" >&2
  echo "Got: $RESTORED_CONTENT" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "safety-backup"
  exit 1
fi

cleanup_dir "$TEST_ROOT"

report_pass "safety-backup"
