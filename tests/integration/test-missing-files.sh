#!/usr/bin/env bash
set -e

# Load testing utilities
source "$(dirname "$0")/../test-framework.sh"

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

# Create one file that exists
echo "existing content" > "$HOME/.existing-file"

# Create backup config with one existing and one missing file
cat > "$JUVY_CONFIG_DIR/backup" << 'EOF'
~/.existing-file
~/.missing-file
EOF

# Source juvy
source "$(dirname "$0")/../../juvy.sh"

# Run backup and capture output
OUTPUT=$(juvy backup 2>&1)
EXIT_CODE=$?

# Verify backup completes successfully (exit 0)
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "Backup should complete with exit 0 even with missing files, got $EXIT_CODE" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "missing-files"
  exit 1
fi

# Verify existing file was backed up
BACKUP_PATH="$BACKUP_DIR$HOME/.existing-file"
assert_file_exists "$BACKUP_PATH"
assert_files_identical "$HOME/.existing-file" "$BACKUP_PATH"

# Verify warning was emitted for missing file
if ! echo "$OUTPUT" | grep -q "not found"; then
  echo "Expected warning about missing file" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "missing-files"
  exit 1
fi

# Verify missing file was NOT created in backup
MISSING_BACKUP_PATH="$BACKUP_DIR$HOME/.missing-file"
if [[ -e "$MISSING_BACKUP_PATH" ]]; then
  echo "Missing file should not appear in backup" >&2
  cleanup_dir "$TEST_ROOT"
  report_fail "missing-files"
  exit 1
fi

cleanup_dir "$TEST_ROOT"

report_pass "missing-files"
