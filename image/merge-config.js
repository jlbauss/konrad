#!/usr/bin/env node
// merge-config.js — deep-merge a left-to-right sequence of JSONC files and
// write the result to stdout.
//
// Usage:
//   node merge-config.js <base.jsonc> [overlay.jsonc ...]
//
// Folds left: the first file is the base, each subsequent file is merged on
// top of the running result, so the LAST file wins on conflicts. With konrad's
// config layers that's `baked < org < user` (call it with the layers present,
// in that order). The two-argument form (base + one override) still behaves
// exactly as before. A single argument is valid too — it just parses, strips
// comments, and re-serializes that one file (the no-overlay case).
//
// Semantics (per merge step, applied in fold order):
//   - Objects merge recursively (later file wins on key conflict).
//   - Arrays REPLACE (a later file's array fully replaces an earlier one).
//   - Scalars REPLACE (later wins).
//   - Keys present only in an earlier file are kept.
//   - Keys present only in a later file are added.
//
// Self-contained: parses JSONC by stripping comments with a small
// stateful stripper (string-aware, so URLs containing // are safe).
'use strict';

const fs = require('fs');

function stripJsonComments(src) {
  let out = '';
  let inString = false;
  let inLine = false;
  let inBlock = false;
  let escaped = false;

  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const next = src[i + 1];

    if (inLine) {
      if (c === '\n') { inLine = false; out += c; }
      continue;
    }
    if (inBlock) {
      if (c === '*' && next === '/') { inBlock = false; i++; }
      continue;
    }
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c === '\\') {
        escaped = true;
      } else if (c === '"') {
        inString = false;
      }
      out += c;
      continue;
    }
    if (c === '"') { inString = true; out += c; continue; }
    if (c === '/' && next === '/') { inLine = true; i++; continue; }
    if (c === '/' && next === '*') { inBlock = true; i++; continue; }
    out += c;
  }
  return out;
}

function parseJsonc(path) {
  const raw = fs.readFileSync(path, 'utf8');
  try {
    return JSON.parse(stripJsonComments(raw));
  } catch (err) {
    process.stderr.write(`merge-config: failed to parse ${path}: ${err.message}\n`);
    process.exit(2);
  }
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function deepMerge(target, source) {
  for (const key of Object.keys(source)) {
    const sv = source[key];
    const tv = target[key];
    if (isPlainObject(sv) && isPlainObject(tv)) {
      target[key] = deepMerge(tv, sv);
    } else {
      target[key] = sv;
    }
  }
  return target;
}

function main() {
  const inputs = process.argv.slice(2);
  if (inputs.length < 1) {
    process.stderr.write('usage: merge-config.js <base.jsonc> [overlay.jsonc ...]\n');
    process.exit(2);
  }
  // Left-fold: parse each file, merge each onto the running accumulator.
  // reduce() with no seed uses the first parsed file as the initial value, so
  // a single input is returned as-is (parsed + comment-stripped). deepMerge
  // mutates and returns its first arg, which is what we want for the fold.
  const merged = inputs
    .map(parseJsonc)
    .reduce((acc, next) => deepMerge(acc, next));
  process.stdout.write(JSON.stringify(merged, null, 2) + '\n');
}

main();
