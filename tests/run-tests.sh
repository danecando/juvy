#!/usr/bin/env zsh
set -e
emulate -L zsh
setopt nullglob
BASE_DIR="$(dirname "$0")"
PASS=0
FAIL=0

for test_file in "$BASE_DIR"/unit/*.zsh "$BASE_DIR"/integration/*.zsh; do
  [ -f "$test_file" ] || continue
  echo "Running $(basename "$test_file")"
  if zsh "$test_file"; then
    echo "✔ $(basename "$test_file")"
    PASS=$((PASS+1))
  else
    echo "✖ $(basename "$test_file")" >&2
    FAIL=$((FAIL+1))
  fi
  echo
done

echo "Passed: $PASS"
echo "Failed: $FAIL"

[ $FAIL -eq 0 ] || exit 1
