<!--
SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
SPDX-License-Identifier: AGPL-3.0-or-later
-->

## Summary

<!-- What this changes, in a few bullets. One concern per commit; the commits carry the detail. -->

## Why

<!-- The problem or ROADMAP item this answers, and any design decision a reviewer should weigh. -->

## Validation run

<!-- What already ran, with results: `scripts/check.sh`, `konrad-dev rebuild` + `scripts/smoke-test.sh konrad:local`, `scripts/selftest.sh`, probes. Say what was skipped and why. -->

## Maintainer probes

<!-- What only the maintainer can run (host-only: a real model, apple/container, native networking, the installer from the forge), as a runbook to paste from a native checkout: setup (checkout the branch; `konrad-dev rebuild` or not), the binary (`konrad-dev`, never `konrad`), any pre-state cleanup, a baseline that proves the environment is right, then the one change under test, with the expected output of each, then cleanup. Open with one line per supported platform (Linux + Podman, macOS + Apple's `container`): required, and why, or not needed, and why. Format: CLAUDE.md → Working with the user. Write it as a task list: shared setup as plain text, then one `- [ ]` item per probe with its steps indented beneath, so the maintainer can tick each as it passes. "None" if nothing is host-only. -->

## Release

<!-- VERSION bump and CHANGELOG entry, or "none" (doc/CI/contributor-only). A bump is the last commit and promotes `## [Unreleased]` in the same commit. -->
