#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Read this repo's GitLab API with the session's forge token, for agents in
# `konrad code`: merge requests are visible to project members only, so an MR's
# description, comments and pipelines need the token's read_api scope.
#
#   scripts/forge-api.sh merge_requests/94              # the MR, with its description
#   scripts/forge-api.sh merge_requests/94/discussions  # review comments
#   scripts/forge-api.sh merge_requests/94/pipelines    # its pipelines
#   scripts/forge-api.sh pipelines/<id>/jobs            # a pipeline's jobs
#   scripts/forge-api.sh jobs/<id>/trace                # a job's log
#   scripts/forge-api.sh 'merge_requests?state=opened'  # open MRs
#
# The path is relative to /api/v4/projects/<this project>/; GET only. The token
# comes from git's credential helper and reaches curl on stdin, so it shows up
# neither in the transcript nor on a command line.
set -euo pipefail

[[ $# -eq 1 && "$1" != /* ]] || { echo "usage: $0 <path under /api/v4/projects/:id/>" >&2; exit 2; }

remote="$(git remote get-url origin)"
remote="${remote#https://}"
remote="${remote#*@}"
host="${remote%%/*}"
project="${remote#*/}"
project="${project%.git}"

token="$(printf 'protocol=https\nhost=%s\n\n' "$host" | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[[ -n "$token" ]] || { echo "forge-api: no token for $host in git's credential store" >&2; exit 1; }

body="$(mktemp)"
trap 'rm -f "$body"' EXIT
code="$(printf 'header = "PRIVATE-TOKEN: %s"\n' "$token" \
  | curl -sS -m 30 --config - -o "$body" -w '%{http_code}' "https://$host/api/v4/projects/${project//\//%2F}/$1")"
case "$code" in
  2??) cat "$body" ;;
  403) echo "forge-api: 403 — the token lacks the read_api scope (create one with read_api + write_repository, role Developer)" >&2; exit 1 ;;
  *)   echo "forge-api: HTTP $code for $1" >&2; head -c 300 "$body" >&2; echo >&2; exit 1 ;;
esac
