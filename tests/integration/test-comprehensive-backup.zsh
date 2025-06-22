#!/usr/bin/env zsh
set -e

# Load testing utilities
source "$(dirname $0)/../test-framework.zsh"

# Load test environment setup
source "$(dirname $0)/../juvy-test-setup.zsh"

# Set up isolated test environment with comprehensive-backup fixture set
setup_juvy_test_env "comprehensive-backup" "testuser" "comprehensive-backup"

# Load fixtures and backup configuration
load_test_fixtures
create_backup_entries_from_fixtures

# Load juvy with test environment
load_juvy_for_test

# Run backup
juvy backup >/dev/null

# Test: Verify home directory files were backed up
BACKUP_ZSHRC="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.zshrc"
assert_file_exists "$BACKUP_ZSHRC"
assert_files_identical "$JUVY_TEST_HOME/.zshrc" "$BACKUP_ZSHRC"
report_pass "comprehensive-backup: .zshrc backed up"

BACKUP_GITCONFIG="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.gitconfig"
assert_file_exists "$BACKUP_GITCONFIG"
assert_files_identical "$JUVY_TEST_HOME/.gitconfig" "$BACKUP_GITCONFIG"
report_pass "comprehensive-backup: .gitconfig backed up"

# Test: Verify nested config directories were backed up
BACKUP_NVIM_INIT="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.config/nvim/init.vim"
assert_file_exists "$BACKUP_NVIM_INIT"
assert_files_identical "$JUVY_TEST_HOME/.config/nvim/init.vim" "$BACKUP_NVIM_INIT"
report_pass "comprehensive-backup: nvim config backed up"

BACKUP_GIT_IGNORE="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.config/git/ignore"
assert_file_exists "$BACKUP_GIT_IGNORE"
assert_files_identical "$JUVY_TEST_HOME/.config/git/ignore" "$BACKUP_GIT_IGNORE"
report_pass "comprehensive-backup: git global ignore backed up"

# Test: Verify SSH config was backed up
BACKUP_SSH_CONFIG="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.ssh/config"
assert_file_exists "$BACKUP_SSH_CONFIG"
assert_files_identical "$JUVY_TEST_HOME/.ssh/config" "$BACKUP_SSH_CONFIG"
report_pass "comprehensive-backup: SSH config backed up"

# Test: Verify system files were backed up
BACKUP_HOSTS="$JUVY_TEST_BACKUP_DIR/etc/hosts"
assert_file_exists "$BACKUP_HOSTS"
assert_files_identical "$JUVY_TEST_ROOT/etc/hosts" "$BACKUP_HOSTS"
report_pass "comprehensive-backup: system hosts file backed up"

BACKUP_SCRIPT="$JUVY_TEST_BACKUP_DIR/usr/local/bin/test-script"
assert_file_exists "$BACKUP_SCRIPT"
assert_files_identical "$JUVY_TEST_ROOT/usr/local/bin/test-script" "$BACKUP_SCRIPT"
report_pass "comprehensive-backup: system script backed up"

# Test: Verify excluded directory was NOT backed up
BACKUP_UNDO_DIR="$JUVY_TEST_BACKUP_DIR$JUVY_TEST_HOME/.config/nvim/undo"
if [[ ! -d "$BACKUP_UNDO_DIR" ]]; then
    report_pass "comprehensive-backup: excluded undo directory not backed up"
else
    report_fail "comprehensive-backup: excluded undo directory should not be backed up"
fi

# Test: Verify git commit was created (run all git commands in backup directory)
if [[ -n $(git -C "$JUVY_TEST_BACKUP_DIR" log --oneline 2>/dev/null) ]]; then
    report_pass "comprehensive-backup: git commit created"
else
    report_fail "comprehensive-backup: no git commit found"
fi

# Test: Verify git log shows a commit was made (check for any commit)
COMMIT_COUNT=$(git -C "$JUVY_TEST_BACKUP_DIR" rev-list --count HEAD 2>/dev/null)
if [[ "$COMMIT_COUNT" -gt 0 ]]; then
    report_pass "comprehensive-backup: commits exist in backup repo"
else
    report_fail "comprehensive-backup: no commits found in backup repo"
fi

# Test: Restore functionality
# Remove some original files to test restore
rm "$JUVY_TEST_HOME/.zshrc"
rm "$JUVY_TEST_HOME/.gitconfig" 
rm -rf "$JUVY_TEST_HOME/.config/nvim"
rm "$JUVY_TEST_ROOT/etc/hosts"

# Perform restore
echo y | juvy restore >/dev/null

# Verify files were restored
assert_file_exists "$JUVY_TEST_HOME/.zshrc"
assert_files_identical "$JUVY_TEST_HOME/.zshrc" "$BACKUP_ZSHRC"
report_pass "comprehensive-backup: .zshrc restored"

assert_file_exists "$JUVY_TEST_HOME/.gitconfig"
assert_files_identical "$JUVY_TEST_HOME/.gitconfig" "$BACKUP_GITCONFIG"
report_pass "comprehensive-backup: .gitconfig restored"

assert_file_exists "$JUVY_TEST_HOME/.config/nvim/init.vim"
assert_files_identical "$JUVY_TEST_HOME/.config/nvim/init.vim" "$BACKUP_NVIM_INIT"
report_pass "comprehensive-backup: nvim config restored"

assert_file_exists "$JUVY_TEST_ROOT/etc/hosts"
assert_files_identical "$JUVY_TEST_ROOT/etc/hosts" "$BACKUP_HOSTS"
report_pass "comprehensive-backup: system hosts file restored"

# Cleanup
cleanup_test_env

echo "Comprehensive backup tests: $TEST_PASSES passed, $TEST_FAILURES failed"
exit $TEST_FAILURES