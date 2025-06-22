#!/usr/bin/env zsh
# Basic testing utilities for juvy

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

