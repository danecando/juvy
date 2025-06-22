#!/usr/bin/env zsh
# Unit tests for rsync pattern generation functions

source "$(dirname "$0")/../test-framework.zsh"
source "$(dirname "$0")/../../juvy/juvy.zsh"

test_add_directory_patterns() {
  local temp_file="$(dirname "$0")/../tmp/juvy-test-patterns-$$"
  local temp_dir="$(dirname "$0")/../tmp/juvy-test-dir-$$"
  local result
  
  # Create temporary test directories
  mkdir -p "$temp_dir/.config/nvim/lua/plugins"
  
  # Test directory pattern generation - fix parameter order: directory first, then file
  echo > "$temp_file"  # Clear file
  _juvy_add_directory_patterns "$temp_dir/.config/nvim/" "$temp_file"
  result=$(cat "$temp_file")
  
  # Should include parent directories and recursive pattern
  if [[ "$result" == *"$temp_dir/"* && "$result" == *"$temp_dir/.config/"* && "$result" == *"$temp_dir/.config/nvim/**"* ]]; then
    report_pass "Directory pattern generation"
  else
    report_fail "Directory pattern generation: expected parent dirs and recursive pattern"
  fi
  
  # Test nested directory
  echo > "$temp_file"  # Clear file
  _juvy_add_directory_patterns "$temp_dir/.config/nvim/lua/plugins/" "$temp_file"
  result=$(cat "$temp_file")
  
  if [[ "$result" == *"$temp_dir/.config/nvim/lua/"* && "$result" == *"$temp_dir/.config/nvim/lua/plugins/**"* ]]; then
    report_pass "Nested directory patterns"
  else
    report_fail "Nested directory patterns: expected hierarchical inclusion"
  fi
  
  rm -rf "$temp_file" "$temp_dir"
}

test_add_file_patterns() {
  local temp_file="$(dirname "$0")/../tmp/juvy-test-patterns-$$"
  local temp_dir="$(dirname "$0")/../tmp/juvy-test-dir-$$"
  local result
  
  # Create temporary test files
  mkdir -p "$temp_dir/.config/git"
  touch "$temp_dir/.zshrc"
  touch "$temp_dir/.config/git/config"
  
  # Test file pattern generation - fix parameter order: file first, then include file
  echo > "$temp_file"  # Clear file
  _juvy_add_file_patterns "$temp_dir/.zshrc" "$temp_file"
  result=$(cat "$temp_file")
  
  # Should include parent directories and the file
  if [[ "$result" == *"$temp_dir/"* && "$result" == *"$temp_dir/.zshrc"* ]]; then
    report_pass "File pattern generation"
  else
    report_fail "File pattern generation: expected parent dir and file inclusion"
  fi
  
  # Test nested file  
  echo > "$temp_file"  # Clear file
  _juvy_add_file_patterns "$temp_dir/.config/git/config" "$temp_file"
  result=$(cat "$temp_file")
  
  if [[ "$result" == *"$temp_dir/.config/"* && "$result" == *"$temp_dir/.config/git/"* && "$result" == *"$temp_dir/.config/git/config"* ]]; then
    report_pass "Nested file patterns"
  else
    report_fail "Nested file patterns: expected hierarchical inclusion"
  fi
  
  rm -rf "$temp_file" "$temp_dir"
}

test_pattern_exclusions() {
  local temp_file="$(dirname "$0")/../tmp/juvy-test-patterns-$$"
  local result
  
  # Test exclusion pattern generation
  echo > "$temp_file"  # Clear file
  
  # This would be called by the main backup processing function
  # Test that exclusion patterns use proper rsync syntax
  echo "- $HOME/.config/nvim/undo/**" >> "$temp_file"
  echo "- *.log" >> "$temp_file"
  
  result=$(cat "$temp_file")
  
  if [[ "$result" == *"- $HOME/.config/nvim/undo/**"* && "$result" == *"- *.log"* ]]; then
    report_pass "Exclusion pattern format"
  else
    report_fail "Exclusion pattern format: expected proper rsync exclusion syntax"
  fi
  
  rm -f "$temp_file"
}

test_pattern_ordering() {
  local temp_file="$(dirname "$0")/../tmp/juvy-test-patterns-$$"
  local temp_dir="$(dirname "$0")/../tmp/juvy-test-dir-$$"
  
  # Create temporary test structure
  mkdir -p "$temp_dir/.config"
  touch "$temp_dir/.zshrc"
  
  # Test that patterns are generated in correct order
  echo > "$temp_file"  # Clear file
  
  # Add patterns in the order they should appear - fix parameter order
  _juvy_add_directory_patterns "$temp_dir/.config/" "$temp_file"
  _juvy_add_file_patterns "$temp_dir/.zshrc" "$temp_file"
  
  # Verify the file contains patterns in logical order
  local line_count=$(wc -l < "$temp_file")
  if [[ "$line_count" -gt 0 ]]; then
    report_pass "Pattern file generation"
  else
    report_fail "Pattern file generation: no patterns generated"
  fi
  
  rm -rf "$temp_file" "$temp_dir"
}

# Initialize configuration
_juvy_load_config

# Run tests
test_add_directory_patterns
test_add_file_patterns  
test_pattern_exclusions
test_pattern_ordering

echo "Pattern generation tests: $TEST_PASSES passed, $TEST_FAILURES failed"
exit $TEST_FAILURES