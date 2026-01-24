#!/usr/bin/env bats
# Tests for filenames with special characters

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "backup file with spaces in name" {
  create_test_file "~/my config file.txt" "content with spaces"
  add_to_backup_list "~/my config file.txt"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/my config file.txt"
  assert_backup_matches_source "~/my config file.txt"
}

@test "restore file with spaces in name" {
  create_test_file "~/my config file.txt" "content with spaces"
  add_to_backup_list "~/my config file.txt"

  juvy backup

  rm "$HOME/my config file.txt"
  run_restore_confirmed

  assert_file_exists "$HOME/my config file.txt"

  local content
  content=$(cat "$HOME/my config file.txt")
  [ "$content" = "content with spaces" ]
}

@test "backup directory with spaces in name" {
  create_test_dir "~/My Documents/"
  create_test_file "~/My Documents/file.txt" "document content"
  add_to_backup_list "~/My Documents/"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_dir_backed_up "~/My Documents/"
  assert_file_backed_up "~/My Documents/file.txt"
}

@test "backup file with special shell characters" {
  # Test with characters that could be problematic in shell
  create_test_file "~/.config-test" "config"
  create_test_file "~/file_with_underscore" "underscore"
  add_to_backup_list "~/.config-test"
  add_to_backup_list "~/file_with_underscore"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/.config-test"
  assert_file_backed_up "~/file_with_underscore"
}

@test "backup file with dots in name" {
  create_test_file "~/.file.with.dots.txt" "dotted content"
  add_to_backup_list "~/.file.with.dots.txt"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/.file.with.dots.txt"
}

@test "backup deeply nested path with spaces" {
  create_test_dir "~/my folder/sub folder/"
  create_test_file "~/my folder/sub folder/deep file.txt" "deep content"
  add_to_backup_list "~/my folder/"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_dir_backed_up "~/my folder/"
  assert_file_backed_up "~/my folder/sub folder/deep file.txt"
}

@test "restore preserves content of file with spaces" {
  local content="line 1
line 2 with spaces
line 3"

  create_test_file "~/spaced file.txt" "$content"
  add_to_backup_list "~/spaced file.txt"

  juvy backup

  rm "$HOME/spaced file.txt"
  run_restore_confirmed

  local restored_content
  restored_content=$(cat "$HOME/spaced file.txt")
  [ "$restored_content" = "$content" ]
}
