#!/usr/bin/env bats
# Tests for juvy restore command

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "restore recovers deleted file" {
  create_test_file "~/.zshrc" "original content"
  add_to_backup_list "~/.zshrc"

  # Backup and then delete the original
  juvy backup
  rm "$HOME/.zshrc"

  # Restore
  run_restore_confirmed

  # File should be restored
  assert_file_exists "$HOME/.zshrc"
  assert_backup_matches_source "~/.zshrc"
}

@test "restore creates safety backup" {
  create_test_file "~/.testfile" "original content"
  add_to_backup_list "~/.testfile"

  # Initial backup
  juvy backup

  # Modify the file
  create_test_file "~/.testfile" "modified content"

  # Restore (should create safety backup of modified version)
  run_restore_confirmed

  # Safety backup directory should exist
  local safety_base="$JUVY_CONFIG_DIR/safety-backup"
  assert_dir_exists "$safety_base"

  # Find the safety backup file
  local safety_file
  safety_file=$(find "$safety_base" -name ".testfile" -type f 2>/dev/null | head -1)
  [ -n "$safety_file" ]

  # Safety backup should have the modified content
  local safety_content
  safety_content=$(cat "$safety_file")
  [ "$safety_content" = "modified content" ]

  # Restored file should have original content
  local restored_content
  restored_content=$(cat "$HOME/.testfile")
  [ "$restored_content" = "original content" ]
}

@test "restore --dry-run shows changes without modifying files" {
  create_test_file "~/.zshrc" "original content"
  add_to_backup_list "~/.zshrc"

  juvy backup

  # Modify the file
  create_test_file "~/.zshrc" "modified content"

  # Run dry-run restore
  run juvy restore --dry-run

  [ "$status" -eq 0 ]

  # File should NOT have been changed
  local current_content
  current_content=$(cat "$HOME/.zshrc")
  [ "$current_content" = "modified content" ]

  # Output should mention dry-run
  [[ "$output" == *"dry-run"* || "$output" == *"Dry-run"* ]]
}

@test "restore directory" {
  create_test_dir "~/.config/nvim/"
  create_test_file "~/.config/nvim/init.lua" "nvim config"
  add_to_backup_list "~/.config/nvim/"

  juvy backup

  # Remove directory
  rm -rf "$HOME/.config/nvim"

  run_restore_confirmed

  # Directory and files should be restored
  assert_dir_exists "$HOME/.config/nvim"
  assert_file_exists "$HOME/.config/nvim/init.lua"
}

@test "restore preserves symlinks" {
  # Create actual file and symlink
  mkdir -p "$HOME/actual"
  echo "actual content" > "$HOME/actual/real-file.txt"
  create_symlink "$HOME/actual/real-file.txt" "~/.my-symlink"
  add_to_backup_list "~/.my-symlink"

  juvy backup

  # Get original target
  local original_target
  original_target=$(readlink "$HOME/.my-symlink")

  # Remove and restore
  rm "$HOME/.my-symlink"
  run_restore_confirmed

  # Should be a symlink with same target
  assert_is_symlink "$HOME/.my-symlink"
  assert_symlink_target "$HOME/.my-symlink" "$original_target"
}

@test "restore with empty backup handles gracefully" {
  > "$JUVY_CONFIG_DIR/backup"

  # Dry-run with empty backup - should not fail catastrophically
  run juvy restore --dry-run

  # May succeed or warn, but shouldn't crash
  # The actual behavior depends on juvy's implementation
  [[ "$status" -eq 0 || "$output" == *"nothing"* || "$output" == *"empty"* || "$output" == *"No"* ]]
}
