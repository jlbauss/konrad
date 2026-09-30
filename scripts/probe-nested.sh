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
#   ./scripts/probe-nested.sh podman --build     # + build konrad's image nested
#
# 1. Builds a throwaway probe image: the published konrad image plus podman,
#    and this checkout's seal (konrad-code-entrypoint.sh stage 1, verbatim)
#    wired to exec a command instead of the interactive stage 2.
# 2. Baseline: serves HTTP on this machine's LAN address and proves an UNSEALED
#    container reaches it, the gateway and the resolver's port 80 — so a refusal
#    in step 3 means the seal refused it.
# 3. Sealed: the same targets from the sealed shell (L1), a nested container on
#    pasta (L2) and a nested --network host container (L3), then seal-removal
#    attempts from every privilege level nesting offers. Prints a verdict.
# Nothing here changes konrad; it only needs the engine and python3 on the host.
set -euo pipefail

engine="${1:?usage: $0 podman|container [--build]}"
build=0; [[ "${2:-}" == --build ]] && build=1
base="${PROBE_BASE:-ghcr.io/jlbauss/konrad:latest}"
img=konrad-nested-probe:local
store=konrad-nested-probe-store
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
# The drop keeps SETUID/SETGID in the bounding set (and only those): the
# file-capability newuidmap/newgidmap need them; NET_ADMIN stays unreachable.
sed 's|--bounding-set=-all|--bounding-set=-all,+setuid,+setgid|' \
  "$repo_root/image/konrad-privdrop.sh" > "$ctx/konrad-privdrop.sh"
grep -q -- '-all,+setuid,+setgid' "$ctx/konrad-privdrop.sh" \
  || { echo "konrad-privdrop.sh changed shape — update this probe" >&2; exit 1; }
cat > "$ctx/Containerfile" <<EOF
FROM $base
USER root
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\
      podman crun passt uidmap fuse-overlayfs containers-storage netavark aardvark-dns catatonit iptables \\
 && rm -rf /var/lib/apt/lists/*
# No setuid binaries at all; the uid mappers get file capabilities instead (a
# setuid-root newuidmap opens uid_map as a non-owner and the kernel refuses it).
# Subordinate ids inside 0..65535, so they also exist under a rootless outer
# engine, whose container only maps that range.
RUN find / -xdev \\( -perm -4000 -o -perm -2000 \\) -type f -exec chmod ug-s {} + \\
 && setcap cap_setuid=ep /usr/bin/newuidmap && setcap cap_setgid=ep /usr/bin/newgidmap \\
 && printf 'node:1:999\nnode:1001:64535\n' > /etc/subuid && cp /etc/subuid /etc/subgid \\
 && install -d -o node -g node /home/node/.local/share/containers \\
 && printf '[containers]\ndefault_sysctls = []\nutsns = "host"\n' > /etc/containers/containers.conf
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

# ── 3. sealed ─────────────────────────────────────────────────────────────────
# do_code's flags, minus no-new-privileges (file capabilities need it off), plus
# what nesting needs: SYS_CHROOT (Podman's seccomp allows chroot only with it),
# /dev/net/tun for pasta, a real /proc and no SELinux label for the nested /proc
# mount, and a volume for storage (native overlay can't stack on overlay).
if [[ "$engine" == podman ]]; then
  "$engine" volume exists "$store" 2>/dev/null || "$engine" volume create "$store" >/dev/null
  sealed=(--user 0 --network bridge
          --sysctl net.ipv4.conf.all.rp_filter=0 --sysctl net.ipv4.conf.default.rp_filter=0
          --sysctl net.ipv4.conf.eth0.rp_filter=0
          --cap-drop=ALL --cap-add=NET_ADMIN --cap-add=SETUID --cap-add=SETGID --cap-add=SETPCAP
          --cap-add=SYS_CHROOT --pids-limit "${PROBE_PIDS:-1024}"
          --device /dev/net/tun --security-opt 'unmask=/proc/*' --security-opt label=disable
          -v "$store:/home/node/.local/share/containers")
else
  # Its own VM per container: no seccomp, SELinux or cap-drop; the rootfs is
  # ext4, so native overlay needs no storage volume. No --device or unmask
  # flag either, so the root prelude below does their job (FIX=1): it needs
  # SYS_ADMIN to unmount the masks (the default set lacks it), which the drop
  # to node clears with every other capability.
  sealed=(--user 0 --cap-add NET_ADMIN --cap-add SYS_ADMIN -e FIX=1)
fi
sealed+=(--memory "${PROBE_MEMORY:-6G}" --cpus "${PROBE_CPUS:-4}" -e "KONRAD_CODE_HOST_NETS=$lan4/32")

# Root, before the seal: report what nesting depends on and, with FIX=1, try
# the in-container equivalents of --device /dev/net/tun and unmask=/proc/*
# (open the tun node; unmount the masks over /proc and /sys/firmware, which
# make the kernel refuse a fresh proc/sysfs mount in a nested namespace).
pre="$(cat <<'EOF'
over() { awk '$2 ~ "^/proc/" || $2 ~ "^/sys/firmware" {print $2 "(" $3 ")"}' /proc/mounts | tr '\n' ' '; }
echo "-- root: $(grep CapEff /proc/self/status | tr -s '\t' ' ')  tun: $(stat -c '%a %U:%G' /dev/net/tun 2>&1)"
echo "-- masks: $(over)"
if [ "${FIX:-0}" = 1 ]; then
  chmod 666 /dev/net/tun && echo "-- fix: tun now $(stat -c %a /dev/net/tun)"
  for m in $(awk '$2 ~ "^/proc/" || $2 ~ "^/sys/firmware" {print $2}' /proc/mounts | sort -r); do
    umount "$m" 2>/dev/null || echo "-- fix: umount $m FAILED"
  done
  echo "-- masks after fix: $(over)"
fi
EOF
)"

inner="$(cat <<'EOF'
q() { grep -v -e 'single mapping' -e 'Additional gid' -e 'level=warning'; }
args="$LAN $PORT $GW $NS"
echo "-- outer: $(id -un) $(grep -E 'CapEff|CapBnd' /proc/self/status | tr -s '\t\n' '  ') $(grep NoNewPrivs /proc/self/status | tr -s '\t' ' ')"
echo "-- tun: $([ -c /dev/net/tun ] && echo yes || echo NO)  userns: $(unshare -Ur true 2>/dev/null && echo yes || echo NO)  store: $(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null)"
podman pull -q docker.io/library/alpine 2>&1 | q >/dev/null
echo "-- nested uid_map: $(podman unshare cat /proc/self/uid_map 2>&1 | q | tr -s ' \n' ' ')"
echo "-- nested --pid=host --network host: $(podman run --rm --pid=host --network host docker.io/library/alpine echo ok 2>&1 | q | tail -1 | cut -c1-100)"
echo "-- nested --pid=host (pasta):        $(podman run --rm --pid=host docker.io/library/alpine echo ok 2>&1 | q | tail -1 | cut -c1-100)"
echo "== L1"; bash /tmp/probe $args | sed 's/^/L1 /'
echo "== L2"; podman run --rm -v /tmp/probe:/p:ro docker.io/library/alpine sh /p $args 2>&1 | q | sed 's/^/L2 /'
echo "== L3"; podman run --rm --network host -v /tmp/probe:/p:ro docker.io/library/alpine sh /p $args 2>&1 | q | sed 's/^/L3 /'
e() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ESC $n SUCCEEDED"; else echo "ESC $n failed"; fi; }
e node-rule-del            ip rule del pref 200
e userns-rule-del          podman unshare ip rule del pref 200
e userns-route-flush       podman unshare ip route flush table 100
e nested-priv-rule-del     podman run --rm --privileged --network host docker.io/library/alpine ip rule del pref 200
e nested-priv-route-flush  podman run --rm --privileged --network host docker.io/library/alpine ip route flush table 100
e newuidmap-real-root      bash -c 'unshare -U sleep 10 & sleep 1; newuidmap $(pgrep -nx sleep) 0 0 1'
e setpriv-to-root          setpriv --reuid 0 true
echo "SEAL rules=$(ip rule | grep -c 'lookup 100') routes=$(ip route show table 100 | wc -l)"
if [ "$BUILD" = 1 ]; then
  cd /tmp && git clone -q https://gitlab.git.nrw/jbauss2/konrad.git && cd konrad
  s=$(date +%s); ./scripts/build-image.sh 2>&1 | q | tail -3; echo "BUILD rc=${PIPESTATUS[0]} secs=$(( $(date +%s) - s ))"
  podman image exists konrad:local \
    && { ./scripts/smoke-test.sh konrad:local 2>&1 | tail -3; echo "SMOKE rc=${PIPESTATUS[0]}"; }
fi
EOF
)"
echo
echo "== step 3: SEALED + nested ($engine)"
# pre runs as root, then the seal, then (as node) the probe file arrives on
# stdin and the inner script ($0, expanded in the container) runs.
# shellcheck disable=SC2016
"$engine" run --rm -i "${sealed[@]}" -e LAN="$lan4" -e PORT="$port" -e GW="$gw" -e NS="$ns" -e BUILD="$build" \
  --entrypoint bash "$img" \
  -c "$pre"$'\n''exec /usr/local/bin/seal-only bash -c '\''cat > /tmp/probe; exec bash -c "$0"'\'' "$0"' "$inner" \
  < "$ctx/probe" 2>&1 | tee "$ctx/sealed"

# ── verdict ───────────────────────────────────────────────────────────────────
echo
echo "== verdict"
fail=0
while read -r target base_res; do
  for lvl in L1 L2 L3; do
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
(( fail == 0 )) && echo "  ALL PASS" || echo "  FAILURES above"
exit "$fail"
