#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# bin/konrad's apple/container service check (container_service_check) against
# a stub `container` CLI that replays `container system status` fixtures, so no
# engine is needed.

load helpers

# The stub: `system status` prints $STUB_DIR/status, hangs when $STUB_DIR/hang
# exists, and fails as a stopped service does when $STUB_DIR/down exists. Any
# other call is appended to $STUB_DIR/calls, so a test can tell konrad changed
# nothing.
stub() {
  export STUB_DIR="$BATS_TEST_TMPDIR"
  mkdir -p "$STUB_DIR/bin" "$STUB_DIR/install"
  cat >"$STUB_DIR/bin/container" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "system status" ]]; then
  [[ -f "$STUB_DIR/hang" ]] && exec sleep 600
  [[ -f "$STUB_DIR/down" ]] && { echo "apiserver is not running"; exit 1; }
  exec cat "$STUB_DIR/status"
fi
echo "$*" >>"$STUB_DIR/calls"
EOF
  chmod +x "$STUB_DIR/bin/container"
  : >"$STUB_DIR/calls"
  export PATH="$STUB_DIR/bin:$PATH" KONRAD_ENGINE=container KONRAD_ENGINE_TIMEOUT=5
}

# Fixture: the table `container system status` prints (apple/container 1.6).
status_table() {  # $1 client version, $2 server version, $3 installRoot
  cat >"$STUB_DIR/status" <<EOF
FIELD               VALUE
status              running
client.version      $1
client.build        release
client.commit       0123abc
host.os             Version 26.1 (Build 25B78)
host.architecture   arm64
host.cpus           10
server.version      $2
server.build        release
server.commit       0123abc
server.appName      container-apiserver
paths.appRoot       /Users/someone/Library/Application Support/com.apple.container/
paths.installRoot   $3
paths.logRoot
containers.total    6
containers.running  0
images.total        3
EOF
}

# Run the check; konrad must not call the engine beyond `system status`.
check() {
  k 'container_service_check'
  [ ! -s "$STUB_DIR/calls" ]
}

GONE=/opt/homebrew/Cellar/container/1.6.0/

@test "container_service_check: matching versions, install present: fine" {
  stub; status_table 1.6.1 1.6.1 "$STUB_DIR/install/"
  check
  [ "$status" -eq 0 ]
}

@test "container_service_check: version mismatch: action needed" {
  stub; status_table 1.6.1 1.6.0 "$STUB_DIR/install/"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"it still runs container 1.6.0, but the installed CLI is 1.6.1"* ]]
}

@test "container_service_check: missing installRoot: action needed" {
  stub; status_table 1.6.1 1.6.1 "$GONE"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"which no longer exists"* ]]
}

# The reference case: 1.6.1 CLI, 1.6.0 service, its install gone.
@test "container_service_check: upgraded under a running service: action needed with the fix" {
  stub; status_table 1.6.1 1.6.0 "$GONE"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"fix: container system stop && container system start"* ]]
}

@test "container_service_check: older release without the table: fine" {
  stub; echo "apiserver is running" >"$STUB_DIR/status"
  check
  [ "$status" -eq 0 ]
}

@test "container_service_check: service not running: returns 1 so the caller starts it" {
  stub; : >"$STUB_DIR/down"
  check
  [ "$status" -eq 1 ]
}

@test "container_service_check: status hangs: action needed instead of a hang" {
  stub; : >"$STUB_DIR/hang"
  export KONRAD_ENGINE_TIMEOUT=1
  start=$SECONDS
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"didn't answer"* ]]
  [ $((SECONDS - start)) -lt 10 ]
}
