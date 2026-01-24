#!/usr/bin/env bats
# Tests for juvy backup command

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "backup single file" {
  create_test_file "~/.zshrc" "export PATH=/usr/bin"
  add_to_backup_list "~/.zshrc"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/.zshrc"
  assert_backup_matches_source "~/.zshrc"
}

@test "backup directory" {
  create_test_dir "~/.config/nvim/"
  create_test_file "~/.config/nvim/init.lua" "-- nvim config"
  create_test_file "~/.config/nvim/lua/plugins.lua" "-- plugins"
  add_to_backup_list "~/.config/nvim/"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_dir_backed_up "~/.config/nvim/"
  assert_file_backed_up "~/.config/nvim/init.lua"
  assert_file_backed_up "~/.config/nvim/lua/plugins.lua"
}

@test "backup creates git commit" {
  create_test_file "~/.zshrc" "test content"
  add_to_backup_list "~/.zshrc"

  run juvy backup

  [ "$status" -eq 0 ]

  # Check that a commit was created
  local commit_count
  commit_count=$(git -C "$BACKUP_DIR" rev-list --count HEAD 2>/dev/null || echo "0")
  [ "$commit_count" -ge 1 ]
}

@test "backup handles missing files gracefully" {
  # Add both existing and missing files
  create_test_file "~/.existing-file" "existing content"
  set_backup_list "~/.existing-file" "~/.missing-file"

  run juvy backup

  # Should succeed even with missing files
  [ "$status" -eq 0 ]

  # Existing file should be backed up
  assert_file_backed_up "~/.existing-file"

  # Missing file should not create anything
  assert_not_backed_up "~/.missing-file"

  # Output should mention the missing file
  assert_output_contains "$output" "not found"
}

@test "backup multiple files" {
  create_test_file "~/.bashrc" "bash config"
  create_test_file "~/.zshrc" "zsh config"
  create_test_file "~/.gitconfig" "git config"
  set_backup_list "~/.bashrc" "~/.zshrc" "~/.gitconfig"

  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/.bashrc"
  assert_file_backed_up "~/.zshrc"
  assert_file_backed_up "~/.gitconfig"
}

@test "backup updates existing files" {
  create_test_file "~/.zshrc" "original content"
  add_to_backup_list "~/.zshrc"

  # First backup
  juvy backup

  # Verify first backup content
  local backup_path
  backup_path="$(get_backup_path "~/.zshrc")"
  assert_file_exists "$backup_path"

  local first_content
  first_content=$(cat "$backup_path")
  [ "$first_content" = "original content" ]

  # Modify the source file directly
  printf '%s' "modified content" > "$HOME/.zshrc"

  # Second backup
  juvy backup

  # Backup should have updated content
  local backup_content
  backup_content=$(cat "$backup_path")
  [ "$backup_content" = "modified content" ]
}

@test "backup with empty backup file succeeds" {
  # Empty backup file
  > "$JUVY_CONFIG_DIR/backup"

  run juvy backup

  # Should succeed with no files to backup
  [ "$status" -eq 0 ]
}

@test "backup preserves file permissions" {
  create_test_file "~/.test-script" "#!/bin/bash\necho test"
  chmod 755 "$HOME/.test-script"
  add_to_backup_list "~/.test-script"

  run juvy backup

  [ "$status" -eq 0 ]

  # Check permissions are preserved
  local backup_path
  backup_path="$(get_backup_path "~/.test-script")"
  [ -x "$backup_path" ]
}
