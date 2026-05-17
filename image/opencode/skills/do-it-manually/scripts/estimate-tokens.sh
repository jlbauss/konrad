#!/bin/sh
# Approximate token count for one or more files.
#
# Heuristic: ~3.5 characters per token across mixed English / code / data.
# This is intentionally crude — its job is to answer "fits comfortably"
# vs "doesn't fit", not to be exact. Real counts vary by content:
#   - dense code:        ~3.0 chars/token
#   - English prose:     ~4.0 chars/token
#   - German prose:      ~3.0 chars/token (compound nouns are dense)
#   - structured JSON:   ~3.5 chars/token
# 3.5 is a safe middle estimate that errs slightly toward over-counting,
# which is what you want — better to chunk one file too many than to
# run out of context mid-transformation.
#
# Usage: estimate-tokens.sh <file> [<file> ...]
set -eu

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <file> [<file> ...]" >&2
    exit 2
fi

total_chars=0
total_lines=0

for f in "$@"; do
    if [ ! -r "$f" ]; then
        echo "estimate-tokens: cannot read '$f'" >&2
        exit 1
    fi
    chars=$(wc -c < "$f")
    lines=$(wc -l < "$f")
    # integer math: chars * 10 / 35 == chars / 3.5
    tokens=$(( chars * 10 / 35 ))
    printf '%-50s  %10d chars  %8d lines  ~%8d tokens\n' "$f" "$chars" "$lines" "$tokens"
    total_chars=$((total_chars + chars))
    total_lines=$((total_lines + lines))
done

if [ "$#" -gt 1 ]; then
    total_tokens=$(( total_chars * 10 / 35 ))
    printf -- '---\n'
    printf '%-50s  %10d chars  %8d lines  ~%8d tokens\n' "TOTAL" "$total_chars" "$total_lines" "$total_tokens"
fi

cat <<'EOF'

Heuristic: ~3.5 chars/token. Now compare to your remaining context budget:
  < 30%  → ingest directly
  30-70% → chunk before processing
  > 70%  → stop, escalate to subagent or external split
EOF
