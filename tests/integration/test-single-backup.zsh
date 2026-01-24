#!/usr/bin/env zsh
set -e

# Load testing utilities
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

# Run backup
juvy backup >/dev/null

BACKUP_PATH="$BACKUP_DIR$HOME/.zshrc"

assert_file_exists "$BACKUP_PATH"
assert_files_identical "$HOME/.zshrc" "$BACKUP_PATH"

# Remove original and restore
rm "$HOME/.zshrc"

echo y | juvy restore >/dev/null

assert_file_exists "$HOME/.zshrc"
assert_files_identical "$HOME/.zshrc" "$BACKUP_PATH"

cleanup_dir "$TEST_ROOT"

report_pass "single-backup"
