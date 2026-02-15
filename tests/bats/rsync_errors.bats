#!/usr/bin/env bats
# Tests for rsync error handling behavior

load test_helper

setup() {
  common_setup
}

teardown() {
  common_teardown
}

@test "_juvy_rsync_simple fails on generic partial transfer exit 23" {
  rsync() {
    echo "sent 123 bytes  received 45 bytes"
    return 23
  }

  run _juvy_rsync_simple "src" "dest"

  [ "$status" -ne 0 ]
}

@test "_juvy_rsync_simple can allow partial transfer for restore permission errors" {
  rsync() {
    echo "rsync: [receiver] mkstemp \"/etc/file\" failed: Permission denied (13)"
    echo "sent 123 bytes  received 45 bytes"
    return 23
  }

  run _juvy_rsync_simple --allow-partial "src" "dest"

  [ "$status" -eq 0 ]
}
