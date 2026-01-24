#!/usr/bin/env bash
set -e

# Test filter generation and exclude patterns
# Verifies that:
# 1. Filter files are generated with correct rule ordering
# 2. Exclude patterns (!path) block files from being backed up
# 3. Directory excludes work correctly

echo "DEBUG: Starting test, \$0=$0" >&2
echo "DEBUG: dirname=\$(dirname \"\$0\")=$(dirname "$0")" >&2
echo "DEBUG: PWD=$PWD" >&2

source "$(dirname "$0")/../test-framework.sh"
echo "DEBUG: Sourced test-framework.sh" >&2

TEST_ROOT=$(mktemp -d)
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

# Create test directory structure:
# ~/.config/nvim/
#   init.lua
#   lua/
#     plugins.lua
#   undo/           <- should be excluded
#     file1.undo
#     file2.undo
mkdir -p "$HOME/.config/nvim/lua"
mkdir -p "$HOME/.config/nvim/undo"
echo "-- init.lua" > "$HOME/.config/nvim/init.lua"
echo "-- plugins.lua" > "$HOME/.config/nvim/lua/plugins.lua"
echo "undo1" > "$HOME/.config/nvim/undo/file1.undo"
echo "undo2" > "$HOME/.config/nvim/undo/file2.undo"

# Also create a simple dotfile
echo "export PATH=/usr/bin" > "$HOME/.zshrc"

# Prepare juvy config - only JUVY_CONFIG_DIR env var is needed
export JUVY_CONFIG_DIR="$HOME/.config/juvy"
mkdir -p "$JUVY_CONFIG_DIR"

BACKUP_DIR="$TEST_ROOT/backup"
mkdir -p "$BACKUP_DIR"
git init -b main "$BACKUP_DIR" >/dev/null 2>&1
git -C "$BACKUP_DIR" config user.name "Test User"
git -C "$BACKUP_DIR" config user.email "test@example.com"

echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"

# Create backup file with include and exclude patterns
cat > "$JUVY_CONFIG_DIR/backup" << 'EOF'
~/.zshrc
~/.config/nvim/
!~/.config/nvim/undo/
EOF

# Source juvy
source "$(dirname "$0")/../../juvy.sh"

# Run backup
juvy backup >/dev/null

# Verify expected files ARE backed up
BACKUP_ZSHRC="$BACKUP_DIR$HOME/.zshrc"
BACKUP_INIT="$BACKUP_DIR$HOME/.config/nvim/init.lua"
BACKUP_PLUGINS="$BACKUP_DIR$HOME/.config/nvim/lua/plugins.lua"

if [[ ! -f "$BACKUP_ZSHRC" ]]; then
  report_fail "filter-excludes: .zshrc should be backed up"
  cleanup_dir "$TEST_ROOT"
  exit 1
fi

if [[ ! -f "$BACKUP_INIT" ]]; then
  report_fail "filter-excludes: nvim/init.lua should be backed up"
  cleanup_dir "$TEST_ROOT"
  exit 1
fi

if [[ ! -f "$BACKUP_PLUGINS" ]]; then
  report_fail "filter-excludes: nvim/lua/plugins.lua should be backed up"
  cleanup_dir "$TEST_ROOT"
  exit 1
fi

# Verify excluded files are NOT backed up
BACKUP_UNDO="$BACKUP_DIR$HOME/.config/nvim/undo"

if [[ -d "$BACKUP_UNDO" ]]; then
  report_fail "filter-excludes: nvim/undo/ directory should NOT be backed up"
  cleanup_dir "$TEST_ROOT"
  exit 1
fi

# Verify content matches
assert_files_identical "$HOME/.zshrc" "$BACKUP_ZSHRC"
assert_files_identical "$HOME/.config/nvim/init.lua" "$BACKUP_INIT"

cleanup_dir "$TEST_ROOT"

report_pass "filter-excludes"
