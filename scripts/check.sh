#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# konrad's static gates in one command — the same script on a host checkout,
# inside `konrad code` (no root, no apt) and in GitLab CI.
#
#     scripts/check.sh                    # every gate
#     scripts/check.sh shellcheck reuse   # just these
#
# Gates: bash-n, shellcheck, reuse, markdownlint, actionlint, hadolint. Each
# tool is fetched at a pinned version on first use (`uv tool run` for the
# Python-packaged binaries, `npx` for markdownlint) and cached by uv/npm after
# that, so the only prerequisites are uv, node and git. The pins below are
# bumped by hand; nothing else in the repo pins these tools.
#
# All selected gates run even when one fails; the exit code is non-zero if any
# failed, and the summary names which.
set -euo pipefail

cd "$(dirname "$0")/.."

SHELLCHECK='shellcheck-py==0.11.0.1'
REUSE='reuse[charset-normalizer]==6.2.0'
ACTIONLINT='actionlint-py==1.7.12.25'
HADOLINT='hadolint-bin==2.15.1'
MARKDOWNLINT='markdownlint-cli2@0.23.3'

ALL_GATES=(bash-n shellcheck reuse markdownlint actionlint hadolint)

# Every tracked shell script. bin/konrad has no .sh suffix, so it's named.
shell_files() {
  git ls-files '*.sh'
  echo bin/konrad
}

gate_bash_n() {
  local f rc=0
  while IFS= read -r f; do
    # Parse with the shell the script declares: install.sh is POSIX sh.
    case "$(head -n1 "$f")" in
      *bash*) bash -n "$f" || rc=1 ;;
      *) sh -n "$f" || rc=1 ;;
    esac
  done < <(shell_files)
  return "$rc"
}

gate_shellcheck() {
  local files
  mapfile -t files < <(shell_files)
  uv tool run --quiet --from "$SHELLCHECK" shellcheck "${files[@]}"
}

gate_reuse() {
  uv tool run --quiet --from "$REUSE" reuse lint --quiet
}

gate_markdownlint() {
  npx --yes "$MARKDOWNLINT"
}

gate_actionlint() {
  uv tool run --quiet --from "$ACTIONLINT" actionlint
}

gate_hadolint() {
  local files
  mapfile -t files < <(git ls-files '*Dockerfile')
  uv tool run --quiet --from "$HADOLINT" hadolint "${files[@]}"
}

for tool in uv npx git; do
  command -v "$tool" >/dev/null \
    || { echo "check.sh: '$tool' not found on PATH" >&2; exit 2; }
done

gates=("$@")
[ "${#gates[@]}" -gt 0 ] || gates=("${ALL_GATES[@]}")

failed=()
for gate in "${gates[@]}"; do
  case " ${ALL_GATES[*]} " in
    *" $gate "*) ;;
    *) echo "check.sh: unknown gate '$gate' (known: ${ALL_GATES[*]})" >&2; exit 2 ;;
  esac
  echo "==> $gate"
  if "gate_${gate//-/_}"; then
    echo "    ok"
  else
    failed+=("$gate")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "check.sh: FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "check.sh: all gates passed (${gates[*]})"
