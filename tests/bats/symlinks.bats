#!/usr/bin/env bats
# Tests for symlink handling

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "backup preserves symlink as symlink" {
  # Create actual file and symlink pointing to it
  mkdir -p "$HOME/actual"
  echo "actual content" > "$HOME/actual/real-file.txt"
  create_symlink "$HOME/actual/real-file.txt" "~/.my-symlink"
  add_to_backup_list "~/.my-symlink"

  run juvy backup

  [ "$status" -eq 0 ]

  # Backup should contain a symlink, not a regular file
  local backup_path
  backup_path="$(get_backup_path "~/.my-symlink")"
  assert_is_symlink "$backup_path"
}

@test "backup preserves symlink target" {
  mkdir -p "$HOME/actual"
  echo "actual content" > "$HOME/actual/real-file.txt"
  create_symlink "$HOME/actual/real-file.txt" "~/.my-symlink"
  add_to_backup_list "~/.my-symlink"

  run juvy backup

  [ "$status" -eq 0 ]

  local backup_path original_target backup_target
  backup_path="$(get_backup_path "~/.my-symlink")"
  original_target=$(readlink "$HOME/.my-symlink")
  backup_target=$(readlink "$backup_path")

  [ "$backup_target" = "$original_target" ]
}

@test "restore preserves symlink as symlink" {
  mkdir -p "$HOME/actual"
  echo "actual content" > "$HOME/actual/real-file.txt"
  create_symlink "$HOME/actual/real-file.txt" "~/.my-symlink"
  add_to_backup_list "~/.my-symlink"

  juvy backup

  # Remove and restore
  rm "$HOME/.my-symlink"
  run_restore_confirmed

  # Restored should be a symlink
  assert_is_symlink "$HOME/.my-symlink"
}

@test "restore preserves symlink target" {
  mkdir -p "$HOME/actual"
  echo "actual content" > "$HOME/actual/real-file.txt"
  create_symlink "$HOME/actual/real-file.txt" "~/.my-symlink"
  add_to_backup_list "~/.my-symlink"

  local original_target
  original_target=$(readlink "$HOME/.my-symlink")

  juvy backup

  rm "$HOME/.my-symlink"
  run_restore_confirmed

  # Restored symlink should point to same target
  local restored_target
  restored_target=$(readlink "$HOME/.my-symlink")
  [ "$restored_target" = "$original_target" ]
}

@test "backup handles broken symlinks" {
  # Create a symlink to a non-existent file
  ln -s "/nonexistent/path" "$HOME/.broken-link"
  add_to_backup_list "~/.broken-link"

  run juvy backup

  # Should succeed (rsync handles broken symlinks)
  [ "$status" -eq 0 ]
}

@test "backup directory containing symlinks" {
  mkdir -p "$HOME/.config/app"
  echo "config" > "$HOME/.config/app/config.txt"
  mkdir -p "$HOME/shared"
  echo "shared data" > "$HOME/shared/data.txt"
  ln -s "$HOME/shared/data.txt" "$HOME/.config/app/data-link"

  add_to_backup_list "~/.config/app/"

  run juvy backup

  [ "$status" -eq 0 ]

  # Both regular file and symlink should be backed up
  assert_file_backed_up "~/.config/app/config.txt"

  local backup_link
  backup_link="$(get_backup_path "~/.config/app/data-link")"
  assert_is_symlink "$backup_link"
}
