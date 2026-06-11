# Architecture

How Konrad is built and *why* — the load-bearing choices and the rationale
behind the non-obvious ones. Where this doc and the code disagree, the code is
canonical; fix the doc.

## Repository guide

One audience and one job per file:

| File | Purpose |
| --- | --- |
| [README.md](README.md) | End-user guide — what Konrad is, install, use, configure. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | This file — system design and the *why*. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributor guide — dev loop, branching, commit style, **versioning & releases**. |
| [CLAUDE.md](CLAUDE.md) | Instructions for AI agents working on Konrad's source. |
| [ROADMAP.md](ROADMAP.md) | Backlog tiers (Inbox / Tier 1 / Tier 2 / Post-1.0 / Obsolete). |
| [CHANGELOG.md](CHANGELOG.md) | Released, user-facing changes (Keep a Changelog). |
| [VERSION](VERSION) | Single source of the version; drives image tags. |
| [LICENSE](LICENSE) · [REUSE.toml](REUSE.toml) · [LICENSES/](LICENSES/) | AGPL-3.0; per-file copyright/license (REUSE spec). |

Code layout (`bin/`, `image/`, `scripts/`) is mapped in [CONTRIBUTING.md](CONTRIBUTING.md#repo-layout--what-goes-where).

## The big picture

Konrad runs [opencode](https://github.com/sst/opencode) inside a sandboxed, rootless Podman container.

- **The image is the canonical artifact.** `image/Dockerfile` builds it; `bin/konrad` — a thin host-side bash CLI — is the primary consumer. A second consumption path — a `konrad init-devcontainer` that scaffolds a Dev Container into the user's own project — is on the [ROADMAP.md](ROADMAP.md).
- **Podman, not Docker.** Open-source, free for commercial use, ergonomic on macOS. `--userns=keep-id` shares the container `node` user's UID with the host user, so bind-mounted files have sane ownership. Docker support is on the roadmap.
- **Tuned for Qwen3.6-class local models.** The agent prompt ([image/opencode/agents/konrad.md](image/opencode/agents/konrad.md)) is sized for a ~30B-class local model; the tested recommendation is `qwen/qwen3.6-27b`. Frontier models work fine; sub-10B ones may need prompt softening.

## Engineering ethos — lightweight, composed, low-maintenance

The guiding principle behind every other choice here: **Konrad stays lightweight and leans on well-maintained building blocks rather than custom code.** Prefer configuring an existing tool over shipping bespoke machinery; drive ongoing maintenance toward zero, so Konrad keeps working and current even through stretches when no one is actively developing it. (This is why model-discovery's custom plugin was dropped, the config deep-merge is a tiny self-contained step, and the whole pinning/rebuild story is a bot plus upstream registries.)

Its second face: **simple, logical, and smooth beats clever.** Konrad should stay tidy and resist sprawl. A solution that *feels* surprising (e.g. the runtime user lacking write access everywhere in its own home) is a smell to fix at the structural cause, not a quirk to live with — today's quiet workaround is tomorrow's unexpected consequence. Accumulating complexity is debt to pay down deliberately; periodic cleanliness passes are part of the maintenance story.

## Configuration & instructions

Config is **layered, not replaced** — three host-mergeable layers, folded left, last writer wins:

```
baked image defaults   <   org                    <   user
/etc/konrad/…               ~/.config/konrad/org/      ~/.config/konrad/user/
```

- Each layer holds the same five opencode pieces — `opencode.jsonc`, `agents/`, `skills/`, `AGENTS.md`, `fonts/`. [image/entrypoint.sh](image/entrypoint.sh) composes them via [image/merge-config.js](image/merge-config.js) (an N-input deep-merge) before opencode loads anything. **Objects merge recursively; arrays replace** — which is why agent rules are added via `AGENTS.md`, not by overriding the `instructions` array. (A layer may also carry an `allowed_hosts` file — Konrad-specific, consumed by the egress firewall, *not* part of this opencode merge.)
- **Discovery is a well-known `$HOME` folder** (`~/.config/konrad/{org,user}`), not an env var or system path — because the macOS Podman machine only auto-shares `$HOME` into its VM, so a `/etc`-style path would be invisible there.
- **`AGENTS.md` is the user's slot; `instructions` is Konrad's.** opencode loads both, additively. The **org** `AGENTS.md` rides the `instructions` channel — the entrypoint appends it with `jq` *after* the merge, so the array-replace rule can't silently drop it — while the user's global `AGENTS.md` stays theirs alone. Precedence, all additive: `environment.md → org AGENTS.md → user AGENTS.md → project AGENTS.md`.
- The org layer is **defaults, not enforcement**: files in the user's own home, so "add-only" describes merge precedence, not a permission lock.
- **No model auto-discovery, no baked `model`.** Provider endpoints ship pre-wired but model lists ship empty — users declare their loaded models in `opencode.jsonc`; opencode prompts for the model on first run and remembers it in the `konrad-state` volume.

## State, secrets & isolation

**`.agent/` belongs to the agent end-to-end; framework state lives elsewhere.**

```
.agent/
  task.md                     # planning artifact (committable)
  artifacts/                  # durable mid-task outputs (committable)
  scratch/                    # agent scripts / probes (auto-pruned >7d)
  quality-assurance/<stamp>/  # verification evidence on a fail (auto-pruned >7d)
```

- **Sessions are ephemeral.** opencode's `~/.local/share/opencode/` isn't bind-mounted — sessions, SQLite DB, and logs die with `--rm`. Durable task memory is `.agent/task.md`, not the session DB; collapsing the two parallel durability paths keeps the design coherent.
- **Secrets never touch the workspace** — `auth.json` lives only in the `konrad-secrets` named volume.
- **Logs land at a host XDG path** (`~/.local/state/konrad/log/`), bind-mounted narrowly so opencode keeps writing structured logs while the workspace stays pristine. No `konrad logs` subcommand — write to a documented path and trust `tail`/`grep`, like `npm`/`brew`.

| Mount | Purpose | Type |
|---|---|---|
| `konrad-secrets` ↔ `…/.opencode-secrets/` | `auth.json` | named volume |
| `konrad-cache` ↔ `…/.cache/opencode/` | regeneratable cache | named volume |
| `konrad-state` ↔ `…/.local/state/opencode/` | model choice, small UI state | named volume |
| `~/.local/state/konrad/log/` ↔ `…/opencode/log/` | logs + session sidecars | host XDG bind |
| `<cwd>` ↔ `/workspace` | the user's project | workspace bind |

`--profile <name>` suffixes the state + cache volumes for throwaway self-test isolation; `konrad --reset` wipes the volumes + log dir.

### Egress firewall

**The agent has no direct route to the internet; a sidecar proxy is the only way out, and it forwards only an allow-list.** This closes the network as an exfiltration channel — a prompt-injected agent can't ship the workspace or the provider credentials to an arbitrary host.

- **Two networks, per run.** `bin/konrad` creates an `--internal` Podman network (no route out) and a normal egress network. The agent joins *only* the internal one; the proxy joins both. So the boundary is enforced by Podman's networking, not by the agent's cooperation — the agent (uid 1000) can't reconfigure it. A Podman *pod* can't do this: pod members share one netns, so they'd share the same egress. Separate containers on separate networks is what isolates them.
- **A forward proxy, on purpose.** The agent gets `HTTP(S)_PROXY` pointed at the sidecar. opencode runs on Bun, which honours those env vars for `fetch`; this was verified end-to-end (its HTTPS model-catalog `CONNECT` and local-model HTTP calls both route through). A forward proxy keeps the agent capability-less — no `NET_ADMIN`, no nftables, no transparent-interception machinery. The proxy is [tinyproxy](https://tinyproxy.github.io/) (`apt`-installed into the one image, not a second artifact to pin/pull) with `FilterDefaultDeny` + an anchored host filter.
- **The allow-list is derived, not hand-maintained.** The proxy runs the *same* `merge-config.js` over the *same* baked < org < user layers the agent sees, and extracts every `provider.*.options.baseURL` host — so it tracks the user's real providers automatically. Unioned with a deliberately tiny baked floor — `host.containers.internal` (local models) and `registry.npmjs.org` (the on-demand provider SDK adapters opencode isn't already bundling) — plus the org/user `allowed_hosts` files (+ `--allow-host` for a run). The floor was trimmed empirically: a configured model resolves and runs without `models.dev`, and OpenAI-compatible providers need no npm fetch, so `models.dev`/PyPI/the open web are opt-in, not default. Running the proxy *from Konrad's own image* is what makes the derivation free — a stock proxy image would have neither the merge tool nor the config layers. Host-based filtering (not IP) is deliberate: remote providers sit behind rotating cloud IPs.
- **Default-on, with a clean bypass.** On for every `run`/`--shell`/`run`-oneshot launch; `--no-firewall` (or `KONRAD_FIREWALL=0`) restores the pre-firewall unrestricted path (a bare `exec podman run`). The proxy + networks are per-run (`$$`-named) and torn down by an EXIT trap. Mechanism lives in [image/konrad-proxy-entrypoint.sh](image/konrad-proxy-entrypoint.sh) and `fw_setup`/`fw_teardown` in [bin/konrad](bin/konrad).

## The planning contract

Two **independent** gates, baked into the agent prompt ([image/opencode/agents/konrad.md](image/opencode/agents/konrad.md)):

- **`.agent/task.md`** — when the task has *side effects* (file edits, state-changing commands). A binary check at first tool-selection, not a complexity prediction. The agent writes it *before* the first side-effecting call, in a fixed shape:

```markdown
# <task title>
## Understanding       — what the user wants, as I read it
## Plan                — 3–5 bullets (the path, not micro-steps)
## Success looks like  — how I'll know I'm done
## Decisions & findings — appended during execution
## Outcome             — what shipped, what didn't, caveats
```

- **`todowrite`** — for anything beyond a trivial single Q&A; opencode's live in-UI checklist.

`task.md` holds *what & why* (durable, survives context compaction); `todowrite` holds *where the agent is right now*. No overlap, no sync burden. The agent surfaces the plan inline and proceeds when confident, or asks via `question` when a wrong guess would be costly (ambiguous goal, irreversible step). The `quality-assurance` skill later reads `task.md`'s Plan + Success + Outcome to render its verdict.

## Build & reproducibility

**Every input is locked; a bot maintains the locks; the publish is smoke-gated.**

- Each input is digest- or version-locked in [image/locks/](image/locks/): base image, the `uv` source image, Python deps (`python.lock`), `opencode-ai`, `typst`, and the Docling model repos (`models.lock` — commit-pinned so the ~1.1 GB model layer stays byte-stable across rebuilds; one `COPY` layer per model means a single-model update re-pulls only that model, not the whole set). apt packages float — they refresh whenever the base image bumps. The [image/Dockerfile](image/Dockerfile) top comment mirrors this list.
- The Python venv ships as **three `COPY` layers** (the `venv-split` build stage partitions it): torch (~700 MB), the large slow-moving numeric wheels (opencv/scipy/numpy/onnxruntime/sympy, ~450 MB), and the churny remainder (~360 MB). So a `python.lock` bump that only moves a small pure-python dep — the near-daily case, since the bot tracks every transitive — re-pulls just the light layer, while torch and the numeric set dedupe (same byte-stability mechanism as the per-model split above). Sibling to the model-layer dedupe.
- The GitLab `resolve-locks` bot re-resolves each upstream daily and opens an auto-merging MR **only when something moved** — so a rebuild fires only when there's genuinely something new. No scheduled cron rebuild. (The build-side of the low-maintenance ethos: freshness is a bot plus upstream registries, not hand-tended bumps.)
- **Reproducible layers** — CI builds with `SOURCE_DATE_EPOCH=0` + `rewrite-timestamp=true`, so byte-identical content yields byte-identical layer digests; that's what lets users skip a re-download when nothing actually changed. Local `konrad-dev --rebuild` writes `konrad:local`, separate from the published `:latest`.
- **CI runs on a GitHub mirror; the primary repo stays on `gitlab.git.nrw`** (one-way push mirror → GitHub Actions does build → smoke → publish to `ghcr.io/jlbauss/konrad`). Why: gitlab.git.nrw's shared runners can't run the privileged Podman build. The GitHub side is a CI execution surface only — no issues, no MRs. (Full contributor + release flow: [CONTRIBUTING.md](CONTRIBUTING.md).)
- Every image carries `/etc/konrad/build-manifest.json` (dpkg / npm / pip versions + build metadata); `diff` two dated `:0.X.Y-<date>` images' manifests to bisect a regression to its upstream cause.

## Licensing

**AGPL-3.0** — compatible with all bundled upstream licenses (MIT, Apache-2.0, OFL-1.1). Strong copyleft is deliberate for a sandbox-style tool: AGPL's network-use clause closes the SaaS loophole plain GPL leaves open, so a fork offered as a hosted remote agent over an API must still publish its source. Per-file copyright + license is declared machine-readably following the [REUSE](https://reuse.software) spec (`REUSE.toml` + `LICENSES/`, `reuse lint`-verified); acknowledgements (the runtime, the model, adapted prompt-patterns) live in the [README](README.md#license-and-attribution).
