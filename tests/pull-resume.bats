#!/usr/bin/env bats
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# bin/konrad's resumable fallback for apple/container pulls
# (container_pull_resumable), against a stub `container` whose pull fails and a
# stub `curl` that serves a fixture registry from files, so no network or engine
# is needed. The curl stub cuts each blob's first download halfway, as the CDN
# does on a slow link, so a pass means the fallback resumed it.

load helpers

# The fixture registry under $STUB_DIR/reg/<repo>/{manifests,blobs}/: a two-
# platform index, the host platform's manifest, a config and two layers. The
# store already holds layer one.
stub() {
  export STUB_DIR="$BATS_TEST_TMPDIR"
  local reg="$STUB_DIR/reg/owner/img" arch cfg l1 l2 man
  mkdir -p "$STUB_DIR/bin" "$reg/manifests" "$reg/blobs" "$STUB_DIR/store/content/blobs/sha256"
  k '_pull_arch'; arch="$output"
  blob() { local f="$STUB_DIR/tmp"; printf '%s' "$1" >"$f"; local d; d="sha256:$(sha256sum "$f" | cut -d' ' -f1)"; mv "$f" "$reg/blobs/$d"; printf '%s' "$d"; }
  cfg="$(blob '{"architecture":"'"$arch"'","os":"linux"}')"
  l1="$(blob "$(head -c 4000 /dev/zero | tr '\0' a)")"
  l2="$(blob "$(head -c 6000 /dev/zero | tr '\0' b)")"
  man="$(blob '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"'"$cfg"'","size":'"$(wc -c <"$reg/blobs/$cfg")"'},"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","digest":"'"$l1"'","size":4000},{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","digest":"'"$l2"'","size":6000}]}')"
  cp "$reg/blobs/$man" "$reg/manifests/$man"
  printf '%s' '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:0000","size":1,"platform":{"architecture":"other","os":"linux"}},{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"'"$man"'","size":'"$(wc -c <"$reg/blobs/$man")"',"platform":{"architecture":"'"$arch"'","os":"linux"}}]}' >"$reg/manifests/1.0"
  : >"$STUB_DIR/store/content/blobs/sha256/${l1#sha256:}"
  printf '%s\n' "$man" "$cfg" "$l1" "$l2" >"$STUB_DIR/digests"

  cat >"$STUB_DIR/bin/container" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "system status") printf 'FIELD VALUE\nstatus running\npaths.appRoot %s/store/\n' "$STUB_DIR" ;;
  "image pull"*) [[ -e "$STUB_DIR/pull-ok" ]] && exit 0; echo "Error: StreamClosed" >&2; exit 1 ;;
  "image load") cat >"$STUB_DIR/loaded.tar" ;;
  *) echo "$*" >>"$STUB_DIR/calls" ;;
esac
EOF
  cat >"$STUB_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" resume=0 url=""
while (( $# )); do
  case "$1" in
    -o) out="$2"; shift ;;
    -C) resume=1; shift ;;
    -D|-H|--data-urlencode) shift ;;
    -*) ;;
    *) url="$1" ;;
  esac
  shift
done
[[ "$url" == */v2/ ]] && { printf 'HTTP/2 200\r\n\r\n'; exit 0; }   # no auth challenge
src="$STUB_DIR/reg/${url#*/v2/}"
[[ -f "$src" ]] || exit 22
from=0
(( resume )) && [[ -f "$out" ]] && from="$(wc -c <"$out")"
(( resume )) || : >"$out"
if [[ "$url" == */blobs/* && ! -e "$src.cut" ]]; then          # first try: half, then a reset
  : >"$src.cut"
  tail -c +"$((from + 1))" "$src" | head -c "$(( ($(wc -c <"$src") - from) / 2 ))" >>"$out"
  exit 92
fi
tail -c +"$((from + 1))" "$src" >>"$out"
EOF
  chmod +x "$STUB_DIR/bin/container" "$STUB_DIR/bin/curl"
  export PATH="$STUB_DIR/bin:$PATH" KONRAD_ENGINE=container KONRAD_ENGINE_TIMEOUT=5
}

@test "eng_pull on container: a broken pull resumes, fetching only what the store lacks" {
  stub
  k 'eng_pull example.test/owner/img:1.0'
  [ "$status" -eq 0 ]
  [[ "$output" == *"fetching 2 layers"* ]]
  local man cfg l1 l2
  { read -r man; read -r cfg; read -r l1; read -r l2; } <"$STUB_DIR/digests"
  mkdir "$STUB_DIR/out" && tar -xf "$STUB_DIR/loaded.tar" -C "$STUB_DIR/out"
  # The manifest, the config and layer two, each whole; not layer one.
  for d in "$man" "$cfg" "$l2"; do
    cmp "$STUB_DIR/out/blobs/sha256/${d#sha256:}" "$STUB_DIR/reg/owner/img/blobs/$d"
  done
  [ ! -e "$STUB_DIR/out/blobs/sha256/${l1#sha256:}" ]
  run jq -r '.manifests[0] | "\(.digest) \(.annotations["io.containerd.image.name"])"' "$STUB_DIR/out/index.json"
  [ "$output" = "$man example.test/owner/img:1.0" ]
  [ ! -e "$HOME/.local/state/konrad/pull" ]
}

@test "eng_pull on container: a registry that never sends the blob fails, keeping the partial" {
  stub
  local l2; l2="$(sed -n 4p "$STUB_DIR/digests")"
  mv "$STUB_DIR/reg/owner/img/blobs/$l2" "$STUB_DIR/l2"
  k 'eng_pull example.test/owner/img:1.0'
  [ "$status" -ne 0 ]
  [ ! -e "$STUB_DIR/loaded.tar" ]
  [ -d "$HOME/.local/state/konrad/pull/blobs" ]
}

@test "eng_pull on container: a pull that works needs no fallback" {
  stub
  : >"$STUB_DIR/pull-ok"
  k 'eng_pull example.test/owner/img:1.0'
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_DIR/loaded.tar" ]
  [[ "$output" != *"retrying the pull"* ]]
}
