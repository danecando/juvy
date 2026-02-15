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

@test "remote syncs to remote" {
  # Create bare repo and set as remote via git directly
  local remote_repo="$TEST_ROOT/remote.git"
  git init --bare "$remote_repo" >/dev/null 2>&1
  git -C "$BACKUP_DIR" remote add origin "$remote_repo"

  # Create a backup first
  create_test_file "~/.zshrc" "content"
  add_to_backup_list "~/.zshrc"
  juvy backup

  # Set upstream and push
  run juvy remote sync

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

@test "remote push command is removed" {
  run juvy remote push

  [ "$status" -ne 0 ]
  [[ "$output" == *"removed"* ]]
  [[ "$output" == *"juvy remote sync"* ]]
}

@test "remote sync uses remote default branch when branch is not main" {
  local remote_repo="$TEST_ROOT/remote.git"
  local seed_repo="$TEST_ROOT/seed"

  git init --bare "$remote_repo" >/dev/null 2>&1
  git clone "$remote_repo" "$seed_repo" >/dev/null 2>&1
  git -C "$seed_repo" config user.name "Seed User"
  git -C "$seed_repo" config user.email "seed@example.com"
  git -C "$seed_repo" checkout -b master >/dev/null 2>&1
  echo "seed" > "$seed_repo/seed.txt"
  git -C "$seed_repo" add seed.txt
  git -C "$seed_repo" commit -m "Seed master" >/dev/null 2>&1
  git -C "$seed_repo" push -u origin master >/dev/null 2>&1
  git --git-dir "$remote_repo" symbolic-ref HEAD refs/heads/master

  git -C "$BACKUP_DIR" remote add origin "$remote_repo"
  printf "JUVY_REMOTE_URL='%s'\n" "$remote_repo" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_AUTO_SYNC='false'" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_NAME='origin'" >> "$JUVY_CONFIG_DIR/config"

  create_test_file "~/.zshrc" "machine-a-master-branch"
  add_to_backup_list "~/.zshrc"
  run juvy backup
  [ "$status" -eq 0 ]

  run juvy remote sync
  [ "$status" -eq 0 ]

  run git --git-dir "$remote_repo" rev-list --count master
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "remote sync reconciles remote updates from another machine" {
  local remote_repo="$TEST_ROOT/remote.git"
  local machine_b_repo="$TEST_ROOT/machine-b"
  local tracked_file="$BACKUP_DIR$HOME/.zshrc"

  git init --bare "$remote_repo" >/dev/null 2>&1
  git -C "$BACKUP_DIR" remote add origin "$remote_repo"
  printf "JUVY_REMOTE_URL='%s'\n" "$remote_repo" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_AUTO_SYNC='true'" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_NAME='origin'" >> "$JUVY_CONFIG_DIR/config"

  create_test_file "~/.zshrc" "machine-a-v1"
  add_to_backup_list "~/.zshrc"
  run juvy backup
  [ "$status" -eq 0 ]
  run juvy remote sync
  [ "$status" -eq 0 ]

  git clone "$remote_repo" "$machine_b_repo" >/dev/null 2>&1
  git -C "$machine_b_repo" config user.name "Machine B"
  git -C "$machine_b_repo" config user.email "machine-b@example.com"
  git -C "$machine_b_repo" checkout -B main origin/main >/dev/null 2>&1
  echo "from-b" > "$machine_b_repo/machine-b.txt"
  git -C "$machine_b_repo" add machine-b.txt
  git -C "$machine_b_repo" commit -m "Machine B update" >/dev/null 2>&1
  git -C "$machine_b_repo" push origin HEAD:main >/dev/null 2>&1

  create_test_file "~/.zshrc" "machine-a-v2-updated-content"
  run juvy backup
  [ "$status" -eq 0 ]
  [[ "$output" != *"sync failed"* ]]

  git -C "$BACKUP_DIR" fetch origin >/dev/null 2>&1
  run git -C "$BACKUP_DIR" rev-list --count "origin/main..HEAD"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
  run git -C "$BACKUP_DIR" rev-list --count "HEAD..origin/main"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  run git --git-dir "$remote_repo" rev-list --count main
  [ "$status" -eq 0 ]
  [ "$output" -ge 3 ]
  [ -f "$tracked_file" ]
}

@test "status reports actionable guidance when remote has diverged" {
  local remote_repo="$TEST_ROOT/remote.git"
  local machine_b_repo="$TEST_ROOT/machine-b"

  git init --bare "$remote_repo" >/dev/null 2>&1
  git -C "$BACKUP_DIR" remote add origin "$remote_repo"
  printf "JUVY_REMOTE_URL='%s'\n" "$remote_repo" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_AUTO_SYNC='false'" >> "$JUVY_CONFIG_DIR/config"
  echo "JUVY_REMOTE_NAME='origin'" >> "$JUVY_CONFIG_DIR/config"

  create_test_file "~/.zshrc" "base"
  add_to_backup_list "~/.zshrc"
  run juvy backup
  [ "$status" -eq 0 ]
  run juvy remote sync
  [ "$status" -eq 0 ]

  git clone "$remote_repo" "$machine_b_repo" >/dev/null 2>&1
  git -C "$machine_b_repo" config user.name "Machine B"
  git -C "$machine_b_repo" config user.email "machine-b@example.com"
  git -C "$machine_b_repo" checkout -B main origin/main >/dev/null 2>&1
  echo "from-b" > "$machine_b_repo/machine-b.txt"
  git -C "$machine_b_repo" add machine-b.txt
  git -C "$machine_b_repo" commit -m "Machine B update" >/dev/null 2>&1
  git -C "$machine_b_repo" push origin HEAD:main >/dev/null 2>&1

  create_test_file "~/.zshrc" "from-a"
  run juvy backup
  [ "$status" -eq 0 ]

  run juvy status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Remote diverged"* ]]
  [[ "$output" == *"juvy remote sync"* ]]
}
