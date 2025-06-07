#!/bin/bash
# Cleanup script for juvy test environment
# Usage: ./test-env/cleanup-test-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_HOME="$SCRIPT_DIR/mock-home"

echo "🧹 Cleaning up test environment..."

# Remove juvy-generated directories and files
if [[ -d "$TEST_HOME/.config/juvy" ]]; then
    rm -rf "$TEST_HOME/.config/juvy"
    echo "  ✓ Removed .config/juvy"
fi

if [[ -d "$TEST_HOME/Library" ]]; then
    rm -rf "$TEST_HOME/Library"
    echo "  ✓ Removed Library directory"
fi

# Remove any other juvy-related test artifacts
if [[ -d "$TEST_HOME/juvy-backups" ]]; then
    rm -rf "$TEST_HOME/juvy-backups"
    echo "  ✓ Removed juvy-backups"
fi

# Reset environment variables if they were set for testing
if [[ "$HOME" == *"test-env/mock-home"* ]]; then
    unset HOME JUVY_CONFIG_DIR JUVY_BACKUP_DIR
    echo "  ✓ Reset environment variables"
fi

echo "✅ Test environment cleaned up"
echo ""
echo "💡 Original mock dotfiles are preserved for future testing"