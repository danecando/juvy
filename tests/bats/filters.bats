#!/usr/bin/env bats
# Tests for include/exclude filter patterns

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "exclude pattern blocks directory from backup" {
  # Create nvim config with undo directory that should be excluded
  create_test_dir "~/.config/nvim/"
  create_test_file "~/.config/nvim/init.lua" "-- init.lua"
  create_test_file "~/.config/nvim/lua/plugins.lua" "-- plugins"
  create_test_dir "~/.config/nvim/undo/"
  create_test_file "~/.config/nvim/undo/file1.undo" "undo1"
  create_test_file "~/.config/nvim/undo/file2.undo" "undo2"

  # Include nvim dir but exclude undo subdirectory
  set_backup_list "~/.config/nvim/" "!~/.config/nvim/undo/"

  run juvy backup

  [ "$status" -eq 0 ]

  # nvim files should be backed up
  assert_file_backed_up "~/.config/nvim/init.lua"
  assert_file_backed_up "~/.config/nvim/lua/plugins.lua"

  # undo directory should NOT be backed up
  assert_not_backed_up "~/.config/nvim/undo/"
}

@test "exclude pattern with file and directory" {
  create_test_file "~/.zshrc" "zsh config"
  create_test_dir "~/.config/nvim/"
  create_test_file "~/.config/nvim/init.lua" "nvim config"
  create_test_dir "~/.config/nvim/undo/"
  create_test_file "~/.config/nvim/undo/test.undo" "undo data"

  set_backup_list "~/.zshrc" "~/.config/nvim/" "!~/.config/nvim/undo/"

  run juvy backup

  [ "$status" -eq 0 ]

  # zshrc should be backed up
  assert_file_backed_up "~/.zshrc"

  # nvim init should be backed up
  assert_file_backed_up "~/.config/nvim/init.lua"

  # undo should NOT be backed up
  assert_not_backed_up "~/.config/nvim/undo/"
}

@test "multiple exclude patterns" {
  create_test_dir "~/.config/app/"
  create_test_file "~/.config/app/config.json" "config"
  create_test_dir "~/.config/app/cache/"
  create_test_file "~/.config/app/cache/data.tmp" "cache"
  create_test_dir "~/.config/app/logs/"
  create_test_file "~/.config/app/logs/app.log" "log"

  set_backup_list "~/.config/app/" "!~/.config/app/cache/" "!~/.config/app/logs/"

  run juvy backup

  [ "$status" -eq 0 ]

  # Main config should be backed up
  assert_file_backed_up "~/.config/app/config.json"

  # Excluded directories should NOT be backed up
  assert_not_backed_up "~/.config/app/cache/"
  assert_not_backed_up "~/.config/app/logs/"
}

@test "exclude patterns take precedence over includes" {
  # Even if a file matches an include pattern, excludes should win
  create_test_dir "~/.config/test/"
  create_test_file "~/.config/test/keep.txt" "keep this"
  create_test_file "~/.config/test/exclude.txt" "exclude this"

  # Include the directory but exclude a specific file
  set_backup_list "~/.config/test/" "!~/.config/test/exclude.txt"

  run juvy backup

  [ "$status" -eq 0 ]

  assert_file_backed_up "~/.config/test/keep.txt"
  assert_not_backed_up "~/.config/test/exclude.txt"
}

@test "backup respects inline comments" {
  create_test_file "~/.zshrc" "zsh config"
  create_test_file "~/.bashrc" "bash config"

  # Add entries with inline comments
  cat > "$JUVY_CONFIG_DIR/backup" << 'EOF'
~/.zshrc # Main shell config
~/.bashrc # Alternative shell
EOF

  run juvy backup

  [ "$status" -eq 0 ]

  assert_file_backed_up "~/.zshrc"
  assert_file_backed_up "~/.bashrc"
}

@test "backup skips comment-only lines" {
  create_test_file "~/.zshrc" "zsh config"

  cat > "$JUVY_CONFIG_DIR/backup" << 'EOF'
# This is a comment
~/.zshrc
# Another comment
EOF

  run juvy backup

  [ "$status" -eq 0 ]

  # Only zshrc should be in backup, no errors from comment lines
  assert_file_backed_up "~/.zshrc"
}

@test "backup handles empty lines in backup file" {
  create_test_file "~/.zshrc" "zsh config"

  cat > "$JUVY_CONFIG_DIR/backup" << 'EOF'

~/.zshrc

EOF

  run juvy backup

  [ "$status" -eq 0 ]
  assert_file_backed_up "~/.zshrc"
}
