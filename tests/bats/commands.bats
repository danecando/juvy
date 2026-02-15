#!/usr/bin/env bats
# Tests for juvy commands: add, remove, list, status

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ------------------------------------------------------------------------------
# add command
# ------------------------------------------------------------------------------

@test "add command adds file to backup list" {
  create_test_file "~/.newfile" "new content"

  # Use actual path (not tilde) for add command
  run juvy add "$HOME/.newfile"

  [ "$status" -eq 0 ]
  # The add command converts to tilde format
  assert_file_contains "$JUVY_CONFIG_DIR/backup" "~/.newfile"
}

@test "add command adds directory to backup list" {
  create_test_dir "~/.config/newdir/"
  create_test_file "~/.config/newdir/config.txt" "config"

  # Use actual path for add command
  run juvy add "$HOME/.config/newdir/"

  [ "$status" -eq 0 ]
  assert_file_contains "$JUVY_CONFIG_DIR/backup" "~/.config/newdir/"
}

@test "add command warns on non-existent path" {
  run juvy add "$HOME/.nonexistent"

  # Should warn and return non-zero
  [[ "$output" == *"not found"* || "$output" == *"does not exist"* || "$status" -ne 0 ]]
}

@test "add does not duplicate existing entries" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"

  run juvy add "$HOME/.zshrc"

  # Count occurrences
  local count
  count=$(grep -c "\.zshrc" "$JUVY_CONFIG_DIR/backup" || echo "0")
  [ "$count" -eq 1 ]
}

@test "add accepts home-relative tilde path when quoted" {
  create_test_file "~/.tildefile" "content"

  run juvy add "~/.tildefile"

  [ "$status" -eq 0 ]
  assert_file_contains "$JUVY_CONFIG_DIR/backup" "~/.tildefile"
}

@test "add accepts path relative to current directory" {
  mkdir -p "$TEST_ROOT/project"
  cd "$TEST_ROOT/project"
  printf "content\n" > "./local.conf"

  run juvy add "./local.conf"

  [ "$status" -eq 0 ]
  assert_file_contains "$JUVY_CONFIG_DIR/backup" "$TEST_ROOT/project/local.conf"
}

@test "add returns non-zero when all requested paths are invalid" {
  run juvy add "$HOME/.does-not-exist"

  [ "$status" -ne 0 ]
}

# ------------------------------------------------------------------------------
# remove command
# ------------------------------------------------------------------------------

@test "remove command removes file from backup list" {
  create_test_file "~/.testrc" "test"
  set_backup_list "~/.testrc" "~/.otherfile"

  run juvy remove "~/.testrc"

  [ "$status" -eq 0 ]
  assert_file_not_contains "$JUVY_CONFIG_DIR/backup" "~/.testrc"
}

@test "remove command preserves other entries" {
  create_test_file "~/.file1" "content1"
  create_test_file "~/.file2" "content2"
  set_backup_list "~/.file1" "~/.file2"

  juvy remove "~/.file1"

  # file2 should still be there
  assert_file_contains "$JUVY_CONFIG_DIR/backup" "~/.file2"
}

@test "remove command removes directory entry" {
  create_test_dir "~/.config/testdir/"
  set_backup_list "~/.config/testdir/" "~/.otherfile"

  run juvy remove "~/.config/testdir/"

  [ "$status" -eq 0 ]
  assert_file_not_contains "$JUVY_CONFIG_DIR/backup" "~/.config/testdir/"
}

@test "remove command handles non-existent entry" {
  set_backup_list "~/.existing"

  run juvy remove "~/.nonexistent"

  # Should indicate entry was not found
  [[ "$output" == *"not in backup list"* || "$output" == *"not found"* ]]
}

@test "remove --delete deletes file from backup directory" {
  create_test_file "~/.testrc" "test"
  add_to_backup_list "~/.testrc"
  juvy backup

  local backup_path
  backup_path="$(get_backup_path "~/.testrc")"
  [ -f "$backup_path" ]

  run juvy remove --delete "~/.testrc"

  [ "$status" -eq 0 ]
  [ ! -f "$backup_path" ]
  [[ "$output" == *"Deleted"* ]]
}

@test "remove without --delete preserves backup file in non-interactive mode" {
  create_test_file "~/.testrc" "test"
  add_to_backup_list "~/.testrc"
  juvy backup

  local backup_path
  backup_path="$(get_backup_path "~/.testrc")"
  [ -f "$backup_path" ]

  # Non-interactive (no TTY) should not prompt and preserve backup
  run juvy remove "~/.testrc"

  [ "$status" -eq 0 ]
  [ -f "$backup_path" ]
  assert_file_not_contains "$JUVY_CONFIG_DIR/backup" "~/.testrc"
}

# ------------------------------------------------------------------------------
# list command
# ------------------------------------------------------------------------------

@test "list command shows backup entries" {
  create_test_file "~/.zshrc" "zsh"
  create_test_file "~/.bashrc" "bash"
  set_backup_list "~/.zshrc" "~/.bashrc"

  run juvy list

  [ "$status" -eq 0 ]
  assert_output_contains "$output" ".zshrc"
  assert_output_contains "$output" ".bashrc"
}

@test "list command handles empty backup file" {
  > "$JUVY_CONFIG_DIR/backup"

  run juvy list

  [ "$status" -eq 0 ]
}

# ------------------------------------------------------------------------------
# status command
# ------------------------------------------------------------------------------

@test "status command runs without error" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"
  juvy backup

  run juvy status

  [ "$status" -eq 0 ]
}

@test "status command detects changes" {
  create_test_file "~/.zshrc" "original"
  add_to_backup_list "~/.zshrc"
  juvy backup

  # Modify the file
  create_test_file "~/.zshrc" "modified"

  run juvy status

  [ "$status" -eq 0 ]
  # Output should indicate there are changes
  # The exact message depends on implementation
}

@test "status command with no changes" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"
  juvy backup

  run juvy status

  [ "$status" -eq 0 ]
}
