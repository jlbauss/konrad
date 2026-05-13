#!/usr/bin/env node
// merge-config.js — deep-merge two JSONC files and write the result to stdout.
//
// Usage:
//   node merge-config.js <defaults.jsonc> <override.jsonc>
//
// Semantics:
//   - Objects merge recursively (override wins on key conflict).
//   - Arrays REPLACE (override's array fully replaces defaults' array if both set).
//   - Scalars REPLACE (override wins).
//   - Keys present only in defaults are kept.
//   - Keys present only in override are added.
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
  const [, , defaultsPath, overridePath] = process.argv;
  if (!defaultsPath || !overridePath) {
    process.stderr.write('usage: merge-config.js <defaults.jsonc> <override.jsonc>\n');
    process.exit(2);
  }
  const merged = deepMerge(parseJsonc(defaultsPath), parseJsonc(overridePath));
  process.stdout.write(JSON.stringify(merged, null, 2) + '\n');
}

main();
