#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Diff the layers of two published image tags WITHOUT pulling either one.
# Answers the maintainer's question: "a user sitting on tag FROM — which
# layers must they download to reach tag TO (default :latest)?"
#
# OCI layers are content-addressed, so any layer whose digest appears in
# both tags is already on the user's disk; the download is exactly the
# set difference layers(TO) \ layers(FROM). We read that straight off the
# two remote manifests via `skopeo inspect` (manifest-only, no blob pull),
# so this is cheap and touches no local image store.
#
#   scripts/layer-diff.sh 0.9                    # line :0.9 -> latest
#   scripts/layer-diff.sh a1b3c0f 9f2e1d4        # explicit, immutable :<sha>
#   scripts/layer-diff.sh --arch arm64 0.9       # pick the platform
#   scripts/layer-diff.sh ghcr.io/jlbauss/konrad:0.9 konrad:latest
#
# A bare argument (no `/`) is resolved as a tag of the default repo; an
# argument containing `/` is used verbatim as a full reference.
set -euo pipefail

DEFAULT_REPO="ghcr.io/jlbauss/konrad"

usage() {
  cat <<EOF
Usage: ${0##*/} [--arch ARCH] [--repo REPO] [--local] FROM [TO]

Report the layers a user on tag FROM must download to reach tag TO,
by diffing the two manifests. Nothing is pulled.

  FROM, TO   image tags (TO defaults to "latest"). A value with no '/'
             is a tag of --repo; a value with '/' is a full reference.
  --arch     platform to inspect (amd64, arm64, ...; default: host arch).
             Ignored with --local (local images are single-arch).
  --repo     default repository for bare tags (default: $DEFAULT_REPO)
  --local    diff images from local podman storage (containers-storage)
             instead of a registry — for verifying a fresh build dedupes.
             Bare names resolve to konrad:<name>; pass full refs otherwise.
  -h, --help show this help
EOF
}

die() { printf '%s: %s\n' "${0##*/}" "$1" >&2; exit 1; }

# Host arch -> OCI arch.
host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) uname -m ;;
  esac
}

ARCH="$(host_arch)"
REPO="$DEFAULT_REPO"
LOCAL=0
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
    --arch) [ $# -ge 2 ] || die "--arch requires a value"; ARCH="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --local) LOCAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

[ "${#POSITIONAL[@]}" -ge 1 ] || { usage >&2; exit 2; }
FROM_TAG="${POSITIONAL[0]}"
TO_TAG="${POSITIONAL[1]:-latest}"

command -v jq >/dev/null 2>&1 || die "jq not found"
if [ "$LOCAL" -eq 1 ]; then
  command -v podman >/dev/null 2>&1 || die "podman not found (needed for --local)"
else
  command -v skopeo >/dev/null 2>&1 \
    || die "skopeo not found — add it to the dev container (apt-get install skopeo)"
fi

# Registry refs select a platform out of a manifest list; local images are
# single-arch, so the overrides only apply to the remote path.
if [ "$LOCAL" -eq 1 ]; then
  SOURCE_LABEL="local (podman)"
else
  OVERRIDE_ARGS=(--override-os linux --override-arch "$ARCH")
  SOURCE_LABEL="$REPO"
fi

# Resolve a CLI argument to a full image reference.
#   --local : bare name (no ':' or '/') -> konrad:<name>, else verbatim.
#   remote  : bare tag (no '/')         -> <repo>:<tag>,  else verbatim.
resolve() {
  if [ "$LOCAL" -eq 1 ]; then
    case "$1" in
      */*|*:*) printf '%s' "$1" ;;
      *)       printf 'konrad:%s' "$1" ;;
    esac
  else
    case "$1" in
      */*) printf '%s' "$1" ;;
      *)   printf '%s:%s' "$REPO" "$1" ;;
    esac
  fi
}

FROM_REF="$(resolve "$FROM_TAG")"
TO_REF="$(resolve "$TO_TAG")"

# Source acquisition. skopeo's containers-storage transport can't reach
# podman's *remote* daemon (the dev container drives the host socket), so for
# --local we read podman over that socket and reshape its output into the same
# {LayersData,…} / {history:…} shape skopeo emits — the diff pipeline below is
# then identical for both sources.
remote_manifest() {
  skopeo inspect "${OVERRIDE_ARGS[@]}" "docker://$1" 2>/dev/null \
    || die "could not inspect $1 (arch $ARCH) — tag missing or no registry access?"
}

# RootFS.Layers gives ordered layer diffIDs; History gives created_by +
# empty_layer (its non-empty entries align 1:1 with the layers). Per-layer
# sizes come from `podman history` (reversed to bottom→top, zipped by index).
pod_manifest() {
  local insp hist
  insp="$(podman image inspect "$1" --format '{{json .}}' 2>/dev/null)" \
    || die "could not inspect local image $1 (podman)"
  hist="$(podman history --format json "$1" 2>/dev/null || printf '[]')"
  jq -n --argjson insp "$insp" --argjson hist "$hist" '
    ($hist | reverse) as $h
    | [$insp.History | to_entries[]
       | {empty: (.value.empty_layer // false), size: ($h[.key].size // 0)}] as $rows
    | [$rows[] | select(.empty | not)] as $layers
    | {LayersData: [$insp.RootFS.Layers | to_entries[]
         | {Digest: .value, Size: ($layers[.key].size // 0)}]}'
}

if [ "$LOCAL" -eq 1 ]; then
  FROM_JSON="$(pod_manifest "$FROM_REF")"
  TO_JSON="$(pod_manifest "$TO_REF")"
  TO_CONFIG="$(podman image inspect "$TO_REF" --format '{{json .History}}' 2>/dev/null \
    | jq '{history: .}' 2>/dev/null || true)"
else
  FROM_JSON="$(remote_manifest "$FROM_REF")"
  TO_JSON="$(remote_manifest "$TO_REF")"
  # Annotate the new (TO) layers from TO's image config: history[] non-empty
  # entries map 1:1, in order, to the layers, each carrying its build
  # instruction. Best-effort — a missing config just drops the descriptions.
  TO_CONFIG="$(skopeo inspect --config "${OVERRIDE_ARGS[@]}" "docker://$TO_REF" 2>/dev/null || true)"
fi
[ -n "$TO_CONFIG" ] || TO_CONFIG=null

printf '\nLayers to download going %s -> %s\n' "$FROM_TAG" "$TO_TAG"
printf 'source: %s   arch: %s\n\n' "$SOURCE_LABEL" "$ARCH"

jq -rn --argjson from "$FROM_JSON" --argjson to "$TO_JSON" --argjson toconfig "$TO_CONFIG" '
  def human:
    if . == 0 then "0 B"
    else
      . as $b
      | ["B","KiB","MiB","GiB","TiB"] as $u
      | ([(($b|log)/(1024|log)|floor), 4] | min) as $e
      | "\(($b / pow(1024;$e)) * 100 | round / 100) \($u[$e])"
    end;
  def lpad($n): (" " * ([$n - length, 0] | max)) + .;
  # Shorten a created_by build line to a one-glance label: collapse
  # whitespace, then peel the `RUN [|N ARG=val …] /bin/sh -c` buildkit
  # wrapper down to the actual command, and the `#(nop)` / `# buildkit`
  # noise, before truncating.
  def shorten:
    gsub("\\s+"; " ")
    | gsub("^RUN (\\|[0-9]+ )?([^ ]+=[^ ]+ )*/bin/sh -c "; "RUN ")
    | gsub("^/bin/sh -c "; "") | gsub("#\\(nop\\) "; "")
    | gsub(" # buildkit$"; "")
    | if length > 64 then .[:63] + "…" else . end;

  ($from.LayersData) as $fl
  | ($to.LayersData) as $tl
  | if ($fl == null) or ($tl == null)
    then "skopeo returned no LayersData (layer sizes) — update skopeo?" | halt_error(1)
    else . end
  # Non-empty history entries align 1:1 with layers, in order — attach as .desc
  # only when the counts match, otherwise leave layers unlabelled.
  | [$toconfig.history // [] | .[] | select(.empty_layer != true) | .created_by] as $hist
  | (($hist | length) == ($tl | length)) as $aligned
  | [$tl | to_entries[] | .value + {desc: (if $aligned then $hist[.key] else null end)}] as $tl
  | ($fl | map(.Digest)) as $have
  | ($tl | map(select(.Digest as $d | ($have | index($d)) == null))) as $need
  | ($need | map(.Size) | add // 0) as $bytes
  | ($tl | length) as $total
  | ($need | length) as $new
  | if $new == 0 then
      "  Already up to date — all \($total) layers shared, nothing to download."
    else
      ( $need | map("  \(.Digest[7:19])  \(.Size | human | lpad(10))  \(.desc // "" | shorten)") | join("\n") ),
      "  " + ("─" * 60),
      "  \($new) of \($total) layers new — \($bytes | human) to download",
      "  (\($total - $new) shared, already on disk)"
    end
'
