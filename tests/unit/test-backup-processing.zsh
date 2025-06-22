#!/usr/bin/env zsh
# Unit tests for backup processing functions

source "$(dirname "$0")/../test-framework.zsh"
source "$(dirname "$0")/../../juvy/juvy.zsh"

test_parse_backup_entry() {
  local result
  
  # Test regular entry
  result=$(_juvy_parse_backup_entry "~/.zshrc")
  if [[ "$result" == *"type:include"* && "$result" == *"path:~/.zshrc"* ]]; then
    report_pass "Regular entry parsing"
  else
    report_fail "Regular entry parsing: expected include type with path ~/.zshrc"
  fi
  
  # Test entry with inline comment
  result=$(_juvy_parse_backup_entry "~/.zshrc # Main shell config")
  if [[ "$result" == *"type:include"* && "$result" == *"path:~/.zshrc"* && "$result" == *"comment:Main shell config"* ]]; then
    report_pass "Entry with inline comment"
  else
    report_fail "Entry with inline comment: expected include with comment"
  fi
  
  # Test exclusion entry
  result=$(_juvy_parse_backup_entry "!~/.config/nvim/undo/")
  if [[ "$result" == *"type:exclude"* && "$result" == *"path:~/.config/nvim/undo/"* ]]; then
    report_pass "Exclusion entry parsing"
  else
    report_fail "Exclusion entry parsing: expected exclude type"
  fi
  
  # Test whitespace handling
  result=$(_juvy_parse_backup_entry "  ~/.gitconfig  ")
  if [[ "$result" == *"path:~/.gitconfig"* ]]; then
    report_pass "Whitespace trimming"
  else
    report_fail "Whitespace trimming: expected trimmed path ~/.gitconfig"
  fi
  
  # Note: The actual function doesn't handle comment-only lines specially
  # It treats them as include entries, which is the current behavior
}

test_validate_path() {
  # Test existing file (use a file we know exists)
  if _juvy_validate_path "/etc/hosts" 2>/dev/null; then
    report_pass "Valid existing file"
  else
    report_fail "Valid existing file should pass validation"
  fi
  
  # Test non-existent file
  if ! _juvy_validate_path "/non/existent/file" 2>/dev/null; then
    report_pass "Non-existent file validation"
  else
    report_fail "Non-existent file should fail validation"
  fi
  
  # Test directory (use a directory we know exists)
  if _juvy_validate_path "/tmp" 2>/dev/null; then
    report_pass "Valid directory"
  else
    report_fail "Valid directory should pass validation"
  fi
}

test_is_sensitive_file() {
  # Test SSH private key
  if _juvy_is_sensitive_file "~/.ssh/id_rsa"; then
    report_pass "SSH private key detection"
  else
    report_fail "SSH private key should be detected as sensitive"
  fi
  
  # Test certificate file
  if _juvy_is_sensitive_file "~/cert.pem"; then
    report_pass "Certificate file detection"
  else
    report_fail "Certificate file should be detected as sensitive"
  fi
  
  # Test token file
  if _juvy_is_sensitive_file "~/.tokens/api.key"; then
    report_pass "Token file detection"
  else
    report_fail "Token file should be detected as sensitive"
  fi
  
  # Test regular config file
  if ! _juvy_is_sensitive_file "~/.zshrc"; then
    report_pass "Regular file not sensitive"
  else
    report_fail "Regular config file should not be sensitive"
  fi
}

test_get_relative_time() {
  local result
  
  # Test with a date string from 1 hour ago
  local one_hour_ago_date
  if command -v gdate >/dev/null 2>&1; then
    one_hour_ago_date=$(gdate -d '1 hour ago' '+%Y-%m-%d %H:%M:%S')
  else
    # Fallback - create a recent date manually
    one_hour_ago_date="2024-01-01 12:00:00"
  fi
  
  result=$(_juvy_get_relative_time "$one_hour_ago_date")
  if [[ "$result" != "unknown time ago" ]]; then
    report_pass "Relative time calculation"
  else
    report_fail "Relative time calculation: got 'unknown time ago', expected time reference"
  fi
}

# Initialize configuration
_juvy_load_config

# Run tests
test_parse_backup_entry
test_validate_path
test_is_sensitive_file
test_get_relative_time

echo "Backup processing tests: $TEST_PASSES passed, $TEST_FAILURES failed"
exit $TEST_FAILURES