# test_helper.bash - Common utilities for juvy bats tests
#
# This file provides setup/teardown functions and assertions for testing juvy.
# Tests use isolated temp directories with overridden HOME and JUVY_CONFIG_DIR.

# Path to bats helper libraries
BATS_SUPPORT_DIR="${BATS_SUPPORT_DIR:-/usr/local/lib/bats/bats-support}"
BATS_ASSERT_DIR="${BATS_ASSERT_DIR:-/usr/local/lib/bats/bats-assert}"

# Load bats helpers if available
if [[ -d "$BATS_SUPPORT_DIR" ]]; then
  load "$BATS_SUPPORT_DIR/load.bash"
fi
if [[ -d "$BATS_ASSERT_DIR" ]]; then
  load "$BATS_ASSERT_DIR/load.bash"
fi

# Path to juvy.sh - resolved relative to test file location
JUVY_SCRIPT="${JUVY_SCRIPT:-$(cd "$(dirname "${BATS_TEST_DIRNAME}")/.." && pwd)/juvy.sh}"

# Path to fixtures
FIXTURES_DIR="${FIXTURES_DIR:-$(cd "$(dirname "${BATS_TEST_DIRNAME}")" && pwd)/fixtures}"

# Bash to use for sourcing juvy (allows Bash 3.2 testing)
JUVY_TEST_BASH="${JUVY_TEST_BASH:-/bin/bash}"

# ------------------------------------------------------------------------------
# Setup / Teardown
# ------------------------------------------------------------------------------

# Creates an isolated test environment with:
# - Temp directory as TEST_ROOT
# - Fake HOME inside TEST_ROOT
# - JUVY_CONFIG_DIR set up
# - Git-initialized backup directory
# - juvy.sh sourced
setup_test_environment() {
  # Create isolated temp directory
  TEST_ROOT="$(mktemp -d)"
  export TEST_ROOT

  # Set up fake HOME
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"

  # Set up juvy config directory
  export JUVY_CONFIG_DIR="$HOME/.config/juvy"
  mkdir -p "$JUVY_CONFIG_DIR"

  # Set up backup directory with git
  BACKUP_DIR="$TEST_ROOT/backup"
  export BACKUP_DIR
  mkdir -p "$BACKUP_DIR"
  git init -b main "$BACKUP_DIR" >/dev/null 2>&1
  git -C "$BACKUP_DIR" config user.name "Test User"
  git -C "$BACKUP_DIR" config user.email "test@example.com"

  # Write default config
  echo "JUVY_BACKUP_DIR='$BACKUP_DIR'" > "$JUVY_CONFIG_DIR/config"

  # Create empty backup file
  touch "$JUVY_CONFIG_DIR/backup"

  # Source juvy.sh
  source "$JUVY_SCRIPT"
}

# Cleans up the test environment
teardown_test_environment() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" ]]; then
    rm -rf "$TEST_ROOT"
  fi
}

# Standard setup that calls setup_test_environment
# Use in tests: setup() { common_setup; }
common_setup() {
  setup_test_environment
}

# Standard teardown that calls teardown_test_environment
# Use in tests: teardown() { common_teardown; }
common_teardown() {
  teardown_test_environment
}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

# Create a test file with content
# Usage: create_test_file "~/.zshrc" "content here"
create_test_file() {
  local entry="$1"
  local content="${2:-test content}"
  local file_path

  file_path="$(_resolve_entry_path "$entry")"
  mkdir -p "$(dirname "$file_path")"
  echo "$content" > "$file_path"
}

# Create a test directory
# Usage: create_test_dir "~/.config/nvim/"
create_test_dir() {
  local entry="$1"
  local dir_path

  dir_path="$(_resolve_entry_path "$entry")"
  mkdir -p "$dir_path"
}

# Add an entry to the backup list
# Usage: add_to_backup_list "~/.zshrc"
add_to_backup_list() {
  local entry="$1"
  echo "$entry" >> "$JUVY_CONFIG_DIR/backup"
}

# Set the entire backup list content
# Usage: set_backup_list "~/.zshrc" "~/.config/nvim/" "!~/.config/nvim/undo/"
set_backup_list() {
  > "$JUVY_CONFIG_DIR/backup"
  for entry in "$@"; do
    echo "$entry" >> "$JUVY_CONFIG_DIR/backup"
  done
}

# Get the backup path for an entry
# Usage: backup_path=$(get_backup_path "~/.zshrc")
get_backup_path() {
  local entry="$1"
  local source_path

  source_path="$(_resolve_entry_path "$entry")"
  echo "$BACKUP_DIR$source_path"
}

# Resolve an entry (like ~/.zshrc) to an absolute path
_resolve_entry_path() {
  local entry="$1"

  # Handle tilde expansion
  if [[ "$entry" == "~/"* ]]; then
    echo "$HOME/${entry#\~/}"
  elif [[ "$entry" == "~" ]]; then
    echo "$HOME"
  else
    echo "$entry"
  fi
}

# Copy a fixture file to the test environment
# Usage: copy_fixture "sample-dotfiles/.zshrc" "~/.zshrc"
copy_fixture() {
  local fixture_path="$1"
  local dest_entry="$2"
  local dest_path

  dest_path="$(_resolve_entry_path "$dest_entry")"
  mkdir -p "$(dirname "$dest_path")"
  cp "$FIXTURES_DIR/$fixture_path" "$dest_path"
}

# Create a symlink
# Usage: create_symlink "/path/to/target" "~/.my-link"
create_symlink() {
  local target="$1"
  local link_entry="$2"
  local link_path

  link_path="$(_resolve_entry_path "$link_entry")"
  mkdir -p "$(dirname "$link_path")"
  ln -s "$target" "$link_path"
}

# Run juvy restore with automatic 'y' confirmation
# Usage: run_restore_confirmed
run_restore_confirmed() {
  echo y | juvy restore "$@"
}

# ------------------------------------------------------------------------------
# Assertions
# ------------------------------------------------------------------------------

# Assert that a file exists in the backup
# Usage: assert_file_backed_up "~/.zshrc"
assert_file_backed_up() {
  local entry="$1"
  local backup_path

  backup_path="$(get_backup_path "$entry")"
  if [[ ! -f "$backup_path" ]]; then
    echo "Expected file to be backed up: $entry (at $backup_path)" >&2
    return 1
  fi
}

# Assert that a directory exists in the backup
# Usage: assert_dir_backed_up "~/.config/nvim/"
assert_dir_backed_up() {
  local entry="$1"
  local backup_path

  backup_path="$(get_backup_path "$entry")"
  if [[ ! -d "$backup_path" ]]; then
    echo "Expected directory to be backed up: $entry (at $backup_path)" >&2
    return 1
  fi
}

# Assert that a file/directory is NOT in the backup
# Usage: assert_not_backed_up "~/.config/nvim/undo/"
assert_not_backed_up() {
  local entry="$1"
  local backup_path

  backup_path="$(get_backup_path "$entry")"
  if [[ -e "$backup_path" ]]; then
    echo "Expected entry to NOT be backed up: $entry (found at $backup_path)" >&2
    return 1
  fi
}

# Assert that two files have identical content
# Usage: assert_files_identical "$file1" "$file2"
assert_files_identical() {
  local file1="$1"
  local file2="$2"

  if ! cmp -s "$file1" "$file2"; then
    echo "Files differ: $file1 vs $file2" >&2
    return 1
  fi
}

# Assert that a file exists at the given path
# Usage: assert_file_exists "$path"
assert_file_exists() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    echo "Expected file to exist: $file_path" >&2
    return 1
  fi
}

# Assert that a directory exists at the given path
# Usage: assert_dir_exists "$path"
assert_dir_exists() {
  local dir_path="$1"

  if [[ ! -d "$dir_path" ]]; then
    echo "Expected directory to exist: $dir_path" >&2
    return 1
  fi
}

# Assert that a path is a symlink
# Usage: assert_is_symlink "$path"
assert_is_symlink() {
  local link_path="$1"

  if [[ ! -L "$link_path" ]]; then
    echo "Expected path to be a symlink: $link_path" >&2
    return 1
  fi
}

# Assert that a symlink points to the expected target
# Usage: assert_symlink_target "$link" "$expected_target"
assert_symlink_target() {
  local link_path="$1"
  local expected_target="$2"
  local actual_target

  actual_target="$(readlink "$link_path")"
  if [[ "$actual_target" != "$expected_target" ]]; then
    echo "Symlink target mismatch for $link_path:" >&2
    echo "  Expected: $expected_target" >&2
    echo "  Actual: $actual_target" >&2
    return 1
  fi
}

# Assert that output contains a string
# Usage: assert_output_contains "$output" "expected string"
assert_output_contains() {
  local output="$1"
  local expected="$2"

  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected" >&2
    echo "Actual output: $output" >&2
    return 1
  fi
}

# Assert that a file contains a specific line
# Usage: assert_file_contains "$file" "expected line"
assert_file_contains() {
  local file_path="$1"
  local expected="$2"

  if ! grep -qF "$expected" "$file_path" 2>/dev/null; then
    echo "Expected file $file_path to contain: $expected" >&2
    return 1
  fi
}

# Assert that a file does NOT contain a specific line
# Usage: assert_file_not_contains "$file" "unexpected line"
assert_file_not_contains() {
  local file_path="$1"
  local unexpected="$2"

  if grep -qF "$unexpected" "$file_path" 2>/dev/null; then
    echo "Expected file $file_path to NOT contain: $unexpected" >&2
    return 1
  fi
}

# Assert that a backup file is identical to source
# Usage: assert_backup_matches_source "~/.zshrc"
assert_backup_matches_source() {
  local entry="$1"
  local source_path backup_path

  source_path="$(_resolve_entry_path "$entry")"
  backup_path="$(get_backup_path "$entry")"

  assert_files_identical "$source_path" "$backup_path"
}
