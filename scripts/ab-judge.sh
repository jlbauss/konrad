#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Blind judging of an ab-test.sh results dir: how good the deliverables are,
# beyond the pass/fail checks of each task's grader. The judges are agents
# in the session that runs this (subagents, a cheaper model such as Sonnet at
# medium effort), never told which side is which:
#
#   scripts/ab-judge.sh blind  <results dir>   # packets + batches in <results dir>.judge/
#   (hand each line of <results dir>.judge/batches.txt to one subagent, with
#    <results dir>.judge/JUDGE.md as its instructions; each writes verdict.json
#    into its packets)
#   scripts/ab-judge.sh report <results dir> [--a-name Haiku --b-name Qwen]
#                              [--show <task>:<run>:<page>[,<page>]]…
#                                              # <results dir>/report/: README.md + img/
#
# A packet holds the task, its input and both deliverables as page renders,
# text and speaker notes, never the files or the agents' notes. Every pair is
# judged twice with X and Y swapped, by different subagents; it counts for a
# side only when both agree. report/ is the standard report for an MR, which
# commits it as tests/ab/reports/<date>-<name>/: a short study in Markdown with
# the graded checks, the verdicts and the clearest pairs side by side.
# The work runs in a konrad image (LibreOffice, python-docx, python-pptx);
# Podman only, like the judging itself, which happens in an agent session.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
die() { printf 'ab-judge: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '9,17p' "$0" | sed 's/^# \{0,1\}//'; }

[ $# -ge 2 ] || { usage >&2; exit 2; }
cmd="$1" results="$2"
shift 2
[ -f "$results/results.json" ] || die "no ab-test results in $results"
results="$(cd "$results" && pwd)"
judge="$results.judge"
image="$(jq -r '.b // empty' "$results/settings.json" 2>/dev/null || true)"
image="${AB_JUDGE_IMAGE:-${image:-konrad:local}}"
podman image exists "$image" || die "no image $image (set AB_JUDGE_IMAGE)"
mkdir -p "$judge"

run() {
  podman run --rm --network none --userns=keep-id --entrypoint /opt/venv/bin/python \
    -v "$results:/results:z" -v "$judge:/judge:z" -v "$ROOT/tests/ab:/ab:ro,z" "$image" /ab/lib/abjudge.py "$@"
}

case "$cmd" in
  blind)  run blind /results /judge /ab "$judge" "$@"
          printf 'ab-judge: batches in %s/batches.txt, instructions in %s/JUDGE.md\n' "$judge" "$judge" ;;
  report) run report /results /judge --name "$(basename "$results")" "$@"
          printf 'ab-judge: %s/report/ (commit it as tests/ab/reports/<date>-<name>/)\n' "$results" ;;
  *)      usage >&2; exit 2 ;;
esac
