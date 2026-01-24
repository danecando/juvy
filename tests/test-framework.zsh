#!/usr/bin/env zsh
# Basic testing utilities for juvy
#
# Test Environment Setup:
#   juvy uses a single global (_JUVY_CONFIG) and respects the JUVY_CONFIG_DIR
#   environment variable for test isolation. Tests should:
#
#   1. Create a temp directory: TEST_ROOT=$(mktemp -d)
#   2. Override HOME: export HOME="$TEST_ROOT/home"
#   3. Set config dir: export JUVY_CONFIG_DIR="$HOME/.config/juvy"
#   4. Create config/backup files in $JUVY_CONFIG_DIR/
#   5. Source juvy.zsh
#   6. Clean up with: cleanup_dir "$TEST_ROOT"
#
#   No other environment variables need to be set.

setopt errexit
setopt nounset
setopt pipefail

TEST_PASSES=0
TEST_FAILURES=0

report_pass() {
  echo "PASS: $1"
  TEST_PASSES=$((TEST_PASSES+1))
}

report_fail() {
  echo "FAIL: $1" >&2
  TEST_FAILURES=$((TEST_FAILURES+1))
}

assert_file_exists() {
  local file="$1"
  if [[ ! -e "$file" ]]; then
    echo "Expected file to exist: $file" >&2
    return 1
  fi
}

assert_files_identical() {
  local f1="$1" f2="$2"
  if ! cmp -s "$f1" "$f2"; then
    echo "Files differ: $f1 $f2" >&2
    return 1
  fi
}

cleanup_dir() {
  local dir="$1"
  [[ -d "$dir" ]] && rm -rf "$dir"
}

