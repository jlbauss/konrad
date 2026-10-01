#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Host-side probe for rootless nested Podman under the `konrad code` seal
# (ROADMAP: "Rootless nested Podman in konrad code"), with a baseline. Run it on
# the HOST, once per engine:
#
#   ./scripts/probe-nested.sh podman             # the podman connection in use
#   ./scripts/probe-nested.sh container          # Apple's container (macOS 26+)
#   ./scripts/probe-nested.sh podman --build     # + cold build, warm rebuild, nested selftest
#
# 1. Builds a throwaway probe image: the published konrad image plus podman,
#    and this checkout's seal (konrad-code-entrypoint.sh stage 1, verbatim)
#    wired to exec a command instead of the interactive stage 2.
# 2. Baseline: serves HTTP on this machine's LAN address and proves an UNSEALED
#    container reaches it, the gateway and the resolver's port 80 — so a refusal
#    later means the seal refused it.
# 3. Delta: the same read-only observations under today's `konrad code` flags
#    and under the nested flags, side by side — what nesting-by-default gives up.
# 4. Sealed + nested (run A): the baseline targets from the sealed shell (L1), a
#    nested container on pasta (L2), on --network host (L3) and on a nested
#    bridge network (L4), then seal-removal attempts. With --build: a COLD build
#    of konrad's image (the store is wiped first) and its smoke test.
# 5. With --build, run B: a FRESH container on the same store — the images from
#    run A must still be there, the rebuild must hit the cache, and a nested
#    selftest.sh drives bin/konrad's own firewall path (proxy sidecar, internal
#    network, keep-id) one level down.
#
# Store layout under test (the intended real one): /var/lib/konrad-containers,
# outside ~/.local (do_code's tools volume), named in storage.conf, on an engine
# volume on both engines (apple/container's arrives root-owned; the root prelude
# hands it to node). Not a host directory, unlike konrad's other apple stores:
# probed 2026-09-30, VirtioFS refuses both the chown and the overlay's pivot dir.
#
# Knobs: PROBE_BASE, PROBE_PIDS (1024), PROBE_MEMORY (6G), PROBE_CPUS (4),
# PROBE_KEEP_STORE=1 (don't wipe the store first; a store an unconfined run
# filled breaks a confined one, as konrad-code-entrypoint.sh explains),
# PROBE_LABEL (Podman's nested SELinux option, default do_code's
# type:container_engine_t; `disable` is the unconfined run it replaced).
# Nothing here changes konrad; it only needs the engine and python3 on the host.
set -euo pipefail

engine="${1:?usage: $0 podman|container [--build]}"
build=0; [[ "${2:-}" == --build ]] && build=1
base="${PROBE_BASE:-ghcr.io/jlbauss/konrad:latest}"
img=konrad-nested-probe:local
store=konrad-nested-probe-store
store_path=/var/lib/konrad-containers
port=8765
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

lan4="$( (ipconfig getifaddr en0 || ipconfig getifaddr en1 || hostname -I | awk '{print $1}') 2>/dev/null || true)"
[[ -n "$lan4" ]] || { echo "could not find this machine's LAN IPv4" >&2; exit 1; }

# ── 1. probe image ────────────────────────────────────────────────────────────
ctx="$(mktemp -d)"
python3 -m http.server "$port" --bind :: >/dev/null 2>&1 &
srv=$!
disown "$srv"  # no "Terminated" job notice when the trap kills it
trap 'kill "$srv" 2>/dev/null || true; rm -rf "$ctx"' EXIT

# Stage 1 of the real entrypoint, up to its drop, exec'ing "$@" instead of $0
# (the $-expressions are sed patterns, not shell).
# shellcheck disable=SC2016
sed -n '1,/^  exec_as_node "\$0" "\$@"$/p' "$repo_root/image/konrad-code-entrypoint.sh" \
  | sed 's|exec_as_node "\$0" "\$@"|exec_as_node "$@"|' > "$ctx/seal-only"
printf 'fi\n' >> "$ctx/seal-only"
# The drop's bounding set takes PROBE_KEEP on top of -all: empty is today's
# drop, ",+setuid,+setgid" the nested one (the file-capability mappers need
# exactly those two; NET_ADMIN stays unreachable either way).
# shellcheck disable=SC2016
sed 's|--bounding-set=-all|--bounding-set=-all${PROBE_KEEP:-}|' \
  "$repo_root/image/konrad-privdrop.sh" > "$ctx/konrad-privdrop.sh"
# shellcheck disable=SC2016  # a literal ${ in the pattern
grep -q -- '-all${PROBE_KEEP' "$ctx/konrad-privdrop.sh" \
  || { echo "konrad-privdrop.sh changed shape — update this probe" >&2; exit 1; }
cat > "$ctx/Containerfile" <<EOF
FROM $base
USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\
      podman crun passt uidmap fuse-overlayfs containers-storage netavark aardvark-dns catatonit iptables nftables \\
 && rm -rf /var/lib/apt/lists/*
# No setuid binaries at all; the uid mappers get file capabilities instead (a
# setuid-root newuidmap opens uid_map as a non-owner and the kernel refuses it).
# Subordinate ids inside 0..65535, so they also exist under a rootless outer
# engine, whose container only maps that range. Storage outside ~/.local.
RUN find / -xdev \\( -perm -4000 -o -perm -2000 \\) -type f -exec chmod ug-s {} + \\
 && setcap cap_setuid=ep /usr/bin/newuidmap && setcap cap_setgid=ep /usr/bin/newgidmap \\
 && printf 'node:1:999\nnode:1001:64535\n' > /etc/subuid && cp /etc/subuid /etc/subgid \\
 && install -d -o node -g node $store_path \\
 && printf '[containers]\ndefault_sysctls = []\nutsns = "host"\n' > /etc/containers/containers.conf \\
 && printf '[storage]\ndriver = "overlay"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\nrootless_storage_path = "$store_path"\n' > /etc/containers/storage.conf
COPY --chmod=755 seal-only /usr/local/bin/seal-only
COPY konrad-privdrop.sh /usr/local/lib/konrad-privdrop.sh
USER node
EOF
echo "== step 1: probe image $img (from $base, $engine)"
"$engine" build -t "$img" "$ctx" >"$ctx/build.log" 2>&1 \
  || { tail -20 "$ctx/build.log"; echo "probe image build failed" >&2; exit 1; }

# ── probe bodies ──────────────────────────────────────────────────────────────
# One line per target: OPEN or blocked. Runs in bash+curl (konrad image) and in
# busybox (alpine), so both tool paths are here. Args: lan4 port gateway resolver.
cat > "$ctx/probe" <<'EOF'
lan="$1"; port="$2"; gw="$3"; ns="$4"
if command -v curl >/dev/null; then get() { curl -sS -o /dev/null -m 4 "$1" 2>/dev/null; }
else get() { wget -S -T 4 -O /dev/null "$1" 2>&1 | grep -q "HTTP/"; }; fi
if [ -n "${BASH_VERSION:-}" ]; then tcp() { timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }
else tcp() { timeout 4 nc -w 3 "$1" "$2" </dev/null >/dev/null 2>&1; }; fi
r() { printf '%-12s %s\n' "$1" "$2"; }
get https://gitlab.com/            && r public OPEN      || r public blocked
get "http://$lan:$port/"           && r host-lan OPEN    || r host-lan blocked
get "http://$gw/"                  && r gateway OPEN     || r gateway blocked
get "http://$gw:$port/"            && r gw-port OPEN     || r gw-port blocked
tcp "$gw" 22                       && r gw-ssh OPEN      || r gw-ssh blocked
get "http://$ns/"                  && r resolver-80 OPEN || r resolver-80 blocked
tcp "$ns" 53                       && r resolver-53 OPEN || r resolver-53 blocked
EOF

net=(); [[ "$engine" == podman ]] && net=(--network bridge)
# The resolver and gateway as a container on this network sees them.
# shellcheck disable=SC2016  # expands inside the container
read -r gw ns < <("$engine" run --rm ${net[@]+"${net[@]}"} --entrypoint bash "$img" -c \
  'echo "$(ip -4 route show default | awk "{print \$3; exit}") $(awk "\$1==\"nameserver\"{print \$2; exit}" /etc/resolv.conf)"')
echo "   host-lan=$lan4:$port gateway=$gw resolver=$ns"

echo
echo "== step 2: UNSEALED baseline"
"$engine" run --rm -i ${net[@]+"${net[@]}"} --entrypoint bash "$img" -s "$lan4" "$port" "$gw" "$ns" \
  < "$ctx/probe" | tee "$ctx/L0"
echo "   setuid/setgid files in $base today: $("$engine" run --rm --entrypoint bash "$base" -c \
  'find / -xdev -type f -perm /6000 2>/dev/null | wc -l')"

# ── run flags ─────────────────────────────────────────────────────────────────
# flags default|nested → sets the global array `f`. `default` is do_code's
# flags today; `nested` drops no-new-privileges (the file capabilities need it
# off) and adds what nesting needs: SYS_CHROOT (Podman's seccomp allows chroot
# only with it), /dev/net/tun for pasta, a real /proc and an SELinux type that
# allows the nested /proc mount, and the store (native overlay can't stack on
# overlay).
store_src="$store"
store_reset() {
  if [[ "$engine" == podman ]]; then
    "$engine" volume rm -f "$store" >/dev/null 2>&1 || true
  else
    "$engine" volume delete "$store" >/dev/null 2>&1 || "$engine" volume rm "$store" >/dev/null 2>&1 || true
  fi
}
store_ensure() {
  if [[ "$engine" == podman ]]; then
    "$engine" volume exists "$store" 2>/dev/null || "$engine" volume create "$store" >/dev/null
  else
    "$engine" volume inspect "$store" >/dev/null 2>&1 || "$engine" volume create "$store" >/dev/null || true
  fi
}
flags() {
  f=(--user 0 --memory "${PROBE_MEMORY:-6G}" --cpus "${PROBE_CPUS:-4}"
     -e "KONRAD_CODE_HOST_NETS=$lan4/32")
  if [[ "$engine" == podman ]]; then
    f+=(--network bridge
        --sysctl net.ipv4.conf.all.rp_filter=0 --sysctl net.ipv4.conf.default.rp_filter=0
        --sysctl net.ipv4.conf.eth0.rp_filter=0
        --cap-drop=ALL --cap-add=NET_ADMIN --cap-add=SETUID --cap-add=SETGID --cap-add=SETPCAP
        --pids-limit "${PROBE_PIDS:-1024}")
    if [[ "$1" == nested ]]; then
      f+=(--cap-add=SYS_CHROOT --device /dev/net/tun
          --security-opt unmask=ALL --security-opt "label=${PROBE_LABEL:-type:container_engine_t}"
          -e "PROBE_KEEP=,+setuid,+setgid" -v "$store_src:$store_path")
    else
      f+=(--security-opt=no-new-privileges)
    fi
  else
    # Its own VM per container: no seccomp, SELinux or cap-drop. No --device or
    # unmask flag either, so the root prelude does their job (FIX=1): it needs
    # SYS_ADMIN to unmount the masks, which the drop to node clears again.
    f+=(--cap-add NET_ADMIN)
    [[ "$1" == nested ]] && f+=(--cap-add SYS_ADMIN -e FIX=1
                                -e "PROBE_KEEP=,+setuid,+setgid" -v "$store_src:$store_path")
  fi
  return 0
}

# Root, before the seal: report what nesting depends on and, with FIX=1, do the
# in-container equivalents of --device /dev/net/tun and unmask=/proc/* (the
# masks make the kernel refuse a fresh proc/sysfs mount in a nested namespace),
# and hand the store to node (an apple/container volume arrives root-owned).
pre="$(cat <<'EOF'
over() { awk '$2 ~ "^/proc/" || $2 ~ "^/sys/firmware" {print $2 "(" $3 ")"}' /proc/mounts | tr '\n' ' '; }
if [ "${QUIET:-0}" != 1 ]; then
  echo "-- root: $(grep CapEff /proc/self/status | tr -s '\t' ' ')  tun: $(stat -c '%a %U:%G' /dev/net/tun 2>&1)"
  echo "-- masks: $(over)"
fi
if [ "${FIX:-0}" = 1 ]; then
  chmod 666 /dev/net/tun || echo "-- fix: chmod tun FAILED"
  for m in $(awk '$2 ~ "^/proc/" || $2 ~ "^/sys/firmware" {print $2}' /proc/mounts | sort -r); do
    umount "$m" 2>/dev/null || echo "-- fix: umount $m FAILED"
  done
  if [ -d /var/lib/konrad-containers ] && [ "$(stat -c %U /var/lib/konrad-containers)" != node ]; then
    chown node:node /var/lib/konrad-containers || echo "-- fix: chown store FAILED"
  fi
fi
EOF
)"

# launch <default|nested> <inner script> [env…]: pre as root, then the seal,
# then (as node) the probe file arrives on stdin and the inner script ($0,
# expanded in the container) runs.
launch() {
  local mode="$1" body="$2"; shift 2
  flags "$mode"
  local -a extra=()
  for kv in "$@"; do extra+=(-e "$kv"); done
  # shellcheck disable=SC2016
  "$engine" run --rm -i "${f[@]}" ${extra[@]+"${extra[@]}"} \
    -e LAN="$lan4" -e PORT="$port" -e GW="$gw" -e NS="$ns" -e BUILD="$build" \
    --entrypoint bash "$img" \
    -c "$pre"$'\n''exec /usr/local/bin/seal-only bash -c '\''cat > /tmp/probe; exec bash -c "$0"'\'' "$0"' "$body" \
    < "$ctx/probe"
}

# ── 3. delta ──────────────────────────────────────────────────────────────────
# Read-only observations as node, after the seal. One `key value` per line.
observe="$(cat <<'EOF'
o() { printf '%s %s\n' "$1" "$2"; }
st() { awk -v k="$1:" '$1 == k {print $2}' /proc/self/status; }
o no-new-privs "$(st NoNewPrivs)"
o cap-bounding "$(st CapBnd)"
o cap-effective "$(st CapEff)"
o seccomp-mode "$(st Seccomp)"
o selinux-label "$(tr -d '\0' < /proc/self/attr/current 2>/dev/null || echo none)"
o proc-masks "$(awk '$2 ~ "^/proc/" || $2 ~ "^/sys/firmware" {n++} END {print n+0}' /proc/mounts)"
for p in /proc/kcore /proc/keys /proc/timer_list /proc/sched_debug /proc/acpi /sys/firmware; do
  # A masked file is /dev/null bound over it (reads succeed, empty); a masked
  # dir is an empty tmpfs. So: content / empty / denied, and entries for dirs.
  if [ -d "$p" ]; then v=$(n=$(ls -A "$p" 2>/dev/null | wc -l) && echo "$n-entries" || echo denied)
  elif head -c1 "$p" >/dev/null 2>&1; then
    [ "$(head -c1 "$p" 2>/dev/null | wc -c)" -gt 0 ] && v=content || v=empty
  else v=denied; fi
  o "node-$p" "$v"
done
o tun-device "$( (exec 3<>/dev/net/tun) 2>/dev/null && echo openable || echo no)"
o userns "$(unshare -U true 2>/dev/null && echo yes || echo no)"
o userns-mapped "$(unshare -Ur true 2>/dev/null && echo yes || echo no)"
# What seccomp and the /proc masks allow inside a user namespace node creates.
o userns-chroot "$(unshare -Ur chroot / true 2>/dev/null && echo allowed || echo refused)"
o userns-mount-proc "$(unshare -Urpm --fork sh -c 'mount -t proc proc /proc' 2>/dev/null && echo allowed || echo refused)"
o filecap-files "$(getcap -r / 2>/dev/null | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')"
o nested-run "$(podman run --rm docker.io/library/alpine true >/dev/null 2>&1 && echo works || echo no)"
EOF
)"
echo
echo "== step 3: DELTA — today's konrad code flags vs nested ($engine)"
launch default "$observe" QUIET=1 > "$ctx/d-default" 2>&1 || true
launch nested "$observe" QUIET=1 > "$ctx/d-nested" 2>&1 || true
printf '   %-22s %-24s %-24s\n' "" default nested
while read -r k v; do
  n="$(awk -v k="$k" '$1 == k {$1 = ""; sub(/^ /, ""); print}' "$ctx/d-nested")"
  mark=" "; [[ "$v" != "$n" ]] && mark="*"
  printf ' %s %-22s %-24s %-24s\n' "$mark" "$k" "${v:--}" "${n:--}"
done < <(grep -E '^[a-z][a-z/_-]+ ' "$ctx/d-default")
grep -hvE '^[a-z][a-z/_-]+ |^\[[0-9]/[0-9]\]|egress · open' "$ctx/d-default" "$ctx/d-nested" \
  | sed 's/^/   (noise) /' | head -10 || true
echo "   (* = changed by nesting)"

# ── 4. run A ──────────────────────────────────────────────────────────────────
inner="$(cat <<'EOF'
q() { grep -v -e 'single mapping' -e 'Additional gid' -e 'level=warning'; }
args="$LAN $PORT $GW $NS"
echo "-- outer: $(id -un) $(grep -E 'CapEff|CapBnd' /proc/self/status | tr -s '\t\n' '  ') $(grep NoNewPrivs /proc/self/status | tr -s '\t' ' ')"
echo "-- store: $(podman info --format '{{.Store.GraphDriverName}} {{.Store.GraphRoot}}' 2>&1 | q | tail -1)  images before: $(podman images -q 2>/dev/null | wc -l)"
echo "STORE images-at-start=$(podman images -q 2>/dev/null | wc -l)"
podman pull -q docker.io/library/alpine 2>&1 | q >/dev/null
if [ "$PHASE" = A ]; then
  echo "-- nested uid_map: $(podman unshare cat /proc/self/uid_map 2>&1 | q | tr -s ' \n' ' ')"
  podman network create probe-br >/dev/null 2>&1 || true
  echo "== L1"; bash /tmp/probe $args | sed 's/^/L1 /'
  echo "== L2"; podman run --rm -v /tmp/probe:/p:ro docker.io/library/alpine sh /p $args 2>&1 | q | sed 's/^/L2 /'
  echo "== L3"; podman run --rm --network host -v /tmp/probe:/p:ro docker.io/library/alpine sh /p $args 2>&1 | q | sed 's/^/L3 /'
  echo "== L4"; podman run --rm --network probe-br -v /tmp/probe:/p:ro docker.io/library/alpine sh /p $args 2>&1 | q | sed 's/^/L4 /'
  e() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ESC $n SUCCEEDED"; else echo "ESC $n failed"; fi; }
  e node-rule-del            ip rule del pref 200
  e userns-rule-del          podman unshare ip rule del pref 200
  e userns-route-flush       podman unshare ip route flush table 100
  e nested-priv-rule-del     podman run --rm --privileged --network host docker.io/library/alpine ip rule del pref 200
  e nested-priv-route-flush  podman run --rm --privileged --network host docker.io/library/alpine ip route flush table 100
  e newuidmap-real-root      bash -c 'unshare -U sleep 10 & sleep 1; newuidmap $(pgrep -nx sleep) 0 0 1'
  e setpriv-to-root          setpriv --reuid 0 true
  echo "SEAL rules=$(ip rule | grep -c 'lookup 100') routes=$(ip route show table 100 | wc -l)"
fi
if [ "$BUILD" = 1 ]; then
  cd /tmp && git clone -q https://gitlab.git.nrw/jbauss2/konrad.git && cd konrad
  s=$(date +%s); ./scripts/build-image.sh 2>&1 | q | tail -3; echo "BUILD phase=$PHASE rc=${PIPESTATUS[0]} secs=$(( $(date +%s) - s ))"
  podman image exists konrad:local \
    && { ./scripts/smoke-test.sh konrad:local 2>&1 | tail -3; echo "SMOKE phase=$PHASE rc=${PIPESTATUS[0]}"; }
  if [ "$PHASE" = B ] && podman image exists konrad:local; then
    ./scripts/selftest.sh --image konrad:local > /tmp/selftest.log 2>&1; rc=$?
    grep -E 'PASS|FAIL|SKIP' /tmp/selftest.log | tail -4
    [ "$rc" = 0 ] || tail -25 /tmp/selftest.log
    echo "SELFTEST rc=$rc"
  fi
  echo "STORE size=$(du -sh /var/lib/konrad-containers 2>/dev/null | cut -f1)"
fi
EOF
)"
if [[ "${PROBE_KEEP_STORE:-0}" != 1 ]]; then store_reset; fi
store_ensure
echo
echo "== step 4: SEALED + nested, run A ($engine, store: ${store_src})"
launch nested "$inner" PHASE=A 2>&1 | tee "$ctx/sealed" || true
if (( build )); then
  echo
  echo "== step 5: SEALED + nested, run B — fresh container, same store"
  launch nested "$inner" PHASE=B 2>&1 | tee "$ctx/runB" || true
fi

# ── verdict ───────────────────────────────────────────────────────────────────
echo
echo "== verdict"
fail=0
while read -r target base_res; do
  for lvl in L1 L2 L3 L4; do
    got="$(awk -v l="$lvl" -v t="$target" '$1 == l && $2 == t {print $3}' "$ctx/sealed")"
    case "$target" in
      public|resolver-53) want=OPEN ;;
      *) [[ "$base_res" == OPEN ]] && want=blocked || want="(baseline blocked — proves nothing)" ;;
    esac
    if [[ -z "$got" ]]; then res="FAIL (no result — nested run broke?)"; fail=1
    elif [[ "$want" == "("* ]]; then res="n/a $want"
    elif [[ "$got" == "$want" ]]; then res=PASS
    else res="FAIL (got $got, want $want)"; fail=1; fi
    printf '  %-3s %-12s %s\n' "$lvl" "$target" "$res"
  done
done < "$ctx/L0"
if grep -q '^ESC .* SUCCEEDED' "$ctx/sealed"; then grep '^ESC .* SUCCEEDED' "$ctx/sealed"; fail=1; fi
grep -q '^ESC ' "$ctx/sealed" || { echo "  no escape attempts ran"; fail=1; }
if (( build )); then
  # Persistence: run B must start with run A's images and rebuild from cache.
  a="$(sed -n 's/^BUILD phase=A rc=0 secs=//p' "$ctx/sealed")"
  b="$(sed -n 's/^BUILD phase=B rc=0 secs=//p' "$ctx/runB")"
  imgs="$(sed -n 's/^STORE images-at-start=//p' "$ctx/runB")"
  printf '  %-16s %s\n' "cold build" "$([[ -n "$a" ]] && echo "${a}s" || echo FAIL)"
  printf '  %-16s %s\n' "warm rebuild" "$([[ -n "$b" ]] && echo "${b}s" || echo FAIL)"
  printf '  %-16s %s\n' "store persisted" "$([[ "${imgs:-0}" -gt 0 ]] && echo "PASS ($imgs images at run B start)" || echo FAIL)"
  printf '  %-16s %s\n' "store size" "$(sed -n 's/^STORE size=//p' "$ctx/runB")"
  for p in A B; do
    if grep -q "^SMOKE phase=$p rc=0" "$ctx/sealed" "$ctx/runB"; then r=PASS; else r=FAIL; fail=1; fi
    printf '  %-16s %s\n' "smoke ($p)" "$r"
  done
  s="$(sed -n 's/^SELFTEST rc=//p' "$ctx/runB")"
  printf '  %-16s %s\n' "nested selftest" "$([[ "$s" == 0 ]] && echo PASS || echo "FAIL (rc=${s:-none})")"
  [[ -n "$a" && -n "$b" && "$s" == 0 && "${imgs:-0}" -gt 0 ]] || fail=1
fi
(( fail == 0 )) && echo "  ALL PASS" || echo "  FAILURES above"
exit "$fail"
