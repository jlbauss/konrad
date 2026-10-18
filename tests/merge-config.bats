#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# image/merge-config.js — the layering contract every config layer relies on:
# objects merge, arrays replace, later layers win, and key order holds (opencode
# applies the LAST matching permission rule, so a layer's added rule must land
# after the baked ones).

load helpers

MERGE="$REPO_ROOT/image/merge-config.js"

layer() { printf '%s\n' "$2" > "$BATS_TEST_TMPDIR/$1"; printf '%s' "$BATS_TEST_TMPDIR/$1"; }

@test "objects merge recursively, later layers win" {
  run node "$MERGE" "$(layer a '{"p":{"x":1,"y":{"k":"a"}},"keep":true}')" \
                    "$(layer b '{"p":{"y":{"k":"b"},"z":3}}')"
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '{"p":{"x":1,"y":{"k":"b"},"z":3},"keep":true}' ]
}

@test "arrays replace, they never concatenate" {
  run node "$MERGE" "$(layer a '{"instructions":["a","b"]}')" "$(layer b '{"instructions":["c"]}')"
  [ "$(jq -c .instructions <<<"$output")" = '["c"]' ]
}

@test "key order: an overridden key keeps its place, an added key goes last" {
  run node "$MERGE" "$(layer a '{"edit":{"**":"allow","*.pem":"deny"}}')" \
                    "$(layer b '{"edit":{"**":"ask","*.p12":"deny"}}')"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.edit | to_entries | map(.key)' <<<"$output")" = '["**","*.pem","*.p12"]' ]
  [ "$(jq -r '.edit["**"]' <<<"$output")" = ask ]
}

@test "JSONC: comments go, comment markers inside strings stay" {
  run node "$MERGE" "$(layer a '// header
{ /* block */ "url": "http://host:1/v1", // trailing
  "glob": "a/*.md" }')"
  [ "$status" -eq 0 ]
  [ "$(jq -r .url <<<"$output")" = "http://host:1/v1" ]
  [ "$(jq -r .glob <<<"$output")" = "a/*.md" ]
}

@test "a malformed layer fails with its path, exit 2" {
  bad="$(layer bad '{"a": 1,}')"
  run node "$MERGE" "$(layer ok '{}')" "$bad"
  [ "$status" -eq 2 ]
  [[ "$output" == *"failed to parse $bad"* ]]
}

@test "no input is a usage error, exit 2" {
  run node "$MERGE"
  [ "$status" -eq 2 ]
  [[ "$output" == *usage* ]]
}

@test "a missing layer fails rather than merging nothing" {
  run node "$MERGE" "$(layer ok '{}')" "$BATS_TEST_TMPDIR/absent.jsonc"
  [ "$status" -ne 0 ]
}
