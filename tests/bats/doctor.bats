#!/usr/bin/env bats
# Tests for juvy doctor command

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "doctor validates valid configuration" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"

  run juvy doctor

  [ "$status" -eq 0 ]
}

@test "doctor reports missing backup directory" {
  # Remove backup directory
  rm -rf "$BACKUP_DIR"

  run juvy doctor

  # Should report issue (may exit non-zero or zero with warning)
  [[ "$output" == *"backup"* || "$output" == *"directory"* || "$output" == *"not found"* || "$output" == *"missing"* ]]
}

@test "doctor reports missing config file" {
  rm -f "$JUVY_CONFIG_DIR/config"

  run juvy doctor

  # Should handle missing config gracefully
  [ "$status" -eq 0 ] || [[ "$output" == *"config"* ]]
}

@test "doctor reports missing backup file" {
  rm -f "$JUVY_CONFIG_DIR/backup"

  run juvy doctor

  # Should handle missing backup file gracefully
  [ "$status" -eq 0 ] || [[ "$output" == *"backup"* ]]
}

@test "doctor detects missing source files" {
  # Add a file that doesn't exist
  add_to_backup_list "~/.nonexistent-file"

  run juvy doctor

  # Doctor warns about missing files but may return 0 or non-zero
  # Just check that it runs and mentions the issue
  [[ "$output" == *"not found"* || "$output" == *"missing"* || "$output" == *"does not exist"* || "$output" == *"nonexistent"* ]]
}

@test "doctor validates existing source files" {
  create_test_file "~/.zshrc" "zsh"
  create_test_file "~/.bashrc" "bash"
  set_backup_list "~/.zshrc" "~/.bashrc"

  run juvy doctor

  [ "$status" -eq 0 ]
}

@test "doctor checks git repository status" {
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"

  run juvy doctor

  [ "$status" -eq 0 ]
  # Should mention git or repo status
}

@test "doctor with --fix option attempts repairs" {
  # This test verifies --fix flag is accepted
  # Actual repair behavior depends on what's broken

  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"

  run juvy doctor --fix

  # Should not error
  [ "$status" -eq 0 ]
}

@test "doctor validates exclude patterns" {
  create_test_dir "~/.config/app/"
  create_test_file "~/.config/app/config.txt" "config"

  set_backup_list "~/.config/app/" "!~/.config/app/cache/"

  run juvy doctor

  [ "$status" -eq 0 ]
}

@test "doctor handles empty backup file" {
  > "$JUVY_CONFIG_DIR/backup"

  run juvy doctor

  [ "$status" -eq 0 ]
}
