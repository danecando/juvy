#!/usr/bin/env zsh
# juvy-test-setup.zsh - Test setup utility for juvy integration tests
# Creates isolated test environment using tests/tmp as fake root directory

emulate -L zsh

# Function to setup test environment with custom paths and fixtures
setup_juvy_test_env() {
    local test_name="${1:-default}"
    local test_user="${2:-testuser}"
    local fixture_set="${3:-default}"
    local test_id="$$"
    
    # Create unique test directory structure  
    local tmp_dir="$(dirname "${(%):-%x}")/../tmp"
    mkdir -p "$tmp_dir"
    local test_root="$(cd "$tmp_dir" && pwd)/test-${test_name}-${test_id}"
    local fake_home="$test_root/Users/$test_user"
    local backup_dir="$test_root/backup"
    
    # Clean up any existing test directory
    [[ -d "$test_root" ]] && rm -rf "$test_root"
    
    # Create directory structure mimicking real filesystem
    mkdir -p "$fake_home"
    mkdir -p "$test_root/etc"
    mkdir -p "$test_root/usr/local/bin"
    mkdir -p "$backup_dir"
    
    # Initialize git repo in backup directory
    git init -b main "$backup_dir" >/dev/null 2>&1
    git -C "$backup_dir" config user.name "Test User"
    git -C "$backup_dir" config user.email "test@example.com"
    
    # Set up juvy config directory in fake home
    local juvy_config_dir="$fake_home/.config/juvy"
    mkdir -p "$juvy_config_dir"
    
    # Export test environment variables
    export JUVY_TEST_ROOT="$test_root"
    export JUVY_TEST_HOME="$fake_home"
    export JUVY_TEST_BACKUP_DIR="$backup_dir"
    export JUVY_TEST_CONFIG_DIR="$juvy_config_dir"
    export JUVY_TEST_USER="$test_user"
    export JUVY_TEST_FIXTURE_SET="$fixture_set"
    
    # Create a function to load juvy with test paths
    load_juvy_for_test() {
        # Save original HOME
        local original_home="$HOME"
        
        # Temporarily override HOME and config paths
        export HOME="$JUVY_TEST_HOME"
        export JUVY_CONFIG_DIR="$JUVY_TEST_CONFIG_DIR"
        export JUVY_CONFIG="$JUVY_TEST_CONFIG_DIR/config"
        export JUVY_BACKUP="$JUVY_TEST_CONFIG_DIR/backup"
        export JUVY_LOG="$JUVY_TEST_CONFIG_DIR/log"
        
        # Source juvy.zsh
        source "$(dirname "${(%):-%x}")/../../juvy/juvy.zsh"
        
        # Override the global variables after sourcing to ensure they stick
        typeset -g JUVY_CONFIG_DIR="$JUVY_TEST_CONFIG_DIR"
        typeset -g JUVY_CONFIG="$JUVY_TEST_CONFIG_DIR/config"
        typeset -g JUVY_BACKUP="$JUVY_TEST_CONFIG_DIR/backup"
        typeset -g JUVY_LOG="$JUVY_TEST_CONFIG_DIR/log"
        
        # Create default config with test backup directory
        echo "JUVY_BACKUP_DIR='$JUVY_TEST_BACKUP_DIR'" > "$JUVY_CONFIG"
        
        # Restore original HOME for the environment
        export HOME="$original_home"
        
        # But keep juvy paths pointing to test directories
        _JUVY_CONFIG[backup_dir]="$JUVY_TEST_BACKUP_DIR"
    }
    
    # Return setup info
    print "Test environment created:"
    print "  Test root: $test_root"
    print "  Fake home: $fake_home"
    print "  Backup dir: $backup_dir"
    print "  Config dir: $juvy_config_dir"
    print "  Fixture set: $fixture_set"
    print ""
    print "To use juvy in tests, call: load_juvy_for_test"
    print "To load fixtures, call: load_test_fixtures"
}

# Function to load fixtures from specified fixture set
load_test_fixtures() {
    [[ -z "$JUVY_TEST_ROOT" ]] && { print "Error: Test environment not set up" >&2; return 1; }
    [[ -z "$JUVY_TEST_FIXTURE_SET" ]] && { print "Error: No fixture set specified" >&2; return 1; }
    
    local fixture_dir="$(dirname "${(%):-%x}")/fixtures/$JUVY_TEST_FIXTURE_SET"
    
    if [[ ! -d "$fixture_dir" ]]; then
        print "Error: Fixture set '$JUVY_TEST_FIXTURE_SET' not found at $fixture_dir" >&2
        return 1
    fi
    
    # Copy all fixture files to appropriate locations in fake filesystem
    local fixture_file
    while IFS= read -r -d '' fixture_file; do
        local relative_path="${fixture_file#$fixture_dir/}"
        local target_path
        
        # Determine target location based on fixture file path
        case "$relative_path" in
            home/*)
                # Files in fixtures/setname/home/ go to fake home directory
                target_path="$JUVY_TEST_HOME/${relative_path#home/}"
                ;;
            etc/*)
                # Files in fixtures/setname/etc/ go to fake /etc
                target_path="$JUVY_TEST_ROOT/$relative_path"
                ;;
            usr/*)
                # Files in fixtures/setname/usr/ go to fake /usr
                target_path="$JUVY_TEST_ROOT/$relative_path"
                ;;
            *)
                # Default: files go to fake home directory
                target_path="$JUVY_TEST_HOME/$relative_path"
                ;;
        esac
        
        # Create target directory and copy file
        mkdir -p "$(dirname "$target_path")"
        cp "$fixture_file" "$target_path"
        
    done < <(find "$fixture_dir" -type f -print0)
    
    print "Fixtures loaded from: $fixture_dir"
    print "Files copied to test filesystem"
}

# Function to create backup entries from fixture manifest
create_backup_entries_from_fixtures() {
    [[ -z "$JUVY_TEST_CONFIG_DIR" ]] && { print "Error: Test environment not set up" >&2; return 1; }
    [[ -z "$JUVY_TEST_FIXTURE_SET" ]] && { print "Error: No fixture set specified" >&2; return 1; }
    
    local fixture_dir="$(dirname "${(%):-%x}")/fixtures/$JUVY_TEST_FIXTURE_SET"
    local manifest_file="$fixture_dir/backup-entries"
    
    if [[ -f "$manifest_file" ]]; then
        # Use manifest file if it exists
        cp "$manifest_file" "$JUVY_TEST_CONFIG_DIR/backup"
        print "Backup entries loaded from: $manifest_file"
    else
        # Auto-generate backup entries from fixture files
        local backup_entries=()
        
        while IFS= read -r -d '' fixture_file; do
            local relative_path="${fixture_file#$fixture_dir/}"
            
            case "$relative_path" in
                home/*)
                    # Convert home/path to ~/path
                    backup_entries+=("~/${relative_path#home/}")
                    ;;
                etc/*)
                    # System files use absolute paths
                    backup_entries+=(("/$relative_path"))
                    ;;
                usr/*)
                    # System files use absolute paths
                    backup_entries+=(("/$relative_path"))
                    ;;
                backup-entries)
                    # Skip manifest file
                    ;;
                *)
                    # Default: treat as home files
                    backup_entries+=("~/$relative_path")
                    ;;
            esac
            
        done < <(find "$fixture_dir" -type f -print0)
        
        # Write backup entries
        printf '%s\n' "${backup_entries[@]}" > "$JUVY_TEST_CONFIG_DIR/backup"
        print "Auto-generated backup entries: ${backup_entries[*]}"
    fi
}

# Function to cleanup test environment
cleanup_test_env() {
    [[ -n "$JUVY_TEST_ROOT" && -d "$JUVY_TEST_ROOT" ]] && rm -rf "$JUVY_TEST_ROOT"
    unset JUVY_TEST_ROOT JUVY_TEST_HOME JUVY_TEST_BACKUP_DIR JUVY_TEST_CONFIG_DIR JUVY_TEST_USER JUVY_TEST_FIXTURE_SET
    print "Test environment cleaned up"
}

# If script is run directly, set up test environment
if [[ "${(%):-%x}" == "${0:A}" ]]; then
    setup_juvy_test_env "${1:-interactive}" "${2:-testuser}" "${3:-default}"
fi