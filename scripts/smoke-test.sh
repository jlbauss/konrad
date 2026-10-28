#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Smoke test the konrad image. Runs in CI before publishing to the
# registry — if any check fails, the daily build does not move the
# `:latest` tag and last-known-good keeps serving users. Also runnable
# locally:
#
#   ./scripts/smoke-test.sh                       # tests konrad:latest
#   ./scripts/smoke-test.sh my-tag:1.2            # tests an arbitrary tag
#   CONTAINER_ENGINE=docker ./scripts/smoke-test.sh   # use docker not podman
#
# Engine selection: an explicit CONTAINER_ENGINE wins (CI sets docker, where
# podman isn't installed). Otherwise we mirror konrad's own choice — KONRAD_ENGINE
# if set, else auto: Apple's `container` on Apple-Silicon macOS when present, else
# podman — so a local `konrad-dev rebuild && ./scripts/smoke-test.sh` inspects
# the SAME image store konrad just built into (a `container build` lands the image
# in container's store, not podman's). All three engines accept the flags we use
# (`run --rm --entrypoint ""`, `image inspect`).
#
# The checks are deliberately "installed and importable" rather than
# "agent runs end-to-end" — exercising opencode requires a model
# provider, which is user-specific. Catching basic install regressions is
# what makes the float-everything pinning strategy safe.
set -euo pipefail

IMAGE="${1:-konrad:latest}"
if [ -n "${CONTAINER_ENGINE:-}" ]; then
  ENGINE="$CONTAINER_ENGINE"
elif [ -n "${KONRAD_ENGINE:-}" ]; then
  ENGINE="$KONRAD_ENGINE"
elif [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && command -v container >/dev/null 2>&1; then
  ENGINE="container"
else
  ENGINE="podman"
fi

# --- Output helpers ---
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
info() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# Run a one-shot command inside the image, no workspace mount needed.
in_image() { "$ENGINE" run --rm --entrypoint "" "$IMAGE" "$@"; }

info "smoke-testing $IMAGE (engine: $ENGINE)"

# --- 1. Image exists ---
# `image inspect` returns non-zero if the image is missing — works in both
# docker and podman (whereas `image exists` is podman-only).
"$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1 \
  || fail "image $IMAGE not found locally — build or pull it first"
pass "image present"

# --- 2. Core binaries on PATH ---
# Names here MUST match the actual binary names in the image, not the
# Debian package names: ripgrep installs `rg`; fd-find installs `fdfind`
# (Dockerfile symlinks to `fd`); bat installs `batcat` (Dockerfile
# symlinks to `bat`). See image/Dockerfile's apt-get install + symlink
# block.
info "core binaries"
for bin in opencode node npm python3 uv typst jq git rg fd bat tree gh pandoc; do
  in_image which "$bin" >/dev/null \
    || fail "$bin not on PATH"
  pass "$bin"
done

# --- 3. Tool versions print (catches broken installs) ---
info "version probes"
in_image node    --version >/dev/null || fail "node --version failed"
in_image npm     --version >/dev/null || fail "npm --version failed"
in_image python3 --version >/dev/null || fail "python3 --version failed"
in_image uv      --version >/dev/null || fail "uv --version failed"
in_image typst   --version >/dev/null || fail "typst --version failed"
in_image opencode --version >/dev/null || fail "opencode --version failed"
pass "all version probes returned 0"

# --- 4. Python skill deps import ---
# Invoke the venv python directly (not `python3` on PATH) so we are
# guaranteed to hit the docling-bearing interpreter, not the system one.
info "python skill imports"
in_image /opt/venv/bin/python -c '
import docling          # EXTRACT route
import pypdf            # EDIT route
import pdfplumber       # region discovery
import pdf2image        # rasterization
import reportlab        # GENERATE route
import openpyxl, pandas # xlsx skill
import docx, pptx       # Word and PowerPoint files
import onnxruntime      # rapidocr engine
print("ok")
' >/dev/null || fail "python skill imports failed"
pass "docling, pypdf, pdfplumber, pdf2image, reportlab, openpyxl, pandas, docx, pptx, onnxruntime"

# --- 5. Build manifest exists and parses ---
info "build manifest"
in_image test -f /etc/konrad/build-manifest.json \
  || fail "/etc/konrad/build-manifest.json missing"
in_image jq -e '.konrad.version, .konrad.build_date, .tooling.node, .apt[0], .python[0]' \
  /etc/konrad/build-manifest.json >/dev/null \
  || fail "manifest JSON missing expected keys"
KONRAD_VER=$(in_image jq -r .konrad.version /etc/konrad/build-manifest.json)
BUILD_DATE=$(in_image jq -r .konrad.build_date /etc/konrad/build-manifest.json)
pass "manifest valid (konrad=$KONRAD_VER, built=$BUILD_DATE)"

# --- 6. Bundled config files in place ---
# Cross-referenced against image/Dockerfile's COPY block. Two distinct
# trees: /etc/konrad/ (root-owned, used by the entrypoint) and
# /home/node/.config/opencode/ (opencode-discoverable, where agents,
# skills, and instructions/environment.md live — *not*
# /etc/konrad/environment.md; the Dockerfile keeps it in the
# opencode-discoverable dir intentionally so edits don't invalidate the npm
# layer).
info "baked content"
# Entrypoint + config-merge machinery
in_image test -x /usr/local/bin/konrad-entrypoint \
  || fail "konrad-entrypoint missing or non-executable"
in_image test -f /etc/konrad/merge-config.js \
  || fail "merge-config.js missing"
# Inline model-discovery probe — run by the entrypoint at session start, so it
# must be baked and executable (COPY --chmod=0755 of konrad-defaults/).
in_image test -x /etc/konrad/discover-models.sh \
  || fail "discover-models.sh missing or non-executable"
# apple/container egress seal + local-model host alias depend on the shared
# privilege-drop helper, a privilege-drop tool (setpriv preferred), and `ip`
# (iproute2). Missing any would make the root prelude fail closed and abort the
# run on that engine, so assert them here even though they're inert on Podman.
in_image test -f /usr/local/lib/konrad-privdrop.sh \
  || fail "konrad-privdrop.sh missing (apple/container seal helper)"
in_image sh -c 'command -v setpriv || command -v gosu || command -v runuser' >/dev/null \
  || fail "no privilege-drop tool (setpriv/gosu/runuser) — apple/container root prelude can't drop to node"
in_image which ip >/dev/null \
  || fail "ip (iproute2) missing — apple/container egress seal can't install the blackhole route"
# konrad code's entrypoint (the host/LAN seal + clone + agent launch).
in_image test -x /usr/local/bin/konrad-code \
  || fail "konrad-code missing or non-executable (konrad code entrypoint)"
# ...and the label bin/konrad's preflight keys on (grep over the inspect JSON:
# the one shape docker, podman and apple/container all print).
"$ENGINE" image inspect "$IMAGE" 2>/dev/null | grep '"io.konrad.code"' >/dev/null \
  || fail "io.konrad.code label missing — konrad code would refuse this image"
# konrad code --nested: rootless podman, with the uid mappers as the ONLY
# privileged binaries (file capabilities, inert unless --nested keeps
# setuid,setgid in the bounding set) and no setuid/setgid file left at all.
for bin in podman crun pasta newuidmap newgidmap nft; do
  in_image which "$bin" >/dev/null || fail "$bin missing (konrad code --nested)"
done
[ "$(in_image sh -c 'getcap -r / 2>/dev/null | cut -d" " -f1 | sort | tr "\n" " "')" \
    = "/usr/bin/newgidmap /usr/bin/newuidmap " ] \
  || fail "file capabilities other than the two uid mappers (or the mappers lack them)"
[ "$(in_image sh -c 'find / -xdev -type f -perm /6000 2>/dev/null | wc -l')" = 0 ] \
  || fail "setuid/setgid files in the image — the uid mappers must be the only privileged binaries"
in_image grep -qx 'node:1001:64535' /etc/subuid || fail "/etc/subuid lacks node's range"
[ "$(in_image stat -c %U /var/lib/konrad-containers)" = node ] \
  || fail "/var/lib/konrad-containers missing or not node-owned (nested image store)"
in_image test -f /etc/konrad/opencode-defaults.jsonc \
  || fail "opencode-defaults.jsonc missing"
# opencode-discoverable content. environment.md is the baked layer's
# instructions/ dir entry — composed onto the system `instructions` channel by
# the entrypoint (the additive baked < org < user convention), not an explicit
# opencode.jsonc key.
in_image test -f /home/node/.config/opencode/instructions/environment.md \
  || fail "instructions/environment.md missing"
in_image test -f /home/node/.config/opencode/agents/konrad.md \
  || fail "konrad agent missing"
for skill in do-it-manually pdf quality-assurance; do
  in_image test -d "/home/node/.config/opencode/skills/$skill" \
    || fail "$skill skill missing"
done
# Every skill pinned in skills.lock, as opencode itself lists it: present,
# and with frontmatter it accepts (a skill opencode rejects is skipped silently).
SKILLS_LOCK="$(cd "$(dirname "$0")/.." && pwd)/image/locks/skills.lock"
listed="$(in_image opencode debug skill | jq -r '.[].name')" \
  || fail "opencode debug skill failed"
while read -r skill _; do
  case "$skill" in ''|\#*) continue ;; esac
  printf '%s\n' "$listed" | grep -x "$skill" >/dev/null \
    || fail "$skill (skills.lock) not among the skills opencode lists"
done < "$SKILLS_LOCK"
# Bundled fonts
in_image test -d /usr/local/share/fonts/konrad \
  || fail "bundled fonts missing"
pass "entrypoint, defaults, agents, skills, and fonts present"

# --- 7. End-to-end: docling extracts a tiny PDF ---
# Catches regressions in the docling/onnxruntime/rapidocr chain that
# version probes alone won't detect.
info "docling end-to-end"
in_image bash -c '
set -e
cd /tmp
# Minimal 1-page PDF with the text "smoke" — generated by reportlab so
# we do not depend on having a test fixture in the image. Invoke the
# venv python explicitly so reportlab resolves to the right interpreter.
/opt/venv/bin/python -c "
from reportlab.pdfgen import canvas
c = canvas.Canvas(\"/tmp/smoke.pdf\")
c.drawString(100, 750, \"smoke\")
c.save()
"
docling /tmp/smoke.pdf --to md --output /tmp/out >/dev/null
grep -qi smoke /tmp/out/smoke.md
' || fail "docling round-trip failed"
pass "docling extracted a generated PDF"

# --- 8. Org config layer: entrypoint composes baked < org < user ---
# Unlike the checks above, this RUNS the real entrypoint (not --entrypoint "")
# with org/ and user/ layers bind-mounted, then inspects the composed config.
# /workspace is baked node-owned, so the entrypoint's .agent bootstrap works
# without a workspace mount. ':ro,z' relabels for SELinux hosts (Fedora local
# podman) and is accepted/ignored by docker in CI.
info "org config layer (entrypoint compose)"
ORG_TMP="$(mktemp -d)"
USER_TMP="$(mktemp -d)"
cleanup_org() { rm -rf "$ORG_TMP" "$USER_TMP"; }
trap cleanup_org EXIT
# org/ is a CONTAINER of named layers (org/<name>/), folded alphabetically
# between baked and user. Two layers here so the org₁ < org₂ order is asserted,
# not assumed. Layer 10-acme: an internal provider (with a baseURL, so the
# firewall derivation below must surface its host), an AGENTS.md, an
# instructions/ file, a skill, and an allowed_hosts file. It deliberately uses
# opencode.JSON (not .jsonc) — with 20-beta/user on .jsonc — so both extensions
# are exercised across the compose AND the firewall derivation (a layer whose
# config is opencode.json was silently dropped from the allow-list before the
# fix that made every config-file consumer accept either extension).
mkdir -p "$ORG_TMP/10-acme/instructions" "$ORG_TMP/10-acme/skills/house-style" "$ORG_TMP/20-beta"
cat > "$ORG_TMP/10-acme/opencode.json" <<'JSON'
{ "env": { "ORG_MARKER": "acme" },
  "provider": { "acme": { "npm": "@ai-sdk/openai-compatible", "name": "ACME (org)",
                          "options": { "baseURL": "https://llm.acme.example/v1" },
                          "models": { "m1": { "name": "M1" } } } } }
JSON
printf '# org rules\n' > "$ORG_TMP/10-acme/AGENTS.md"
printf '# org house rules\n' > "$ORG_TMP/10-acme/instructions/house-rules.md"
printf -- '---\nname: house-style\ndescription: example\n---\n# House\n' \
  > "$ORG_TMP/10-acme/skills/house-style/SKILL.md"
printf 'wiki.acme.example\n' > "$ORG_TMP/10-acme/allowed_hosts"
# Layer 20-beta: overrides the marker — alphabetically later must win.
cat > "$ORG_TMP/20-beta/opencode.jsonc" <<'JSON'
{ "env": { "ORG_MARKER": "beta" } }
JSON
# User layer: override the org provider's display name — the user must win.
cat > "$USER_TMP/opencode.jsonc" <<'JSON'
{ "provider": { "acme": { "name": "ACME (user override)" } } }
JSON
# User-layer additive instruction file (same instructions/ dir convention).
mkdir -p "$USER_TMP/instructions"
printf '# user rules\n' > "$USER_TMP/instructions/my-rules.md"
# mktemp -d makes dirs 0700. The smoke test doesn't use --userns=keep-id (it
# must also run under docker in CI), so the container's `node` uid isn't the
# owner of these host dirs and couldn't traverse 0700. Open them up so the
# bind mounts are readable regardless of uid mapping (',z' below handles
# SELinux separately). Real konrad doesn't need this — keep-id maps the host
# user to node so its own ~/.config/konrad files are readable as-is.
chmod -R a+rX "$ORG_TMP" "$USER_TMP"
# The in-container assertions are a quoted heredoc fed to `bash -s` on stdin
# (-i keeps stdin open) — quoted so the $cfg / $(...) below are the container
# shell's, not this script's.
"$ENGINE" run --rm -i \
  -v "$ORG_TMP:/home/node/.config/konrad/org:ro,z" \
  -v "$USER_TMP:/home/node/.config/konrad/user:ro,z" \
  "$IMAGE" bash -s <<'CONTAINER' || fail "org-layer compose/precedence/instructions/skill assertion failed"
set -e
cfg=/home/node/.config/opencode/opencode.jsonc
# org provider + model merged in
jq -e '.provider.acme.models.m1' "$cfg" >/dev/null
# baked default survived the merge (proves the fold, not a clobber)
jq -e '.provider.lmstudio' "$cfg" >/dev/null
# ORG-vs-ORG precedence: the alphabetically later layer (20-beta) wins
[ "$(jq -r '.env.ORG_MARKER' "$cfg")" = "beta" ]
# USER precedence: user override of the name wins over every org layer
[ "$(jq -r '.provider.acme.name' "$cfg")" = "ACME (user override)" ]
# The baked .instructions array holds exactly the baked + user globs; org
# layers get no entry (opencode globs only the basename component, so an
# org/*/… glob could never match — their files are COPIED instead, below).
jq -e '.instructions | index("/home/node/.config/opencode/instructions/*.md")' "$cfg" >/dev/null
jq -e '.instructions | index("/home/node/.config/konrad/user/instructions/*.md")' "$cfg" >/dev/null
jq -e '.instructions | index("/home/node/.config/konrad/org/instructions/*.md") | not' "$cfg" >/dev/null
# Org instruction files (and back-compat AGENTS.md) copied into the baked
# instructions/ dir under the org-<layer>- prefix, where the baked glob
# picks them up.
test -f /home/node/.config/opencode/instructions/org-10-acme-house-rules.md
test -f /home/node/.config/opencode/instructions/org-10-acme-AGENTS.md
# The user's instruction file is matched in place by its own glob.
test -f /home/node/.config/konrad/user/instructions/my-rules.md
# baked layer's instruction file (the runtime-environment manifest) is in place
test -f /home/node/.config/opencode/instructions/environment.md
# org skill copied into the opencode skills dir
test -f /home/node/.config/opencode/skills/house-style/SKILL.md
# Firewall derivation enumerates EVERY org layer: the provider baseURL host
# and the layer's allowed_hosts entry must both surface (a missed layer would
# silently block that org's internal provider at the proxy).
/etc/konrad/compose-allowed-hosts.sh > /tmp/allowed-hosts
grep -qx 'llm.acme.example'  /tmp/allowed-hosts
grep -qx 'wiki.acme.example' /tmp/allowed-hosts
CONTAINER
pass "org layers merge in order under user precedence; instructions copy; skill loads; firewall sees every layer"

# --- 9. opencode honours konrad's config ---
# opencode drops config keys it doesn't know without a word (exit 0, gone from
# `opencode debug config`), and the lock bot auto-merges every opencode release,
# so an upstream rename would strip konrad's permission rules while every other
# gate stays green. So ask opencode itself, through the real entrypoint and the
# baked layer alone (what a fresh install gets), what it resolved — and for the
# denies, *call the tool* (`debug agent <name> --tool`), which runs it under
# the agent's resolved permissions: that also catches rules that are present
# but don't hold (opencode applies the last matching rule, so a catch-all listed
# after a deny voids it). Every deny is paired with a control on the same tool
# that must succeed, so a deny can't pass because the call broke for another
# reason. `ask` auto-approves under --tool, so `rm -rf`'s ask is read off the
# resolved rule list instead.
info "opencode honours konrad's config (resolved config + enforced permissions)"
"$ENGINE" run --rm -i "$IMAGE" bash -s <<'CONTAINER' || fail "opencode no longer honours konrad's config — see the failing check above (an opencode bump may have renamed a key)"
set -euo pipefail
cd /workspace
no() { printf '  check failed: %s\n' "$*" >&2; exit 1; }

# Resolved config: the keys konrad's UX rests on.
cfg="$(mktemp)"
opencode debug config > "$cfg" || no "opencode debug config failed"
jq -e '.default_agent == "konrad"'      "$cfg" >/dev/null || no "default_agent is not konrad"
jq -e '.agent.build.disable == true'    "$cfg" >/dev/null || no "built-in build agent not disabled"
jq -e '.agent.plan.disable == true'     "$cfg" >/dev/null || no "built-in plan agent not disabled"
jq -e '.autoupdate == false'            "$cfg" >/dev/null || no "autoupdate not off"

# tool <agent> <tool> <params-json>: run one tool call as <agent>; the output
# lands in $out. Returns the call's exit status.
out="$(mktemp)"
tool() { opencode debug agent "$1" --tool "$2" --params "$3" > "$out" 2>&1; }
# The two refusals opencode prints: a deny on a pattern, and a tool denied
# outright (removed from the agent). If upstream rewords them, denies stop
# matching and this check fails loudly — the safe direction.
REFUSED='prevents you from using this specific tool call|is disabled for agent'
allowed() { tool "$@" || { cat "$out" >&2; no "control call refused or failed: $1 $2 $3"; }; }
denied()  { if tool "$@"; then no "allowed, should be denied: $1 $2 $3"; fi
            grep -E "$REFUSED" "$out" >/dev/null || { cat "$out" >&2; no "failed without a permission refusal: $1 $2 $3"; }; }

# The secrets volume (auth.json) is out of the agent's reach.
mkdir -p /home/node/.opencode-secrets /tmp/ctl
echo probe > /home/node/.opencode-secrets/probe
echo probe > /tmp/ctl/probe
allowed konrad read '{"filePath":"/tmp/ctl/probe"}'
denied  konrad read '{"filePath":"/home/node/.opencode-secrets/probe"}'
allowed konrad bash '{"command":"cat /tmp/ctl/probe","description":"control"}'
denied  konrad bash '{"command":"cat /home/node/.opencode-secrets/probe","description":"probe"}'

# Edits to secrets and repo integrity are refused; ordinary files are not.
allowed konrad write '{"filePath":"/workspace/ok.txt","content":"x"}'
for f in .env .git/config id.key cert.pem token.secret node_modules/x.js; do
  denied konrad write "{\"filePath\":\"/workspace/$f\",\"content\":\"x\"}"
done

# Root and host container/cluster control are refused.
allowed konrad bash '{"command":"true","description":"control"}'
for c in "sudo true" "podman ps" "docker ps" "kubectl version"; do
  denied konrad bash "{\"command\":\"$c\",\"description\":\"probe\"}"
done

# The subagent's deltas hold on top of the baseline.
allowed manual-transformer bash '{"command":"true","description":"control"}'
denied  manual-transformer bash '{"command":"rm -rf /tmp/ctl","description":"probe"}'
denied  manual-transformer webfetch '{"url":"https://example.com","format":"text"}'

# Rules that --tool can't exercise, read off the resolved rule list (the last
# rule for a permission/pattern is the one opencode applies).
last() { opencode debug agent "$1" | sed -n '/^{/,$p' \
           | jq -r --arg p "$2" --arg pat "$3" \
               '[.permission[] | select(.permission == $p and .pattern == $pat)] | last | .action // "none"'; }
[ "$(last konrad bash 'rm -rf *')"   = ask ]   || no "konrad: rm -rf is not ask"
[ "$(last konrad question '*')"      = allow ] || no "konrad: question tool not allowed"
[ "$(last konrad todowrite '*')"     = allow ] || no "konrad: todowrite not allowed"
[ "$(last manual-transformer question '*')" = deny ] || no "manual-transformer: question not denied"
CONTAINER
pass "default agent, permission denies (called, with controls), asks and subagent deltas all hold"


# --- All clear ---
printf '\n\033[32mall checks passed for %s\033[0m\n' "$IMAGE"
