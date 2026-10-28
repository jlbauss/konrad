#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# A/B test two konrad images on the same tasks with a real model — the check
# for a change whose effect only shows in what the agent does with it (a skill
# swapped for an upstream one, a prompt edit). Each task in tests/ab/<task>/ is:
#
#   prompt.md   the request, passed to `konrad run` as is
#   input/      files copied into each run's fresh workspace
#   grade.py    run in the grader image with the workspace read-only; prints
#               {"checks": [{"name", "pass", "detail"}, ...]} (tests/ab/lib)
#
# Every run goes through bin/konrad (`konrad-dev run --format json`) under a
# throwaway profile, A and B interleaved so a provider hiccup hits both. konrad
# reads its config layers from $HOME, so the runs get a HOME of their own
# (podman keeps its store through XDG_*): your org and user layers, copied in as
# org layers so your providers work, under one layer of the harness's that
# allows `rm -rf`, the one `ask` rule. `konrad run` has no one to ask, so it
# rejects the call and opencode ends the run there, which says nothing about
# the change under test. Per
# run it keeps the workspace, the event stream and the grade; the report adds
# up score (share of checks passed), cost, time, steps and the skills loaded.
#
#   scripts/ab-test.sh --a konrad:ab-a --b konrad:local --runs 5 xlsx-create-report
#
# Podman only (like test-autoupdate.sh); needs jq and a connected provider key,
# a capped one in unattended runs (CONTRIBUTING → A real model in unattended runs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASKS="$ROOT/tests/ab"

A="konrad:latest"
B="konrad:local"
GRADER=""
RUNS=5
JOBS=3
MODEL="${KONRAD_AB_MODEL:-anthropic/claude-haiku-5-5}"
VARIANT="${KONRAD_AB_VARIANT:-low}"
TIMEOUT=900
OUT=""
SUFFIX=""

usage() {
  cat <<'USAGE'
usage: scripts/ab-test.sh [options] <task>...

  --a <image>         variant A (default konrad:latest)
  --b <image>         variant B (default konrad:local)
  --runs <n>          runs per variant and task (default 5)
  --jobs <n>          runs in parallel (default 3)
  --model <slug>      default $KONRAD_AB_MODEL or anthropic/claude-haiku-5-5
  --variant <effort>  reasoning effort, default $KONRAD_AB_VARIANT or low ('' = model default)
  --timeout <s>       per run (default 900)
  --grader <image>    image the graders run in (default: variant A)
  --prompt-suffix <text>  appended to every prompt, e.g. to make the agent load a
                      skill it would otherwise skip, so the skill's content gets measured
  --out <dir>         results (default .skill-eval/<timestamp>, gitignored)
  --report <dir>      only re-print the report of an earlier results dir

Tasks are the directories under tests/ab/ (ls tests/ab).
USAGE
}

die() { printf 'ab-test: %s\n' "$*" >&2; exit 1; }

# --- one run: called back through xargs as `ab-test.sh --trial …` -----------
trial() {
  local task="$1" side="$2" image="$3" n="$4" dir="$5"
  local ws="$dir/ws" profile="ab-$$-$side$n-${task//[^a-zA-Z0-9]/}"
  mkdir -p "$ws"
  cp -a "$TASKS/$task/input/." "$ws/"
  local args=(--profile "$profile" run --model "$MODEL" --format json)
  [ -n "$VARIANT" ] && args+=(--variant "$VARIANT")
  local start rc=0
  start="$(date +%s)"
  local prompt
  prompt="$(cat "$TASKS/$task/prompt.md")${SUFFIX:+

$SUFFIX}"
  (cd "$ws" && HOME="$AB_HOME" KONRAD_IMAGE="$image" timeout "$TIMEOUT" konrad-dev "${args[@]}" "$prompt") \
    </dev/null >"$dir/events.jsonl" 2>"$dir/stderr.txt" || rc=$?
  jq -n --arg task "$task" --arg side "$side" --arg image "$image" --argjson n "$n" \
    --argjson rc "$rc" --argjson seconds "$(( $(date +%s) - start ))" \
    '{task: $task, side: $side, image: $image, n: $n, rc: $rc, seconds: $seconds}' > "$dir/run.json"
  podman volume rm -f "konrad-state-$profile" "konrad-cache-$profile" >/dev/null 2>&1 || true
  podman run --rm --network none --entrypoint /opt/venv/bin/python \
    -v "$ws:/ws:ro,z" -v "$TASKS:/ab:ro,z" "$GRADER" "/ab/$task/grade.py" /ws \
    >"$dir/grade.json" 2>"$dir/grade.err" || true
  jq -e '.checks | length > 0' "$dir/grade.json" >/dev/null 2>&1 \
    || printf '{"checks":[{"name":"grader ran","pass":false,"detail":"see grade.err"}]}\n' > "$dir/grade.json"
  printf 'ab-test: %s %s#%s done (rc %s, %s/%s checks)\n' "$task" "$side" "$n" "$rc" \
    "$(jq '[.checks[] | select(.pass)] | length' "$dir/grade.json")" "$(jq '.checks | length' "$dir/grade.json")"
}

# --- the report: one record per run, then a summary per task ----------------
record() {
  local dir="$1"
  # A refused permission ends the run (exit 0): told apart from a bad answer.
  local refused
  refused="$(grep -c 'auto-rejecting' "$dir/stderr.txt" 2>/dev/null || true)"
  jq -n --slurpfile run "$dir/run.json" --slurpfile grade "$dir/grade.json" --argjson refused "${refused:-0}" \
    --slurpfile ev <(jq -cR 'fromjson? // empty' "$dir/events.jsonl") '
    ($grade[0].checks) as $c
    | [$ev[] | select(.type == "step_finish") | .part] as $steps
    | [$ev[] | select(.type == "tool_use") | .part] as $tools
    | $run[0] + {
        score: (if ($c | length) > 0 then ([$c[] | select(.pass)] | length) / ($c | length) else 0 end),
        checks: ($c | map({(.name): .pass}) | add),
        cost: ([$steps[].cost // 0] | add // 0),
        steps: ($steps | length),
        tools: ($tools | length),
        tool_errors: ([$tools[] | select(.state.status == "error")] | length),
        refused: ($refused > 0),
        skills: [$tools[] | select(.tool == "skill") | .state.input.name] }'
}

report() {
  local out="$1" task
  for dir in "$out"/*/[ab]-*/; do
    if [ -f "$dir/run.json" ] && [ -f "$dir/grade.json" ]; then record "$dir"; fi
  done | jq -s . > "$out/results.json"
  for task in $(jq -r '[.[].task] | unique[]' "$out/results.json"); do
    jq -r --arg t "$task" '
      [.[] | select(.task == $t)] as $r
      | def avg(f): if length > 0 then (map(f) | add / length) else 0 end;
        def side(s): [$r[] | select(.side == s)];
        def pct: . * 100 | round | tostring + "%";
        def num(d): . * pow(10; d) | round / pow(10; d) | tostring;
      "## \($t)\n",
      "| | A (\(side("a")[0].image // "-")) | B (\(side("b")[0].image // "-")) |",
      "| --- | --- | --- |",
      "| runs (exit 0) | \(side("a") | length) (\(side("a") | map(select(.rc == 0)) | length)) | \(side("b") | length) (\(side("b") | map(select(.rc == 0)) | length)) |",
      "| ended by a refused permission | \(side("a") | map(select(.refused)) | length) | \(side("b") | map(select(.refused)) | length) |",
      "| mean score | \(side("a") | avg(.score) | pct) | \(side("b") | avg(.score) | pct) |",
      "| all checks passed | \(side("a") | map(select(.score == 1)) | length) | \(side("b") | map(select(.score == 1)) | length) |",
      "| mean cost (USD) | \(side("a") | avg(.cost) | num(4)) | \(side("b") | avg(.cost) | num(4)) |",
      "| mean time (s) | \(side("a") | avg(.seconds) | round) | \(side("b") | avg(.seconds) | round) |",
      "| mean steps / tool calls / failed calls | \(side("a") | "\(avg(.steps) | num(1)) / \(avg(.tools) | num(1)) / \(avg(.tool_errors) | num(1))") | \(side("b") | "\(avg(.steps) | num(1)) / \(avg(.tools) | num(1)) / \(avg(.tool_errors) | num(1))") |",
      "| skills loaded (runs) | \(side("a") | [.[].skills | unique[]] | group_by(.) | map("\(.[0]) \(length)") | join(", ")) | \(side("b") | [.[].skills | unique[]] | group_by(.) | map("\(.[0]) \(length)") | join(", ")) |",
      "",
      "| check | A passed | B passed |",
      "| --- | --- | --- |",
      (reduce ($r[].checks | keys_unsorted[]) as $k ([]; if index([$k]) then . else . + [$k] end)
        | .[] as $k | "| \($k) | \(side("a") | map(select(.checks[$k])) | length)/\(side("a") | length) | \(side("b") | map(select(.checks[$k])) | length)/\(side("b") | length) |"),
      ""' "$out/results.json"
  done | tee "$out/report.md"
}

# --- arguments ---------------------------------------------------------------
if [ "${1:-}" = --trial ]; then
  shift
  MODEL="$1" VARIANT="$2" TIMEOUT="$3" GRADER="$4" AB_HOME="$5" SUFFIX="$6"
  shift 6
  trial "$@"
  exit 0
fi

tasks=()
while [ $# -gt 0 ]; do
  case "$1" in
    --a)       A="$2"; shift 2 ;;
    --b)       B="$2"; shift 2 ;;
    --runs)    RUNS="$2"; shift 2 ;;
    --jobs)    JOBS="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --grader)  GRADER="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    --prompt-suffix) SUFFIX="$2"; shift 2 ;;
    --report)  report "$2"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*)        usage >&2; die "unknown option: $1" ;;
    *)         tasks+=("$1"); shift ;;
  esac
done
[ "${#tasks[@]}" -gt 0 ] || { usage >&2; exit 2; }
for t in "${tasks[@]}"; do
  [ -f "$TASKS/$t/prompt.md" ] && [ -f "$TASKS/$t/grade.py" ] || die "no task '$t' in tests/ab/"
done
command -v konrad-dev >/dev/null 2>&1 || die "konrad-dev not on PATH (CONTRIBUTING → First-time setup)"
command -v jq >/dev/null 2>&1 || die "jq is needed for the report"
for img in "$A" "$B"; do
  podman image exists "$img" || die "no image $img (konrad-dev rebuild, or podman tag)"
done
GRADER="${GRADER:-$A}"
OUT="${OUT:-$ROOT/.skill-eval/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

AB_HOME="$OUT/home"
cfg="$HOME/.config/konrad"
mkdir -p "$AB_HOME/.config/konrad/org" "$AB_HOME/.config/konrad/user"
if [ -d "$cfg/org" ]; then cp -a "$cfg/org/." "$AB_HOME/.config/konrad/org/"; fi
if [ -d "$cfg/user" ]; then cp -a "$cfg/user" "$AB_HOME/.config/konrad/org/zz-user"; fi
printf '{ "permission": { "bash": { "rm -rf *": "allow" } } }\n' > "$AB_HOME/.config/konrad/user/opencode.jsonc"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

printf 'ab-test: %s task(s) × %s runs × A=%s, B=%s · %s%s · %s in parallel → %s\n' \
  "${#tasks[@]}" "$RUNS" "$A" "$B" "$MODEL" "${VARIANT:+ ($VARIANT)}" "$JOBS" "$OUT"
printf '%s\n' "$SUFFIX" > "$OUT/prompt-suffix.txt"
for t in "${tasks[@]}"; do
  for n in $(seq 1 "$RUNS"); do
    printf '%s\0a\0%s\0%s\0%s\0' "$t" "$A" "$n" "$OUT/$t/a-$n"
    printf '%s\0b\0%s\0%s\0%s\0' "$t" "$B" "$n" "$OUT/$t/b-$n"
  done
done | xargs -0 -n 5 -P "$JOBS" "$0" --trial "$MODEL" "$VARIANT" "$TIMEOUT" "$GRADER" "$AB_HOME" "$SUFFIX"

printf '\n'
report "$OUT"
printf '\nab-test: per-run workspaces, events and grades under %s\n' "$OUT"
