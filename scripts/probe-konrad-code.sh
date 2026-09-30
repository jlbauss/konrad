#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Host-side seal probe for `konrad code`, with a baseline. Run it on the HOST
# (not in the dev container), once per engine:
#
#   ./scripts/probe-konrad-code.sh podman      # the podman connection in use
#   ./scripts/probe-konrad-code.sh container   # Apple's container (macOS 26+)
#
# Step 1 (automatic): serve HTTP on this machine's LAN address and prove an
# UNSEALED container reaches it, the engine gateway and IPv6 — so a refusal in
# step 2 means the seal refused it, not that the target was never reachable.
# Step 2 (by hand): the same targets from inside `konrad code --shell`; the
# script prints the line to paste there. Pass: whatever step 1 reached now fails.
set -euo pipefail

engine="${1:?usage: $0 podman|container}"
# No localhost/ prefix: apple/container would read it as a registry to pull from.
img="${KONRAD_IMAGE:-konrad:local}"
port=8765
repo="${PROBE_REPO:-https://gitlab.com/gitlab-examples/nodejs}"

lan4="$( (ipconfig getifaddr en0 || ipconfig getifaddr en1 || hostname -I | awk '{print $1}') 2>/dev/null || true)"
lan6="$( (ifconfig 2>/dev/null | awk '$1 == "inet6" && $2 !~ /^(fe80|::1)/ && $0 !~ /temporary|deprecated/ {print $2; exit}') || true)"
lan6="${lan6%%%*}"
[[ -n "$lan4" ]] || { echo "could not find this machine's LAN IPv4" >&2; exit 1; }
echo "host LAN: v4=$lan4 v6=${lan6:-<none>}"

python3 -m http.server "$port" --bind :: >/dev/null 2>&1 &
srv=$!
trap 'kill "$srv" 2>/dev/null || true' EXIT
sleep 1

# The shared probe, one line per target: the HTTP code, or curl's error.
# Runs inside the container, so its $vars must NOT expand here.
# shellcheck disable=SC2016
probe='
gw=$(ip -4 route show default | awk "{print \$3; exit}")
t() { printf "  %-8s %-40s " "$1" "$2"; curl -sS -o /dev/null -m 5 -w "%{http_code}" $3 "$2" 2>&1 | tr "\n" " " | cut -c1-90; }
t public https://gitlab.com/
t public6 https://ipv6.google.com/ -6
t host-LAN http://'"$lan4"':'"$port"'/
[ -n "'"$lan6"'" ] && t host-v6 "http://['"$lan6"']:'"$port"'/" -6
t gateway http://$gw/
t gw-port http://$gw:'"$port"'/
t meta http://169.254.169.254/
t rebind http://10.0.0.1.nip.io/
for d in udp/10.0.0.1/9 tcp/$gw/22; do printf "  %-8s %-40s " raw "$d"; if timeout 3 bash -c "echo x > /dev/$d" 2>/dev/null; then echo connected; else echo refused/unreachable; fi; done
'

echo
echo "== step 1: UNSEALED baseline ($engine, $img) — host-LAN, gateway ports and raw should connect =="
net=()
[[ "$engine" == podman ]] && net=(--network bridge)
"$engine" run --rm ${net[@]+"${net[@]}"} --entrypoint bash "$img" -c "$probe"

cat <<EOF

== step 2: SEALED — run this, press Enter at the token prompt, then paste the line below ==
   KONRAD_ENGINE=$engine konrad-dev code --shell $repo

   (keep this script running: it serves the host-LAN target until you press Enter here)

  must work:  public (and public6 if step 1 reached it)
  must fail:  every target that connected in step 1 (a 200, or raw "connected");
              one that already failed there proves nothing either way
  then also:  ip rule del pref 200   → Operation not permitted
              grep CapEff /proc/self/status → 0000000000000000

----- paste inside the sealed shell -----
$(printf '%s' "$probe" | tr '\n' ';' | sed 's/;;*/; /g; s/^; //')
-----------------------------------------
EOF
read -r -p "press Enter to stop the host server " _
