#!/usr/bin/env bats
# Tests for backup locking behavior

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "backup skips when lock already exists" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"

  mkdir -p "$JUVY_CONFIG_DIR/locks/backup.lock"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_not_backed_up "~/.zshrc"
}

@test "backup proceeds after lock is removed" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"

  mkdir -p "$JUVY_CONFIG_DIR/locks/backup.lock"
  run juvy backup
  [ "$status" -eq 0 ]

  rm -rf "$JUVY_CONFIG_DIR/locks/backup.lock"
  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/.zshrc"
}
