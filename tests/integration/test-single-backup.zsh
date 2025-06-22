#!/usr/bin/env zsh
set -e

# Load testing utilities
source "$(dirname $0)/../test-framework.zsh"

# Load test environment setup
source "$(dirname $0)/../juvy-test-setup.zsh"

# Set up isolated test environment with single-backup fixture set
setup_juvy_test_env "single-backup" "testuser" "single-backup"

# Load fixtures and backup configuration
load_test_fixtures
create_backup_entries_from_fixtures

# Load juvy with test environment
load_juvy_for_test

# Run backup
juvy backup >/dev/null

BACKUP_PATH="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.zshrc"

assert_file_exists "$BACKUP_PATH"
assert_files_identical "$JUVY_TEST_HOME/.zshrc" "$BACKUP_PATH"

# Remove original and restore
rm "$JUVY_TEST_HOME/.zshrc"

echo y | juvy restore >/dev/null

assert_file_exists "$JUVY_TEST_HOME/.zshrc"
assert_files_identical "$JUVY_TEST_HOME/.zshrc" "$BACKUP_PATH"

cleanup_test_env

report_pass "single-backup"
