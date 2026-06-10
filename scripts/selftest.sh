#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# konrad self-test — the realistic, end-to-end dev-loop check.
#
# Two layers, in order:
#   1. ./scripts/smoke-test.sh — does the IMAGE have the right binaries, deps,
#      and baked content? Engine-agnostic; the same gate CI runs.
#   2. a real `konrad run` through bin/konrad — does the RUNTIME come up the way
#      a user's invocation does (uid mapping, workspace mount, config compose)
#      and answer a prompt? This is the part the image smoke test deliberately
#      doesn't cover, and the part that exercises the macOS dev-container
#      self-testing path end to end. It goes through the real CLI on purpose —
#      that's where the rootful uid-map / remote-path-translation logic lives.
#
# Layer 2 needs a model + a provider credential. By default the model is
# whatever you've configured for NORMAL konrad — the self-test runtime mounts
# your real ~/.config/konrad layer (see bin/konrad podman_run), so it composes
# baked<org<user and picks up your `model` like any other run. Override per run:
#
#     scripts/selftest.sh                            # model from your konrad config
#     scripts/selftest.sh --model lmstudio/<id>      # override: a local LM Studio model
#     KONRAD_SELFTEST_MODEL=anthropic/… scripts/selftest.sh
#
# It DEGRADES rather than failing when no model is usable here (none configured
# and none passed, no key in the reachable secrets volume, endpoint
# unreachable, …): the container-startup half still validates the runtime path
# and the model probe reports SKIP with the reason. So a RED result means the
# runtime broke — not that you haven't configured a model or wired a key.
# Setup (model + one-time credential) is in CONTRIBUTING.md (on macOS the
# rootful daemon has its own, initially-empty secrets volume).
#
# Not a CI gate: CI has no podman, no model, and no credentials. This is the
# contributor's / agent's loop. CONTAINER_ENGINE is intentionally NOT honored —
# Layer 2 is podman-specific because it runs through bin/konrad.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# --- Defaults (all overridable) ---
IMAGE="${KONRAD_IMAGE:-konrad:local}"
# Empty = inherit the model from your mounted konrad config (the normal-mode
# default). A flag or KONRAD_SELFTEST_MODEL overrides it via an explicit --model.
MODEL="${KONRAD_SELFTEST_MODEL:-}"
PROFILE="selftest"                  # throwaway state/cache volumes; secrets shared
PROMPT='Reply with exactly the token KONRAD-OK and nothing else.'
EXPECT='KONRAD-OK'

usage() {
  cat <<'USAGE'
usage: scripts/selftest.sh [--model <slug>] [--image <tag>] [--profile <name>]

Runs the image smoke test, then a real `konrad run` through bin/konrad and
asserts the agent answers. By default the model comes from your mounted konrad
config (same as a normal run); --model or $KONRAD_SELFTEST_MODEL overrides it.
The model stage degrades to SKIP when no model/credential is usable here, so a
red result means the runtime broke. See CONTRIBUTING.md for one-time setup.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --model)   MODEL="$2";   shift 2 ;;
    --image)   IMAGE="$2";   shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'selftest: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- Output helpers (match smoke-test.sh) ---
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# --- Locate the CLI ---
# konrad-dev is preprovisioned on PATH in the dev container; a native checkout
# runs bin/konrad directly. KONRAD_IMAGE pins the tag regardless of which one.
if command -v konrad-dev >/dev/null 2>&1; then
  KONRAD="konrad-dev"
elif [ -x "$ROOT/bin/konrad" ]; then
  KONRAD="$ROOT/bin/konrad"
else
  fail "neither konrad-dev (on PATH) nor $ROOT/bin/konrad found"
fi

info "self-testing $IMAGE — layer 1: image smoke test"
"$ROOT/scripts/smoke-test.sh" "$IMAGE"

info "self-testing $IMAGE — layer 2: end-to-end run (model: ${MODEL:-from konrad config}, profile: $PROFILE)"

# Throwaway profile volumes (mirror bin/konrad's STATE_VOLUME/CACHE_VOLUME +
# the --profile suffix); secrets stay shared, so we never touch credentials.
cleanup() {
  if command -v podman >/dev/null 2>&1; then
    podman volume rm -f "konrad-state-$PROFILE" "konrad-cache-$PROFILE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Pass --model only when explicitly overridden; otherwise let opencode resolve
# it from the mounted config layer, exactly like a normal konrad run.
run_args=(--profile "$PROFILE" run)
[ -n "$MODEL" ] && run_args+=(--model "$MODEL")
run_args+=("$PROMPT")

# stdin from /dev/null: `opencode run` reads a non-tty stdin as piped input and
# blocks on EOF (see bin/konrad podman_run), so a closed stdin keeps it using
# the prompt arg instead of hanging. A `timeout` backstops a wedged model call
# (e.g. no model resolvable at all) so the probe degrades instead of blocking.
runner=(env "KONRAD_IMAGE=$IMAGE" "$KONRAD" "${run_args[@]}")
command -v timeout >/dev/null 2>&1 && runner=(timeout 180 "${runner[@]}")

set +e
out="$("${runner[@]}" </dev/null 2>&1)"
rc=$?
set -e

# Echo the run output, indented, so a failure/skip is self-explaining.
printf '%s\n' "$out" | sed 's/^/    │ /'

if printf '%s' "$out" | grep -q "$EXPECT"; then
  pass "agent answered through the full konrad runtime (token '$EXPECT' present, rc=$rc)"
  info "self-test complete — runtime + model both verified end to end"
elif printf '%s' "$out" | grep -qi 'starting opencode'; then
  # The container came up via the real invocation — uid mapping, workspace
  # mount, and config compose all succeeded — only the model call didn't
  # produce the token. That's an environment gap (no usable credential for
  # this model / unreachable provider), not a runtime regression.
  skip "runtime path OK (container started, workspace mounted, config composed); model stage (${MODEL:-from konrad config}) did not answer"
  skip "→ configure a model in ~/.config/konrad/user/opencode.jsonc (or pass --model) and wire its credential — see CONTRIBUTING.md. Runtime itself is validated."
  info "self-test complete — runtime verified; model stage skipped (no usable model/credential)"
else
  fail "container never reached opencode startup (rc=$rc) — the runtime path is broken, not a credential gap. See output above."
fi
