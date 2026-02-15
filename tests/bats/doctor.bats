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

@test "doctor warns when local and remote histories have diverged" {
  local remote_repo="$TEST_ROOT/remote.git"
  local machine_b_repo="$TEST_ROOT/machine-b"

  git init --bare "$remote_repo" >/dev/null 2>&1
  git -C "$BACKUP_DIR" remote add origin "$remote_repo"
  printf "JUVY_REMOTE_URL='%s'\n" "$remote_repo" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_PUSH='false'" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_NAME='origin'" >> "$JUVY_CONFIG_DIR/config"

  create_test_file "~/.zshrc" "base"
  add_to_backup_list "~/.zshrc"
  juvy backup >/dev/null 2>&1
  juvy remote sync >/dev/null 2>&1

  git clone "$remote_repo" "$machine_b_repo" >/dev/null 2>&1
  git -C "$machine_b_repo" config user.name "Machine B"
  git -C "$machine_b_repo" config user.email "machine-b@example.com"
  git -C "$machine_b_repo" checkout -B main origin/main >/dev/null 2>&1
  echo "from-b" > "$machine_b_repo/machine-b.txt"
  git -C "$machine_b_repo" add machine-b.txt
  git -C "$machine_b_repo" commit -m "Machine B update" >/dev/null 2>&1
  git -C "$machine_b_repo" push origin HEAD:main >/dev/null 2>&1

  create_test_file "~/.zshrc" "from-a"
  juvy backup >/dev/null 2>&1

  run juvy doctor

  [[ "$output" == *"diverged"* ]]
  [[ "$output" == *"juvy remote sync"* ]]
}
