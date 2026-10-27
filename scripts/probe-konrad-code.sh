#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Host-side seal probe for `konrad code`, with a baseline. Run it on the HOST
# (not inside a container), once per engine:
#
#   ./scripts/probe-konrad-code.sh podman      # the podman connection in use
#   ./scripts/probe-konrad-code.sh container   # Apple's container (macOS 26+)
#
# Step 1, baseline: serve HTTP on this machine's LAN address and prove an
# UNSEALED container reaches it (directly, or at the engine's mapped address
# host.containers.internal — under pasta the host's own LAN IP is the
# container's own), the engine gateway and IPv6 — so a refusal in
# step 2 means the seal refused it, not that the target was never reachable.
# Step 2, the change: the same targets from inside `konrad-dev code --shell` on
# a public repo, under a throwaway --profile. The session asks for its token on
# the terminal, so a python3 pty driver answers it as a user would: Enter, the
# probe once the shell is up, `exit`; bin/konrad has no CI mode to keep. Then
# the verdict: whatever step 1 reached
# now fails, the internet still works, the seal can't be removed, node has no
# capabilities. Exits non-zero on any FAIL. PROBE_KEEP=1 keeps the volumes.
set -euo pipefail

engine="${1:?usage: $0 podman|container}"
# No localhost/ prefix: apple/container would read it as a registry to pull from.
img="${KONRAD_IMAGE:-konrad:local}"
port=8765
repo="${PROBE_REPO:-https://gitlab.com/gitlab-examples/nodejs}"
profile="sealprobe$$"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

lan4="$( (ipconfig getifaddr en0 || ipconfig getifaddr en1 || hostname -I | awk '{print $1}') 2>/dev/null || true)"
lan6="$( (ifconfig 2>/dev/null | awk '$1 == "inet6" && $2 !~ /^(fe80|::1)/ && $0 !~ /temporary|deprecated/ {print $2; exit}') || true)"
lan6="${lan6%%%*}"
[[ -n "$lan4" ]] || { echo "could not find this machine's LAN IPv4" >&2; exit 1; }
echo "host LAN: v4=$lan4 v6=${lan6:-<none>}"

ctx="$(mktemp -d)"
# The session's volumes, named as do_code names them under --profile.
# shellcheck disable=SC2329  # called from the EXIT trap
cleanup_volumes() {
  [[ "${PROBE_KEEP:-0}" == 1 ]] && return 0
  if [[ "$engine" == podman ]]; then
    podman volume ls --format '{{.Name}}' | grep -E "^konrad-code-.*-$profile\$" \
      | xargs -r podman volume rm >/dev/null || true
  else
    container volume delete "konrad-code-${repo#https://}-containers-$profile" >/dev/null 2>&1 || true
    rm -rf "$HOME/.local/state/konrad/store/konrad-code-"*"-$profile"
  fi
}
python3 -m http.server "$port" --bind :: >/dev/null 2>&1 &
srv=$!
disown "$srv"  # no "Terminated" job notice when the trap kills it
trap 'kill "$srv" 2>/dev/null || true; cleanup_volumes; rm -rf "$ctx"' EXIT
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
t host http://host.containers.internal:'"$port"'/
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
"$engine" run --rm ${net[@]+"${net[@]}"} --entrypoint bash "$img" -c "$probe" | tee "$ctx/base"

echo
echo "== step 2: SEALED — konrad-dev --profile $profile code --shell $repo =="
# konrad-dev by name: bin/konrad picks konrad:local and skips the background
# refresh by argv[0]. The driver waits for each prompt before it answers, since
# input typed ahead is lost: apple/container's `run -it` drops what was queued
# before it set up the terminal. Enter at the token prompt (a public repo
# clones anonymously); at the shell's prompt the probe between markers and the
# two removal checks; after the end marker, exit.
ln -s "$repo_root/bin/konrad" "$ctx/konrad-dev"
sealed_cmd="echo PROBE-\"\"BEGIN; $(printf '%s' "$probe" | tr '\n' ';' | sed 's/;;*/; /g; s/^; //') ip rule del pref 200 2>&1 | sed 's/^/  rule-del /'; awk '/^CapEff/ {print \"  capeff \" \$2}' /proc/self/status; echo PROBE-\"\"END"
KONRAD_ENGINE="$engine" KONRAD_IMAGE="$img" python3 - "$ctx/pty" "$sealed_cmd" \
  "$ctx/konrad-dev" --profile "$profile" code --shell "$repo" <<'PY' || true
import fcntl, os, pty, re, select, signal, struct, sys, termios, time
log, line, argv = sys.argv[1], sys.argv[2].encode(), sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 250, 0, 0))
out, step, now = b"", 0, time.time()
deadline, last = now + 900, now
while time.time() < deadline:
    if select.select([fd], [], [], 1)[0]:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
        last = time.time()
        sys.stderr.buffer.write(chunk)  # the session, live
        sys.stderr.flush()
    # Line ends vary by engine (a second \r where the host tty isn't raw).
    text = out.replace(b"\r", b"")
    if step == 0 and b"Paste the token" in text:
        os.write(fd, b"\r")
        step = 1
    # The shell is up: its prompt after the entrypoint's "shell" line, or, if
    # neither shows, 20 quiet seconds after the token (bash reads it later).
    shell = re.search(rb"  shell\n", text)
    if step < 2 and ((shell and re.search(rb"\$ $", text[shell.end():]))
                     or (step == 1 and time.time() - last > 20)):
        os.write(fd, line + b"\r")
        step = 2
    if step == 2 and re.search(rb"\nPROBE-END\n", text):
        os.write(fd, b"exit\r")
        step = 3
else:
    os.kill(pid, signal.SIGTERM)
os.waitpid(pid, 0)
open(log, "wb").write(out)
PY
tr -d '\r' < "$ctx/pty" | sed -n '/^PROBE-BEGIN$/,/^PROBE-END$/p' | tee "$ctx/sealed"
if ! grep -q '^PROBE-END$' "$ctx/sealed"; then
  echo "-- the sealed shell never finished the probe; its last output:"
  tr -d '\r' < "$ctx/pty" | tail -20
fi

# ── verdict ───────────────────────────────────────────────────────────────────
# A target is OPEN when its result starts with an HTTP status (a failed curl
# starts with its error message instead) or the raw socket connected.
result() { awk -v k="$1 $2" '$1 " " $2 == k {print $3; exit}' "$3"; }
is_open() { [[ "$1" =~ ^[1-5][0-9][0-9]$ || "$1" == connected ]]; }
echo
echo "== verdict"
fail=0 baseline_open=0
# shellcheck disable=SC2094  # result() only reads the file the loop reads
while read -r label target _; do
  [[ -n "$target" ]] || continue
  base="$(result "$label" "$target" "$ctx/base")"
  got="$(result "$label" "$target" "$ctx/sealed")"
  if [[ "$label" == public* ]]; then
    if ! is_open "$base"; then res="n/a (baseline blocked)"
    elif is_open "$got"; then res=PASS
    else res="FAIL (the internet must stay open; got:$got)"; fail=1; fi
  elif ! is_open "$base"; then res="n/a (baseline blocked — proves nothing)"
  else
    baseline_open=1
    if [[ -z "$got" ]]; then res="FAIL (no result — the session broke?)"; fail=1
    elif is_open "$got"; then res="FAIL (reachable through the seal:$got)"; fail=1
    else res=PASS; fi
  fi
  printf '  %-8s %-40s %s\n' "$label" "$target" "$res"
done < "$ctx/base"
if (( ! baseline_open )); then
  echo "  FAIL: the unsealed baseline reached no host, gateway or raw target — the seal is unproven"
  fail=1
fi
if grep -q '^  rule-del .*Operation not permitted' "$ctx/sealed"; then echo "  seal removal: PASS (refused)"
else echo "  seal removal: FAIL ($(grep '^  rule-del' "$ctx/sealed" || echo 'no result'))"; fail=1; fi
if grep -Eq '^  capeff 0+$' "$ctx/sealed"; then echo "  node caps:    PASS (none)"
else echo "  node caps:    FAIL ($(grep '^  capeff' "$ctx/sealed" || echo 'no result'))"; fail=1; fi
(( fail == 0 )) && echo "  ALL PASS" || echo "  FAILURES above"
exit "$fail"
