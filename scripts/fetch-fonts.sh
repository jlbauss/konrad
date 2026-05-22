#!/usr/bin/env bash
# Pull the konrad font palette from canonical upstreams into image/fonts/konrad/.
# One-shot script — run when bumping a font version. The fetched files are
# committed to the repo so the image build itself does not need network access.
#
# Usage:  ./scripts/fetch-fonts.sh           # fetch all
#         ./scripts/fetch-fonts.sh inter     # fetch one family
#
# Each family lands in image/fonts/konrad/<family>/ alongside its OFL/Apache
# license text. Update NOTICE when versions change.
set -euo pipefail

INTER_VERSION="4.1"
SOURCE_SERIF_VERSION="4.005"
JETBRAINS_MONO_VERSION="2.304"
FRAUNCES_REF="master"
EB_GARAMOND_REF="master"
IBM_PLEX_REF="master"
ATKINSON_REF="main"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/image/fonts/konrad"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

want() {
    [ "$#" -eq 0 ] && return 0
    for arg in "$@"; do [ "$arg" = "$FAMILY" ] && return 0; done
    return 1
}

mkdir -p "$DEST"

# -----------------------------------------------------------------------------
# Inter (OFL, rsms)
# -----------------------------------------------------------------------------
FAMILY=inter
if want "$@"; then
    echo "→ Inter v$INTER_VERSION"
    rm -rf "$DEST/Inter"
    mkdir -p "$DEST/Inter"
    curl -fsSL "https://github.com/rsms/inter/releases/download/v${INTER_VERSION}/Inter-${INTER_VERSION}.zip" \
        -o "$TMP/inter.zip"
    unzip -q "$TMP/inter.zip" -d "$TMP/inter"
    # Static TTFs ship under extras/ttf/Inter-{Regular,Italic,Bold,BoldItalic}.ttf
    cp "$TMP/inter/extras/ttf/Inter-Regular.ttf"    "$DEST/Inter/"
    cp "$TMP/inter/extras/ttf/Inter-Italic.ttf"     "$DEST/Inter/"
    cp "$TMP/inter/extras/ttf/Inter-Bold.ttf"       "$DEST/Inter/"
    cp "$TMP/inter/extras/ttf/Inter-BoldItalic.ttf" "$DEST/Inter/"
    cp "$TMP/inter/LICENSE.txt" "$DEST/Inter/LICENSE.txt"
fi

# -----------------------------------------------------------------------------
# Source Serif 4 (OFL, Adobe)
# -----------------------------------------------------------------------------
FAMILY=source-serif
if want "$@"; then
    echo "→ Source Serif 4 v$SOURCE_SERIF_VERSION"
    rm -rf "$DEST/SourceSerif4"
    mkdir -p "$DEST/SourceSerif4"
    base="https://github.com/adobe-fonts/source-serif/raw/${SOURCE_SERIF_VERSION}R/TTF"
    for w in Regular It Bold BoldIt; do
        curl -fsSL "$base/SourceSerif4-${w}.ttf" -o "$DEST/SourceSerif4/SourceSerif4-${w}.ttf"
    done
    curl -fsSL "https://github.com/adobe-fonts/source-serif/raw/${SOURCE_SERIF_VERSION}R/LICENSE.md" \
        -o "$DEST/SourceSerif4/LICENSE.md"
fi

# -----------------------------------------------------------------------------
# Fraunces (OFL, Undercase Type) — ship variable file (Fraunces is designed
# as a variable font; static instances are lossy on its opsz/soft/wonk axes).
# -----------------------------------------------------------------------------
FAMILY=fraunces
if want "$@"; then
    echo "→ Fraunces ($FRAUNCES_REF)"
    rm -rf "$DEST/Fraunces"
    mkdir -p "$DEST/Fraunces"
    base="https://github.com/undercasetype/Fraunces/raw/${FRAUNCES_REF}/fonts/variable"
    curl -fsSL "$base/Fraunces%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf" \
        -o "$DEST/Fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf"
    curl -fsSL "$base/Fraunces-Italic%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf" \
        -o "$DEST/Fraunces/Fraunces-Italic[SOFT,WONK,opsz,wght].ttf"
    curl -fsSL "https://github.com/undercasetype/Fraunces/raw/${FRAUNCES_REF}/OFL.txt" \
        -o "$DEST/Fraunces/OFL.txt"
fi

# -----------------------------------------------------------------------------
# JetBrains Mono (Apache 2.0)
# -----------------------------------------------------------------------------
FAMILY=jetbrains-mono
if want "$@"; then
    echo "→ JetBrains Mono v$JETBRAINS_MONO_VERSION"
    rm -rf "$DEST/JetBrainsMono"
    mkdir -p "$DEST/JetBrainsMono"
    curl -fsSL "https://github.com/JetBrains/JetBrainsMono/releases/download/v${JETBRAINS_MONO_VERSION}/JetBrainsMono-${JETBRAINS_MONO_VERSION}.zip" \
        -o "$TMP/jbm.zip"
    unzip -q "$TMP/jbm.zip" -d "$TMP/jbm"
    cp "$TMP/jbm/fonts/ttf/JetBrainsMono-Regular.ttf"    "$DEST/JetBrainsMono/"
    cp "$TMP/jbm/fonts/ttf/JetBrainsMono-Italic.ttf"     "$DEST/JetBrainsMono/"
    cp "$TMP/jbm/fonts/ttf/JetBrainsMono-Bold.ttf"       "$DEST/JetBrainsMono/"
    cp "$TMP/jbm/fonts/ttf/JetBrainsMono-BoldItalic.ttf" "$DEST/JetBrainsMono/"
    cp "$TMP/jbm/OFL.txt" "$DEST/JetBrainsMono/LICENSE.txt"
fi

# -----------------------------------------------------------------------------
# EB Garamond (OFL, Georg Duffner / Octavio Pardo)
# -----------------------------------------------------------------------------
FAMILY=eb-garamond
if want "$@"; then
    echo "→ EB Garamond ($EB_GARAMOND_REF)"
    rm -rf "$DEST/EBGaramond"
    mkdir -p "$DEST/EBGaramond"
    base="https://github.com/octaviopardo/EBGaramond12/raw/${EB_GARAMOND_REF}/fonts/ttf"
    for w in Regular Italic Bold BoldItalic; do
        curl -fsSL "$base/EBGaramond-${w}.ttf" -o "$DEST/EBGaramond/EBGaramond-${w}.ttf"
    done
    curl -fsSL "https://github.com/octaviopardo/EBGaramond12/raw/${EB_GARAMOND_REF}/OFL.txt" \
        -o "$DEST/EBGaramond/OFL.txt"
fi

# -----------------------------------------------------------------------------
# IBM Plex Sans (OFL, IBM)
# -----------------------------------------------------------------------------
FAMILY=ibm-plex-sans
if want "$@"; then
    echo "→ IBM Plex Sans ($IBM_PLEX_REF)"
    rm -rf "$DEST/IBMPlexSans"
    mkdir -p "$DEST/IBMPlexSans"
    base="https://github.com/IBM/plex/raw/${IBM_PLEX_REF}/packages/plex-sans/fonts/complete/ttf"
    for w in Regular Italic Bold BoldItalic; do
        curl -fsSL "$base/IBMPlexSans-${w}.ttf" -o "$DEST/IBMPlexSans/IBMPlexSans-${w}.ttf"
    done
    curl -fsSL "$base/license.txt" -o "$DEST/IBMPlexSans/LICENSE.txt"
fi

# -----------------------------------------------------------------------------
# Atkinson Hyperlegible (OFL, Braille Institute)
# -----------------------------------------------------------------------------
FAMILY=atkinson
if want "$@"; then
    echo "→ Atkinson Hyperlegible ($ATKINSON_REF)"
    rm -rf "$DEST/AtkinsonHyperlegible"
    mkdir -p "$DEST/AtkinsonHyperlegible"
    base="https://github.com/googlefonts/atkinson-hyperlegible/raw/${ATKINSON_REF}/fonts/ttf"
    for w in Regular Italic Bold BoldItalic; do
        curl -fsSL "$base/AtkinsonHyperlegible-${w}.ttf" \
            -o "$DEST/AtkinsonHyperlegible/AtkinsonHyperlegible-${w}.ttf"
    done
    curl -fsSL "https://github.com/googlefonts/atkinson-hyperlegible/raw/${ATKINSON_REF}/OFL.txt" \
        -o "$DEST/AtkinsonHyperlegible/OFL.txt"
fi

echo
echo "Done. Total size:"
du -sh "$DEST"
echo
echo "Per family:"
du -sh "$DEST"/*/
