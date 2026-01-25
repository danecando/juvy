#!/usr/bin/env bats
# Tests for juvy init command

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "init creates config directory" {
  # Remove the config dir created by setup
  rm -rf "$JUVY_CONFIG_DIR"

  run juvy init </dev/null

  assert_dir_exists "$JUVY_CONFIG_DIR"
}

@test "init creates backup file with smart defaults" {
  # Remove the config files created by setup
  rm -rf "$JUVY_CONFIG_DIR"
  mkdir -p "$JUVY_CONFIG_DIR"
  echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"

  # Create some dotfiles that should be detected
  echo "test" > "$HOME/.bashrc"
  echo "test" > "$HOME/.zshrc"
  mkdir -p "$HOME/.config"

  # Re-source juvy to pick up the new environment
  source "$JUVY_SCRIPT"

  run juvy init </dev/null

  [ "$status" -eq 0 ]
  assert_file_exists "$JUVY_CONFIG_DIR/backup"
}

@test "init detects existing dotfiles" {
  rm -rf "$JUVY_CONFIG_DIR"
  mkdir -p "$JUVY_CONFIG_DIR"
  echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"

  # Create test dotfiles
  echo "bashrc content" > "$HOME/.bashrc"
  mkdir -p "$HOME/.config/nvim"
  echo "nvim config" > "$HOME/.config/nvim/init.lua"

  source "$JUVY_SCRIPT"

  run juvy init </dev/null

  [ "$status" -eq 0 ]
  # Check that backup file was created
  assert_file_exists "$JUVY_CONFIG_DIR/backup"
}

@test "init preserves existing backup file" {
  # Add entries to backup file
  add_to_backup_list "~/.existing-entry"

  run juvy init </dev/null

  # Original entry should still exist
  assert_file_contains "$JUVY_CONFIG_DIR/backup" "~/.existing-entry"
}

@test "re-init preserves config settings" {
  # Create a dotfile
  echo "test" > "$HOME/.bashrc"

  # First init with accept defaults (three newlines for iCloud/backup dir/remote prompts)
  printf '\n\n\n' | juvy init

  # Verify backup file exists
  assert_file_exists "$JUVY_CONFIG_DIR/backup"

  # Second init should preserve existing config
  printf '\n\n\n' | juvy init

  # Config should still have backup dir
  assert_file_contains "$JUVY_CONFIG_DIR/config" "JUVY_BACKUP_DIR"
}
