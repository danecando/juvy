#!/usr/bin/env bash
set -e

BASE_DIR="$(dirname "$0")"
PASS=0
FAIL=0

shopt -s nullglob

for test_file in "$BASE_DIR"/unit/*.sh "$BASE_DIR"/integration/*.sh; do
  [ -f "$test_file" ] || continue
  echo "Running $(basename "$test_file")"
  output_file=$(mktemp)
  if bash "$test_file" >"$output_file" 2>&1; then
    echo "OK $(basename "$test_file")"
    PASS=$((PASS+1))
  else
    echo "FAILED $(basename "$test_file")" >&2
    echo "--- Output from failed test ---" >&2
    cat "$output_file" >&2
    echo "--- End of output ---" >&2
    FAIL=$((FAIL+1))
  fi
  rm -f "$output_file"
  echo
done

echo "Passed: $PASS"
echo "Failed: $FAIL"

[ $FAIL -eq 0 ] || exit 1
