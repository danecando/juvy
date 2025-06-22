#!/usr/bin/env zsh
# Unit tests for path resolution functions

source "$(dirname "$0")/../test-framework.zsh"
source "$(dirname "$0")/../../juvy/juvy.zsh"

test_entry_to_source_path() {
  local result
  
  # Test explicit tilde path
  result=$(_juvy_entry_to_source_path "~/.zshrc")
  if [[ "$result" == "$HOME/.zshrc" ]]; then
    report_pass "Explicit tilde path conversion"
  else
    report_fail "Explicit tilde path conversion: expected '$HOME/.zshrc', got '$result'"
  fi
  
  # Test implicit home-relative path
  result=$(_juvy_entry_to_source_path ".zshrc")
  if [[ "$result" == "$HOME/.zshrc" ]]; then
    report_pass "Implicit home-relative path conversion"
  else
    report_fail "Implicit home-relative path conversion: expected '$HOME/.zshrc', got '$result'"
  fi
  
  # Test absolute path
  result=$(_juvy_entry_to_source_path "/etc/hosts")
  if [[ "$result" == "/etc/hosts" ]]; then
    report_pass "Absolute path pass-through"
  else
    report_fail "Absolute path pass-through: expected '/etc/hosts', got '$result'"
  fi
  
  # Test directory with trailing slash
  result=$(_juvy_entry_to_source_path "~/.config/nvim/")
  if [[ "$result" == "$HOME/.config/nvim/" ]]; then
    report_pass "Directory with trailing slash"
  else
    report_fail "Directory with trailing slash: expected '$HOME/.config/nvim/', got '$result'"
  fi
}

test_entry_to_backup_path() {
  local result backup_dir="$(dirname "$0")/../tmp/test-backup"
  
  # Load config with test backup directory
  _JUVY_CONFIG[backup_dir]="$backup_dir"
  
  # Test home directory file
  result=$(_juvy_entry_to_backup_path "~/.zshrc")
  if [[ "$result" == "$backup_dir$HOME/.zshrc" ]]; then
    report_pass "Home file backup path"
  else
    report_fail "Home file backup path: expected '$backup_dir$HOME/.zshrc', got '$result'"
  fi
  
  # Test system file
  result=$(_juvy_entry_to_backup_path "/etc/hosts")
  if [[ "$result" == "$backup_dir/etc/hosts" ]]; then
    report_pass "System file backup path"
  else
    report_fail "System file backup path: expected '$backup_dir/etc/hosts', got '$result'"
  fi
  
  # Test directory
  result=$(_juvy_entry_to_backup_path "~/.config/nvim/")
  if [[ "$result" == "$backup_dir$HOME/.config/nvim/" ]]; then
    report_pass "Directory backup path"
  else
    report_fail "Directory backup path: expected '$backup_dir$HOME/.config/nvim/', got '$result'"
  fi
}

# Note: _juvy_backup_path_to_entry function doesn't exist in the actual implementation
# The current architecture doesn't require reverse path mapping

# Initialize configuration
_juvy_load_config

# Run tests
test_entry_to_source_path
test_entry_to_backup_path

echo "Path resolution tests: $TEST_PASSES passed, $TEST_FAILURES failed"
exit $TEST_FAILURES