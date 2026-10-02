#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# konrad code entrypoint — the sealed coding-agent mode (`konrad code <git-url>`).
# bin/konrad starts the image with THIS as --entrypoint (not konrad-entrypoint:
# no opencode config, no layers, no context). The opposite trade-off to `konrad`:
# the container sees only a clone of a repo that already lives on the forge, so
# egress is open to the internet — minus the host, the LAN and link-local, which
# the root prelude below seals at the IP level before anything else runs.
#
# Mounts (all named volumes, nothing from the host filesystem):
#   /workspace        konrad-code-<repo>  the clone, its forge token, and the
#                     worktrees of parallel sessions (.sessions/<name>)
#   /home/node/.local konrad-code-tools   the agent binary (installed on first use)
#   /home/node/.config konrad-code-config the agent's login + settings
#   /var/lib/konrad-containers  konrad-code-<repo>-containers  nested podman's
#                     image store (--nested only)
#
# Two stages in one file: as root, install the seal and drop to node with every
# capability gone; as node, set up git, clone or fetch, install the agent if
# missing, and exec it. See ARCHITECTURE → konrad code.
set -euo pipefail

KONRAD_CODE_URL="${KONRAD_CODE_URL:-}"
KONRAD_DEBUG="${KONRAD_DEBUG:-0}"
WORK=/workspace
CREDS="$WORK/.git-credentials"
SESSIONS="$WORK/.sessions"   # parallel sessions' git worktrees (one per name)
SEAL_TABLE=100
NESTED_STORE=/var/lib/konrad-containers

# Output style mirrors image/entrypoint.sh (a launch reads as one sequence).
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  case "${COLORTERM:-}" in
    truecolor|24bit) _C_OK=$'\033[38;2;63;122;87m' ;;
    *)               _C_OK=$'\033[32m' ;;
  esac
  _C_WARN=$'\033[33m'; _C_ERR=$'\033[31m'; _C_DIM=$'\033[2m'; _C_OFF=$'\033[0m'
else
  _C_OK=''; _C_WARN=''; _C_ERR=''; _C_DIM=''; _C_OFF=''
fi
step()  { printf '  %s✓%s  %s\n' "$_C_OK"  "$_C_OFF" "$*" >&2; }
go()    { printf '  %s→%s  %s\n' "$_C_DIM" "$_C_OFF" "$*" >&2; }
say()   { printf '%skonrad%s %s\n' "$_C_DIM" "$_C_OFF" "$*" >&2; }
warn()  { printf '%skonrad%s %swarning:%s %s\n' "$_C_DIM" "$_C_OFF" "$_C_WARN" "$_C_OFF" "$*" >&2; }
fatal() { printf '%skonrad%s %serror:%s %s\n'   "$_C_DIM" "$_C_OFF" "$_C_ERR" "$_C_OFF" "$*" >&2; exit 1; }
dbg()   { [[ "$KONRAD_DEBUG" == "1" ]] && printf '[konrad code debug] %s\n' "$*" >&2; return 0; }

# shellcheck source=konrad-privdrop.sh
. /usr/local/lib/konrad-privdrop.sh \
  || fatal "missing /usr/local/lib/konrad-privdrop.sh (broken image)"

# ── Stage 1 (root): seal host / LAN / link-local, then drop ───────────────────
# The destinations are refused by `unreachable` routes in a dedicated table that
# a policy rule consults BEFORE main, so they win even over a connected route
# (the container's own subnet, the gateway). One exemption, port-scoped: DNS to
# the engine's resolvers in resolv.conf — they sit in private space on every
# engine (gvproxy 192.168.127.1, pasta 169.254.1.1, apple/container's gateway)
# and at least gvproxy serves an API on other ports of the same address, so a
# whole-address exemption would reopen the host. Public destinations miss the
# table and fall through to main's default route. Routes and rules are netns
# state; the dropped node user has no CAP_NET_ADMIN, so it can't remove them.
# Fail CLOSED: any failed step aborts the run before the agent starts.
seal_v4=(0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12
         192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4)
seal_v6=(::/128 ::ffff:0:0/96 64:ff9b::/96 64:ff9b:1::/48 fc00::/7 fe80::/10 ff00::/8)

seal_family() {  # $1 = -4|-6, rest = ranges
  local fam="$1" net r p err; shift
  for net in "$@"; do
    ip "$fam" route add unreachable "$net" table "$SEAL_TABLE" \
      || fatal "egress seal: could not install the route for $net"
  done
  # The container's own connected subnets too, private or not: on rootless
  # Podman (pasta) the interface copies the host's address, so this is the host's
  # real LAN even when it's publicly addressed. `replace` tolerates overlap with
  # a range already listed above.
  while read -r net _; do
    [[ "$net" == */* ]] || continue
    ip "$fam" route replace unreachable "$net" table "$SEAL_TABLE" \
      || fatal "egress seal: could not install the route for connected $net"
  done < <(ip "$fam" route show table main proto kernel 2>/dev/null)
  # The host's own networks, handed over by bin/konrad (KONRAD_CODE_HOST_NETS):
  # on a publicly addressed LAN the private list above misses both the host and
  # its neighbours. Normalized (and validated) by ipaddress; junk is skipped.
  while read -r net; do
    [[ -n "$net" ]] || continue
    ip "$fam" route replace unreachable "$net" table "$SEAL_TABLE" \
      || fatal "egress seal: could not install the route for host network $net"
  done < <(python3 - "$fam" "${KONRAD_CODE_HOST_NETS:-}" <<'PY'
import ipaddress, sys
want = 4 if sys.argv[1] == "-4" else 6
for a in sys.argv[2].split():
    try:
        n = ipaddress.ip_network(a, strict=False)
    except ValueError:
        continue
    if n.version == want:
        print(n)
PY
)
  # Deduplicated: the engine copies the host's resolvers, and a host on two links
  # to the same router (Wi-Fi + dock) lists it twice — as does rootless Podman
  # one level down. A repeated `rule add` is refused with EEXIST, so pass ip's
  # own error through instead of guessing.
  while read -r r; do
    for p in udp tcp; do
      err="$(ip "$fam" rule add to "$r" ipproto "$p" dport 53 lookup main pref 100 2>&1)" \
        || fatal "egress seal: could not exempt DNS to $r ($p): ${err:-unknown error}"
    done
  done < <(awk '$1 == "nameserver" && !seen[$2]++ {print $2}' /etc/resolv.conf \
             | if [[ "$fam" == -6 ]]; then grep ':' ; else grep -v ':'; fi || true)
  ip "$fam" rule add lookup "$SEAL_TABLE" pref 200 \
    || fatal "egress seal: could not install the policy rule"
}

if [[ "$(id -u)" == "0" ]]; then
  seal_family -4 "${seal_v4[@]}"
  # IPv6: seal whenever the stack exists at all; a v6-less kernel has no v6
  # route to leak through.
  if [[ -e /proc/net/if_inet6 ]]; then
    seal_family -6 "${seal_v6[@]}"
  fi
  # Self-check: the host's gateway and a LAN address must no longer route
  # (`ip route get` fails with "No route to host" on an unreachable route).
  for probe in 10.0.0.1 192.168.1.1 "$(ip -4 route show default | awk '{print $3; exit}')"; do
    [[ -n "$probe" ]] || continue
    if ip -4 route get "$probe" >/dev/null 2>&1; then
      fatal "egress seal: self-check failed ($probe still routable) — refusing to run"
    fi
  done
  # Reverse-path filtering must be off (bin/konrad sets it on Podman): with
  # private space unreachable it drops inbound packets and large downloads stall.
  # Not a security property, so warn rather than refuse.
  dev="$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')"
  if [[ -n "$dev" && -r "/proc/sys/net/ipv4/conf/$dev/rp_filter" ]] \
     && [[ "$(cat "/proc/sys/net/ipv4/conf/$dev/rp_filter")" != 0 \
           || "$(cat /proc/sys/net/ipv4/conf/all/rp_filter)" != 0 ]]; then
    warn "reverse-path filtering is on for $dev — large downloads may stall"
  fi
  dbg "$(ip -4 rule; ip -4 route show table "$SEAL_TABLE")"
  step "egress · open, host + LAN sealed"
  if [[ "${KONRAD_CODE_NESTED:-0}" == "1" ]]; then
    # Rootless nested Podman (--nested). On Podman, bin/konrad's flags already
    # did the work (--device, unmask, the store volume); apple/container has no
    # such flags, so root does their job here with the SYS_ADMIN it was given
    # for this prelude only (the drop below clears it): open the tun device to
    # node (pasta), unmount the masks over /proc (the kernel refuses a fresh
    # proc mount in a nested namespace while any of it is hidden), and hand
    # node the store, which an apple/container volume brings root-owned.
    if [[ -c /dev/net/tun && "$(stat -c %a /dev/net/tun)" != 666 ]]; then
      chmod 666 /dev/net/tun || warn "could not open /dev/net/tun to node — nested networking may fail"
    fi
    while read -r m; do
      umount "$m" 2>/dev/null || true
    done < <(awk '$2 ~ "^/proc/" || $2 ~ "^/sys/firmware" {print $2}' /proc/mounts | sort -r)
    awk '$2 ~ "^/proc/" {f = 1} END {exit !f}' /proc/mounts \
      && warn "/proc is still partly masked — nested containers may fail to start"
    if [[ -d "$NESTED_STORE" && "$(stat -c %U "$NESTED_STORE")" != node ]]; then
      chown node:node "$NESTED_STORE" || warn "could not hand $NESTED_STORE to node — nested containers will fail"
    fi
    step "nested containers · rootless podman"
    # Node keeps exactly setuid,setgid in its bounding set: the file-capability
    # newuidmap/newgidmap need them to map the subordinate ids. NET_ADMIN stays
    # out of reach, so the seal holds.
    exec_as_node --keep-caps setuid,setgid "$0" "$@"
  fi
  exec_as_node "$0" "$@"
fi

# ── Stage 2 (node): git, clone/fetch, agent install, launch ──────────────────
[[ -n "$KONRAD_CODE_URL" ]] || fatal "KONRAD_CODE_URL not set (start this through 'konrad code <git-url>')"
[[ -t 0 ]] || fatal "konrad code needs an interactive terminal"
ip -4 rule 2>/dev/null | grep -q "lookup $SEAL_TABLE" \
  || fatal "egress seal missing — konrad code must start as root so it can seal the host (start it through 'konrad code')"
# The drop must have left exactly the bounding set this run asked for: nothing,
# or setuid+setgid (0xc0) under --nested. Anything wider refuses to run.
want_bnd=0000000000000000
[[ "${KONRAD_CODE_NESTED:-0}" == "1" ]] && want_bnd=00000000000000c0
[[ "$(awk '$1 == "CapBnd:" {print $2}' /proc/self/status)" == "$want_bnd" ]] \
  || fatal "unexpected capability bounding set after the drop — refusing to run"

repo_host="${KONRAD_CODE_URL#https://}"; repo_host="${repo_host%%/*}"
repo_path="${KONRAD_CODE_URL#https://*/}"; repo_path="${repo_path%.git}"
repo_dir="$WORK/${repo_path##*/}"

# Git config lives in the ephemeral home (rewritten each run); the token lives
# in the repo's own volume, so it never follows the user to another repo.
git config --global credential.helper "store --file=$CREDS"
git config --global push.autoSetupRemote true
git config --global init.defaultBranch main
# No interactive credential prompt: GitLab answers a missing repo and a private
# one without a valid token alike (401), and git would then ask for a username
# — a dead end here, since the token is the only credential.
export GIT_TERMINAL_PROMPT=0
# On apple/container /workspace, ~/.config and ~/.local are host dirs shared
# into the VM over VirtioFS (the one filesystem two VMs can share, which
# parallel sessions and repos need). VirtioFS reports a file as owned by
# whichever uid last looked it up, for as long as the guest caches that answer,
# so tools that check ownership can see root (after the prelude) or a nested
# container's uid instead of node. git refuses the clone as "dubious
# ownership": the volume is this repo's alone, so trust just that path.
git config --global --add safe.directory "$repo_dir"
# Podman refuses a ~/.config it doesn't seem to own, but checks only a config
# dir it derives from $HOME: naming its default explicitly skips the check.
export XDG_CONFIG_HOME="$HOME/.config"
[[ -n "${KONRAD_GIT_NAME:-}" ]]  && git config --global user.name  "$KONRAD_GIT_NAME"
[[ -n "${KONRAD_GIT_EMAIL:-}" ]] && git config --global user.email "$KONRAD_GIT_EMAIL"

# The token is typed here, inside the container, so it never touches the host.
# ask_token stores it in git's `store` format; Enter stores an empty file
# (anonymous: a public repo clones, pushes fail) so the choice is remembered;
# deleting the file makes the next run ask again.
asked=0
ask_token() {
  local token
  asked=1
  read -r -s -p "  Paste the token (input hidden; Enter to skip for a public repo): " token </dev/tty
  printf '\n' >&2
  if [[ -n "$token" ]]; then
    ( umask 077; printf 'https://oauth2:%s@%s\n' "$token" "$repo_host" > "$CREDS" )
    step "token stored in this repo's volume"
  else
    : > "$CREDS"
    warn "no token — cloning anonymously; pushes will fail (to add one later: rm $CREDS in --shell, then run again)"
  fi
}

# Ask the forge about the stored token (GitLab's token self-lookup, which works
# for project tokens too): every token expires, and on a public repo a dead one
# would otherwise only surface when the agent's push fails mid-session. A
# rejected token is asked for again; a missing write scope or a near expiry
# warns. Best-effort: any answer but 200/401 (another forge, an old GitLab, no
# network) skips the check silently.
check_token() {
  local token body code exp days
  token="$(sed -n 's|^https://oauth2:\(.*\)@.*$|\1|p' "$CREDS" 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    (( asked )) || go "no token, pushes fail · to add one: rm $CREDS in --shell, then run again"
    return 0
  fi
  body="$(mktemp)"
  code="$(curl -sS -m 8 -o "$body" -w '%{http_code}' -H "PRIVATE-TOKEN: $token" \
            "https://$repo_host/api/v4/personal_access_tokens/self" 2>/dev/null || true)"
  case "$code" in
    401)
      warn "$repo_host rejected the stored token — it was revoked or has expired"
      printf '  Create a new one at https://%s/%s/-/settings/access_tokens\n' "$repo_host" "$repo_path" >&2
      ask_token
      ;;
    200)
      jq -e '.scopes | index("write_repository")' "$body" >/dev/null 2>&1 \
        || warn "the token lacks the write_repository scope — the agent's pushes will fail"
      exp="$(jq -r '.expires_at // empty' "$body" 2>/dev/null || true)"
      if [[ -n "$exp" ]]; then
        days=$(( ( $(date -d "$exp" +%s 2>/dev/null || date +%s) - $(date +%s) ) / 86400 ))
        if (( days <= 14 )); then
          warn "the token expires on $exp — renew it at https://$repo_host/$repo_path/-/settings/access_tokens"
        fi
      fi
      ;;
  esac
  rm -f "$body"
  return 0
}

# First run: explain the token and the branch protection, then ask.
if [[ ! -f "$CREDS" ]]; then
  cat >&2 <<EOF

  ${_C_OK}First run for $repo_host/$repo_path.${_C_OFF} The agent pushes through a project
  access token scoped to this one repository:

    https://$repo_host/$repo_path/-/settings/access_tokens
      role: Developer   scopes: read_repository, write_repository

  Recommended: protect the default branch so the agent can open merge requests
  but never land code by itself. GitLab usually does this out of the box — check
  it under Settings → Repository → Protected branches (or Branch rules):

    https://$repo_host/$repo_path/-/settings/repository#js-protected-branches-settings
      Allowed to merge:           Maintainers
      Allowed to push and merge:  Maintainers  (or No one — never Developers)
      Allowed to force push:      off

  This only holds while the token stays role Developer: a Maintainer token
  passes the protection and could push to the default branch directly.

EOF
  ask_token
fi
check_token

if [[ -d "$repo_dir/.git" ]]; then
  # Fetch only — never touch the working tree, which may hold unpushed work.
  # Clones from before bin/konrad added `.git` to the URL made GitLab print a
  # redirect warning on every git command; point them at the canonical URL.
  [[ "$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)" == "$KONRAD_CODE_URL" ]] \
    || git -C "$repo_dir" remote set-url origin "$KONRAD_CODE_URL"
  if git -C "$repo_dir" fetch --prune --quiet origin; then
    step "fetched"
  else
    warn "git fetch failed — continuing with the existing clone"
  fi
else
  if ! git clone "$KONRAD_CODE_URL" "$repo_dir"; then
    # Forget the token too: it was typed for a URL that didn't work, so the
    # next run asks again. Exit 3 tells bin/konrad the volume holds nothing.
    rm -f "$CREDS"
    printf '%skonrad%s %serror:%s could not clone %s — either the repository does not exist, or it is private and the token is missing or lacks read_repository. Check the URL and run again (you will be asked for the token again).\n' \
      "$_C_DIM" "$_C_OFF" "$_C_ERR" "$_C_OFF" "$KONRAD_CODE_URL" >&2
    exit 3
  fi
  step "cloned $repo_path"
fi
default_branch="$(git -C "$repo_dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
default_branch="${default_branch#origin/}"; default_branch="${default_branch:-main}"

# Parallel sessions (bin/konrad picks the name; see code_live_sessions there).
# `primary` works in the clone itself, as every run did before sessions; any
# other session gets a git worktree of that clone under $SESSIONS, created
# detached at the default branch on first use and resumed after. Worktrees
# share the clone's objects and its token, and git refuses to check out one
# branch in two of them — the guard parallel agents need.
session="${KONRAD_CODE_SESSION:-primary}"
work_dir="$repo_dir"
if [[ "$session" != primary ]]; then
  work_dir="$SESSIONS/$session"
  git config --global --add safe.directory "$work_dir"
  git -C "$repo_dir" worktree prune || true
  if [[ -e "$work_dir/.git" ]]; then
    step "session $session · resumed its worktree"
  else
    git -C "$repo_dir" worktree add --quiet --detach "$work_dir" "origin/$default_branch" \
      || fatal "could not create the worktree for session $session"
    step "session $session · new worktree at origin/$default_branch"
  fi
fi
cd "$work_dir"

# Where each worktree stands. A merged MR deletes its branch on the forge, which
# leaves a worktree on a branch whose upstream is gone (`git pull` then fails
# cryptically). Say so; switching or removing is the user's or the agent's call.
gone() {  # gone <dir> — its branch's upstream was deleted
  local b
  b="$(git -C "$1" branch --show-current 2>/dev/null || true)"
  [[ -n "$b" && "$(git -C "$1" for-each-ref --format='%(upstream:track)' "refs/heads/$b")" == "[gone]" ]]
}
cur="$(git branch --show-current 2>/dev/null || true)"
go "on ${cur:-a detached HEAD}"
if gone .; then
  go "its remote branch is gone (merged?) · git switch --detach origin/$default_branch, then branch anew"
fi
others=""
while read -r key path; do
  [[ "$key" == worktree && "$path" != "$PWD" ]] || continue
  name=primary; [[ "$path" == "$repo_dir" ]] || name="${path##*/}"
  b="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  gone "$path" && b+=", merged?"
  others+="${others:+ · }$name (${b:-detached})"
done < <(git worktree list --porcelain)
[[ -z "$others" ]] || go "other sessions: $others"

if [[ "${KONRAD_CODE_NESTED:-0}" == "1" ]]; then
  # A store written before --nested kept SELinux on holds layers labelled with
  # the old unconfined SELinux user. The confined agent can't copy up their
  # directories (an object's SELinux user differs from its own) or relabel them,
  # so every nested container would fail to start. It's a cache: reset it once.
  # Only when this run is confined (bin/konrad's label on SELinux hosts).
  self_ctx="$(tr -d '\0' </proc/self/attr/current 2>/dev/null || true)"
  store_ctx="$(stat -c %C "$NESTED_STORE/overlay" 2>/dev/null || true)"
  if [[ "$self_ctx" == *:container_engine_t:* && "$store_ctx" == *:*:*:* \
        && "${self_ctx%%:*}" != "${store_ctx%%:*}" ]]; then
    go "this repo's image store predates SELinux confinement · resetting it once (images get pulled or rebuilt again)"
    podman system reset --force >/dev/null 2>&1 \
      || warn "could not reset the image store — nested containers may fail; 'podman system reset' inside the session retries"
  fi
  # A session keeps its own container database (libpod's static dir) and named
  # volumes; images and layers stay shared. libpod keeps its db in the store
  # but its run state and lock table in this container's /tmp and /dev/shm, so
  # two sessions on one db reset each other's running containers ("Exited 292
  # years ago") and hand out the same locks — scripts/probe-shared-store.sh.
  # The primary session keeps libpod's default, so stores from before carry on.
  if [[ "$session" != primary ]]; then
    mkdir -p "$NESTED_STORE/sessions/$session"
    printf '[engine]\nstatic_dir = "%s/libpod"\nvolume_path = "%s/volumes"\n' \
      "$NESTED_STORE/sessions/$session" "$NESTED_STORE/sessions/$session" > /tmp/konrad-session-containers.conf
    export CONTAINERS_CONF_OVERRIDE=/tmp/konrad-session-containers.conf
  fi
  # Informational only — a failing store must warn with podman's own error,
  # never end the run (under set -e + pipefail a bare pipeline here would).
  # Every line of it but the warnings, which podman prints on a healthy run too.
  store_err="$(mktemp)"
  if store_ids="$(podman images -q 2>"$store_err")"; then
    go "nested podman · $(grep -c . <<<"$store_ids" || true) image(s) kept in this repo's store"
  else
    store_msg="$(grep -v -e '^WARN\[' -e 'level=warning' "$store_err" | paste -sd ' ' || true)"
    warn "nested podman can't read its store: ${store_msg:-$(tail -1 "$store_err")}"
  fi
  rm -f "$store_err"
fi

if [[ "${KONRAD_CODE_SHELL:-0}" == "1" ]]; then
  go "shell"
  exec bash
fi

# The agent is installed on first use, never shipped: its license lets the user
# install it, not konrad redistribute it. The official installer drops it into
# ~/.local (the konrad-code-tools volume), where it also self-updates.
if ! command -v claude >/dev/null 2>&1; then
  cat >&2 <<'EOF'

  Claude Code isn't installed yet. konrad will run Anthropic's official installer
  (curl -fsSL https://claude.ai/install.sh | bash) into a volume shared by all
  your konrad code repos. Claude Code is Anthropic's software under Anthropic's
  terms (https://www.anthropic.com/legal) — installing it means you
  accept them.

EOF
  read -r -p "  Install Claude Code now? [y/N] " ans </dev/tty
  [[ "$ans" =~ ^[Yy] ]] || fatal "not installed — nothing to run"
  # The installer downloads a ~240 MB binary with a silent `curl -fsSL` and no
  # timeout, so a stalled network reads as a hang. curl honours $CURL_HOME/.curlrc,
  # which turns a stall (< 1 KB/s for 60 s) into a clean failure without touching
  # the vendor's script; a watcher on the download file shows progress meanwhile.
  # Whole lines, not an in-place redraw, so they can't collide with the
  # installer's own output; it stops once the installer marks the verified
  # binary executable, i.e. when its `claude install` step takes over.
  CURL_HOME="$(mktemp -d)"; export CURL_HOME
  printf 'connect-timeout = 20\nspeed-limit = 1024\nspeed-time = 60\n' > "$CURL_HOME/.curlrc"
  (
    while sleep 5; do
      for f in "$HOME"/.claude/downloads/claude-*; do
        [[ -f "$f" ]] || continue
        [[ -x "$f" ]] && exit 0
        go "downloading Claude Code · $(( $(stat -c %s "$f" 2>/dev/null || echo 0) / 1048576 )) MB"
      done
    done
  ) &
  watcher=$!
  rc=0
  curl -fsSL https://claude.ai/install.sh | bash || rc=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  unset CURL_HOME
  [[ "$rc" == 0 ]] \
    || fatal "Claude Code install failed (exit $rc) — a stalled or blocked network is the usual cause; run konrad code again to retry"
  command -v claude >/dev/null 2>&1 || fatal "installer finished but 'claude' is not on PATH"
  step "Claude Code installed"
fi

# A short environment note on top of the agent's own prompts: the facts it can't
# discover by itself (the git-only way back, the sealed LAN). Nothing else.
note="You are running inside konrad code: a disposable container with open internet access but no route to the user's machine or local network. The working directory is a fresh clone of $KONRAD_CODE_URL; nothing you do here reaches the user except through the forge. '$default_branch' is protected, so work on a feature branch, commit, and open a merge request with: git push -u origin <branch> -o merge_request.create -o merge_request.target=$default_branch -o merge_request.remove_source_branch. The user reviews and merges it in the forge web UI. Install project tooling you need at runtime (uv, npm, …). Other konrad code sessions may work on this repo in parallel, each in its own git worktree of the same clone under $WORK (this one: $session, at $work_dir): stay in yours, leave their branches alone, and start new branches from origin/$default_branch rather than checking out '$default_branch' (git refuses a branch another worktree has checked out)."
if [[ "${KONRAD_CODE_NESTED:-0}" == "1" ]]; then
  note+=" Rootless podman is available: you can build and run containers here (images persist in this repo's store across sessions and are shared with parallel ones, so don't prune images you didn't build); they share this container's sealed network, so they reach the internet but not the user's machine or LAN either."
fi

go "claude · $repo_path"
exec claude --dangerously-skip-permissions --append-system-prompt "$note" "$@"
