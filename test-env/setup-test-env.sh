#!/bin/bash
# Setup script for juvy test environment
# Usage: source test-env/setup-test-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JUVY_TEST_HOME="$SCRIPT_DIR/mock-home"
export JUVY_TEST_CONFIG_DIR="$JUVY_TEST_HOME/.config/juvy"
export JUVY_TEST_BACKUP_DIR="$JUVY_TEST_HOME/juvy-backups"

# Override juvy variables for testing
export HOME="$JUVY_TEST_HOME"
export JUVY_CONFIG_DIR="$JUVY_TEST_CONFIG_DIR"
export JUVY_BACKUP_DIR="$JUVY_TEST_BACKUP_DIR"

echo "✅ Test environment configured:"
echo "   Test HOME: $JUVY_TEST_HOME"
echo "   Config DIR: $JUVY_TEST_CONFIG_DIR" 
echo "   Backup DIR: $JUVY_TEST_BACKUP_DIR"
echo ""
echo "💡 Run juvy commands normally - they will use the test environment"
echo "💡 Run 'unset HOME JUVY_CONFIG_DIR JUVY_BACKUP_DIR' to restore original environment"