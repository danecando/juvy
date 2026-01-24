#!/usr/bin/env bash
# run-docker-tests.sh - Unified test runner for juvy
#
# Usage:
#   ./tests/run-docker-tests.sh              # Run all tests
#   ./tests/run-docker-tests.sh backup.bats  # Run specific test file
#   ./tests/run-docker-tests.sh --bash32     # Run with Bash 3.2
#   ./tests/run-docker-tests.sh --local      # Run locally without Docker
#
# Environment:
#   JUVY_TEST_BASH - Path to bash for testing (default: /bin/bash)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TEST_FILES...]

Run juvy tests using bats.

Options:
  --bash32    Run tests with Bash 3.2 (macOS compatibility)
  --local     Run tests locally without Docker
  --build     Rebuild Docker images before running tests
  --help      Show this help message

Examples:
  $(basename "$0")                    # Run all tests in Docker
  $(basename "$0") --bash32           # Run Bash 3.2 compatibility tests
  $(basename "$0") --local            # Run tests locally
  $(basename "$0") backup.bats        # Run specific test file
  $(basename "$0") --local *.bats     # Run all tests locally
EOF
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Build juvy.sh if scripts/build.sh exists
build_juvy() {
  if [[ -f "$PROJECT_ROOT/scripts/build.sh" ]]; then
    log_info "Building juvy.sh..."
    bash "$PROJECT_ROOT/scripts/build.sh"
  fi
}

# Run tests locally using bats
run_local_tests() {
  local test_files=("$@")

  # Check for bats
  if ! command -v bats >/dev/null 2>&1; then
    log_error "bats not found. Install with: npm install -g bats"
    log_error "Or use Docker: $(basename "$0") (without --local)"
    exit 1
  fi

  # Build juvy.sh
  build_juvy

  # Default to all test files if none specified
  if [[ ${#test_files[@]} -eq 0 ]]; then
    test_files=("$PROJECT_ROOT/tests/bats")
  else
    # Prepend path if just filename given
    local expanded=()
    for f in "${test_files[@]}"; do
      if [[ "$f" != /* && "$f" != "$PROJECT_ROOT"* ]]; then
        expanded+=("$PROJECT_ROOT/tests/bats/$f")
      else
        expanded+=("$f")
      fi
    done
    test_files=("${expanded[@]}")
  fi

  log_info "Running tests locally..."
  log_info "Bash version: $BASH_VERSION"

  # Set up bats library paths for local runs
  # Try common locations
  for lib_path in \
    "/usr/local/lib/bats" \
    "/opt/homebrew/lib" \
    "$HOME/.local/lib/bats" \
    "/usr/lib/bats"; do
    if [[ -d "$lib_path/bats-support" ]]; then
      export BATS_SUPPORT_DIR="$lib_path/bats-support"
    fi
    if [[ -d "$lib_path/bats-assert" ]]; then
      export BATS_ASSERT_DIR="$lib_path/bats-assert"
    fi
  done

  # Run bats
  bats "${test_files[@]}"
}

# Run tests in Docker
run_docker_tests() {
  local service="$1"
  shift
  local test_files=("$@")
  local rebuild="${REBUILD:-false}"

  # Check for docker compose
  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker not found. Install Docker or use --local flag."
    exit 1
  fi

  # Build juvy.sh
  build_juvy

  # Build containers if requested
  if [[ "$rebuild" == "true" ]]; then
    log_info "Building Docker images..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" build "$service"
  fi

  # Prepare bats command
  local bats_args=("tests/bats")
  if [[ ${#test_files[@]} -gt 0 ]]; then
    bats_args=()
    for f in "${test_files[@]}"; do
      if [[ "$f" != tests/* ]]; then
        bats_args+=("tests/bats/$f")
      else
        bats_args+=("$f")
      fi
    done
  fi

  log_info "Running tests in Docker ($service)..."

  # Run tests
  docker compose -f "$PROJECT_ROOT/docker-compose.yml" run --rm "$service" bats "${bats_args[@]}"
}

main() {
  local use_local=false
  local use_bash32=false
  local rebuild=false
  local test_files=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --local)
        use_local=true
        shift
        ;;
      --bash32)
        use_bash32=true
        shift
        ;;
      --build)
        rebuild=true
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        test_files+=("$1")
        shift
        ;;
    esac
  done

  # Export rebuild flag for docker function
  export REBUILD="$rebuild"

  if [[ "$use_local" == "true" ]]; then
    run_local_tests "${test_files[@]}"
  elif [[ "$use_bash32" == "true" ]]; then
    run_docker_tests "test-bash32" "${test_files[@]}"
  else
    run_docker_tests "test" "${test_files[@]}"
  fi

  log_info "All tests passed!"
}

main "$@"
