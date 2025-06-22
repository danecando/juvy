#!/usr/bin/env zsh
# Unit tests for configuration parsing functions

source "$(dirname "$0")/../test-framework.zsh"
source "$(dirname "$0")/../../juvy/juvy.zsh"

test_load_config() {
  local temp_config="$(dirname "$0")/../tmp/test-config-$$"
  local original_config="$JUVY_CONFIG"
  
  # Override config path for testing
  JUVY_CONFIG="$temp_config"
  
  # Test default configuration loading
  _juvy_load_config
  if [[ "${_JUVY_CONFIG[backup_dir]}" == "$HOME/Library/Mobile Documents/com~apple~CloudDocs/juvy" ]]; then
    report_pass "Default backup directory"
  else
    report_fail "Default backup directory: expected iCloud path, got '${_JUVY_CONFIG[backup_dir]}'"
  fi
  
  if [[ "${_JUVY_CONFIG[remote_url]}" == "" ]]; then
    report_pass "Default empty remote URL"
  else
    report_fail "Default remote URL should be empty, got '${_JUVY_CONFIG[remote_url]}'"
  fi
  
  # Test custom configuration loading
  cat > "$temp_config" << 'EOF'
JUVY_BACKUP_DIR="/custom/backup/path"
JUVY_REMOTE_URL="git@github.com:user/dotfiles.git"
JUVY_REMOTE_PUSH="true"
JUVY_SCHEDULE_ENABLED="true"
EOF
  
  _juvy_load_config
  if [[ "${_JUVY_CONFIG[backup_dir]}" == "/custom/backup/path" ]]; then
    report_pass "Custom backup directory"
  else
    report_fail "Custom backup directory: expected '/custom/backup/path', got '${_JUVY_CONFIG[backup_dir]}'"
  fi
  
  if [[ "${_JUVY_CONFIG[remote_url]}" == "git@github.com:user/dotfiles.git" ]]; then
    report_pass "Custom remote URL"
  else
    report_fail "Custom remote URL: expected git URL, got '${_JUVY_CONFIG[remote_url]}'"
  fi
  
  if [[ "${_JUVY_CONFIG[remote_push]}" == "true" ]]; then
    report_pass "Custom remote push setting"
  else
    report_fail "Custom remote push: expected 'true', got '${_JUVY_CONFIG[remote_push]}'"
  fi
  
  # Restore original config path
  JUVY_CONFIG="$original_config"
  rm -f "$temp_config"
}

test_parse_quoted_value() {
  local result
  
  # Test unquoted value
  result=$(_juvy_parse_quoted_value "simple_value")
  if [[ "$result" == "simple_value" ]]; then
    report_pass "Unquoted value parsing"
  else
    report_fail "Unquoted value parsing: expected 'simple_value', got '$result'"
  fi
  
  # Test single-quoted value
  result=$(_juvy_parse_quoted_value "'single quoted'")
  if [[ "$result" == "single quoted" ]]; then
    report_pass "Single-quoted value parsing"
  else
    report_fail "Single-quoted value parsing: expected 'single quoted', got '$result'"
  fi
  
  # Test double-quoted value
  result=$(_juvy_parse_quoted_value '"double quoted"')
  if [[ "$result" == "double quoted" ]]; then
    report_pass "Double-quoted value parsing"
  else
    report_fail "Double-quoted value parsing: expected 'double quoted', got '$result'"
  fi
  
  # Test value with spaces
  result=$(_juvy_parse_quoted_value '"path with spaces"')
  if [[ "$result" == "path with spaces" ]]; then
    report_pass "Quoted value with spaces"
  else
    report_fail "Quoted value with spaces: expected 'path with spaces', got '$result'"
  fi
}

test_trim_whitespace() {
  local result
  
  # Test leading whitespace
  result=$(_juvy_trim_whitespace "  leading")
  if [[ "$result" == "leading" ]]; then
    report_pass "Leading whitespace trimming"
  else
    report_fail "Leading whitespace trimming: expected 'leading', got '$result'"
  fi
  
  # Test trailing whitespace
  result=$(_juvy_trim_whitespace "trailing  ")
  if [[ "$result" == "trailing" ]]; then
    report_pass "Trailing whitespace trimming"
  else
    report_fail "Trailing whitespace trimming: expected 'trailing', got '$result'"
  fi
  
  # Test both leading and trailing
  result=$(_juvy_trim_whitespace "  both  ")
  if [[ "$result" == "both" ]]; then
    report_pass "Both whitespace trimming"
  else
    report_fail "Both whitespace trimming: expected 'both', got '$result'"
  fi
  
  # Test no whitespace
  result=$(_juvy_trim_whitespace "none")
  if [[ "$result" == "none" ]]; then
    report_pass "No whitespace to trim"
  else
    report_fail "No whitespace to trim: expected 'none', got '$result'"
  fi
}

test_config_file_format() {
  local temp_config="$(dirname "$0")/../tmp/test-config-format-$$"
  local original_config="$JUVY_CONFIG"
  
  # Override config path for testing
  JUVY_CONFIG="$temp_config"
  
  # Test config file with comments and whitespace
  cat > "$temp_config" << 'EOF'
# This is a comment
JUVY_BACKUP_DIR="/test/path"

# Another comment
  JUVY_REMOTE_URL = "git@example.com:user/repo.git"  
JUVY_REMOTE_PUSH=true

# Empty lines and comments should be ignored

JUVY_SCHEDULE_ENABLED="false"
EOF
  
  _juvy_load_config
  
  if [[ "${_JUVY_CONFIG[backup_dir]}" == "/test/path" ]]; then
    report_pass "Config with comments parsing"
  else
    report_fail "Config with comments: backup_dir expected '/test/path', got '${_JUVY_CONFIG[backup_dir]}'"
  fi
  
  if [[ "${_JUVY_CONFIG[remote_url]}" == "git@example.com:user/repo.git" ]]; then
    report_pass "Config with whitespace parsing"
  else
    report_fail "Config with whitespace: remote_url expected git URL, got '${_JUVY_CONFIG[remote_url]}'"
  fi
  
  if [[ "${_JUVY_CONFIG[schedule_enabled]}" == "false" ]]; then
    report_pass "Config boolean value parsing"
  else
    report_fail "Config boolean: expected 'false', got '${_JUVY_CONFIG[schedule_enabled]}'"
  fi
  
  # Restore original config path
  JUVY_CONFIG="$original_config"
  rm -f "$temp_config"
}

# Initialize configuration
_juvy_load_config

# Run tests
test_load_config
test_parse_quoted_value
test_trim_whitespace
test_config_file_format

echo "Configuration parsing tests: $TEST_PASSES passed, $TEST_FAILURES failed"
exit $TEST_FAILURES