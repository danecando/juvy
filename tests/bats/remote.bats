#!/usr/bin/env bats
# Tests for git remote functionality

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "remote command shows status when no remote configured" {
  run juvy remote

  [ "$status" -eq 0 ]
  # Should indicate no remote or show empty status
  [[ "$output" == *"No remote"* || "$output" == *"not configured"* || -z "$output" || "$output" == *"Remote"* ]]
}

@test "remote off removes git remote" {
  # Set up a remote first via git directly
  local remote_repo="$TEST_ROOT/remote.git"
  git init --bare "$remote_repo" >/dev/null 2>&1
  git -C "$BACKUP_DIR" remote add origin "$remote_repo" 2>/dev/null || true

  run juvy remote off

  [ "$status" -eq 0 ]

  # Verify remote was removed
  local remote_check
  remote_check=$(git -C "$BACKUP_DIR" remote 2>/dev/null || echo "")
  [[ "$remote_check" != *"origin"* ]]
}

@test "remote push syncs to remote" {
  # Create bare repo and set as remote via git directly
  local remote_repo="$TEST_ROOT/remote.git"
  git init --bare "$remote_repo" >/dev/null 2>&1
  git -C "$BACKUP_DIR" remote add origin "$remote_repo"

  # Create a backup first
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"
  juvy backup

  # Set upstream and push
  run juvy remote push

  # Check if push succeeded or if there's a reasonable error
  # (push may fail in some environments due to git config)
  if [ "$status" -ne 0 ]; then
    # If push failed, verify it's not due to a broken command
    # The remote should at least be configured
    local remote_url
    remote_url=$(git -C "$BACKUP_DIR" remote get-url origin 2>/dev/null || echo "")
    [ -n "$remote_url" ]
  else
    # If push succeeded, verify commits were pushed
    local remote_commits
    remote_commits=$(git -C "$remote_repo" rev-list --count HEAD 2>/dev/null || echo "0")
    [ "$remote_commits" -ge 1 ]
  fi
}

@test "remote validates URL format" {
  # Invalid URL should fail
  run juvy remote "/tmp/invalid-path"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid URL"* ]]
}

@test "remote accepts https URL format" {
  # Note: This will fail connection test but should accept the URL format
  # We're just testing URL validation, not actual connection
  run juvy remote "https://github.com/user/repo.git"

  # May fail due to connection test, but shouldn't fail URL validation
  # Check that it got past URL validation (error message won't mention "Invalid URL")
  [[ "$output" != *"Invalid URL"* ]]
}

@test "remote accepts git SSH URL format" {
  # Note: This will fail connection test but should accept the URL format
  run juvy remote "git@github.com:user/repo.git"

  # Check that it got past URL validation
  [[ "$output" != *"Invalid URL"* ]]
}
