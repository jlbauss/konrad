# State isolation — `.agent/` is the agent's, framework state lives elsewhere

Status: accepted 2026-05-20. Implements ROADMAP "Drop the `.agent`
session-state requirement."

This note records *why* state lives where it does after the change. The
state topology itself is enforced by [bin/konrad](../../bin/konrad) and
[image/entrypoint.sh](../../image/entrypoint.sh); when those disagree
with this note, they are canonical and the note is stale — update it.

## What this replaces

Before this change, konrad bind-mounted `<cwd>/.agent/opencode/` ↔
`/home/node/.local/share/opencode/` so opencode's framework state
(sessions, SQLite conversation DB, log files) landed in the workspace.
That meant:

- Every workspace accumulated a sessions / SQLite DB / log files
  directory that grew unbounded over time.
- The `.agent/` directory — which the planning contract claims as the
  *agent's* working memory — was also home to opencode framework state.
  Two owners, one path, no clear contract.
- `konrad clean` had to be run per-project to keep workspaces from
  bloating.

## The contract

**`.agent/` belongs to the agent.** Nothing from the framework lives
there. Layout:

```
.agent/
  task.md             # planning artifact (see task-md-and-todowrite.md)
  scratch/            # python scripts the agent wrote, exploration code
  artifacts/          # durable mid-task outputs (manual-output.<ext>, etc.)
  qa/<stamp>/         # QA evidence (PNGs etc.) — bounded retention
```

Auto-pruning: `image/entrypoint.sh` deletes anything in
`.agent/qa/*` and `.agent/scratch/*` older than 7 days at every
container start. `artifacts/` and `task.md` are hands-off — the user
may want to commit them or pick them up later.

**Opencode session state is ephemeral.** `~/.local/share/opencode/`
inside the container is no longer bind-mounted; it's just a directory
in the container's writable layer, gone on `--rm`. Sessions, SQLite,
conversation logs all die with the container.

The framing matches the planning contract: konrad is a stateless tool
that re-reads `.agent/task.md` on each run if the user has a task in
flight. The session-database UI of "previous conversations" is not the
durability story; `.agent/task.md` is. Removing the framework's parallel
durability path collapses the design to one contract.

**Logs live in a central XDG location** on the host:

```
${XDG_STATE_HOME:-$HOME/.local/state}/konrad/log/
```

This is bind-mounted to `/home/node/.local/share/opencode/log/` inside
the container — a narrow, single-purpose bind that lets opencode keep
writing structured log files (timestamped, `+Xms` deltas per line) while
keeping the workspace pristine.

Each `konrad` launch produces two files in the central log dir:

- `<konrad-timestamp>-session.txt` — a sidecar written by the
  entrypoint with the host workspace path and the start time.
- `<opencode-timestamp>.log` — opencode's structured log, as today.

The sidecar is necessary because opencode runs inside the container and
only sees `/workspace` — it can't record the host path. Sorting the dir
by timestamp pairs each sidecar with its log naturally.

There is no `konrad logs` subcommand. Following the convention of
file-writing CLI tools (`npm`, `brew`, `terraform`, opencode itself),
konrad just writes to a documented XDG path and trusts the user to use
`tail`, `less`, `grep`. The entrypoint prints the log path on every
launch.

Pruning: `bin/konrad` deletes `*.log` and `*-session.txt` older than 7
days from the central log dir at every launch (host-side, before
podman_run).

## Volumes and mounts after the change

| Mount | Purpose | Type |
|---|---|---|
| `konrad-secrets` ↔ `/home/node/.opencode-secrets/` | `auth.json` (login credentials) | named volume |
| `konrad-cache` ↔ `/home/node/.cache/opencode/` | opencode's regeneratable cache | named volume |
| `konrad-state` ↔ `/home/node/.local/state/opencode/` | last-selected model, small UI state | named volume |
| `~/.local/state/konrad/log/` ↔ `/home/node/.local/share/opencode/log/` | opencode log files + session sidecars | host XDG bind |
| `<cwd>` ↔ `/workspace` | the user's project | workspace bind |

Net change: workspace gets a `.agent/` directory it actually owns
end-to-end; one bind moved from per-workspace to host XDG; volume
count unchanged at three.

## Cleanup story

- **Workspace `.agent/qa/` and `.agent/scratch/`**: auto-pruned at
  every container start (>7d), in the entrypoint.
- **Central log dir**: auto-pruned at every `bin/konrad` launch (>7d),
  host-side. `konrad clean --all` also wipes it.
- **`.agent/artifacts/`, `.agent/task.md`**: hands-off. User
  manages. Documented in README.
- **Legacy `.agent/opencode/`**: if it exists from before this change,
  it's orphaned junk. The entrypoint prints a one-time warning telling
  the user to `rm -rf .agent/opencode/`. We don't auto-delete it
  because the user might have a stale `auth.json` there from before
  the secrets-volume migration; let them inspect.
- **Named volumes**: `konrad clean --all` wipes them as before.

## What does NOT change

- **Auth handling.** `auth.json` still lives in the `konrad-secrets`
  named volume. The entrypoint still symlinks
  `~/.local/share/opencode/auth.json` → `$SECRETS/auth.json` so
  opencode finds it where it expects. The migration step that pulled
  a stray `auth.json` out of the workspace bind is removed (the path
  no longer exists), but the symlink wiring is identical.
- **The shared volumes' identity.** `konrad-secrets`, `konrad-cache`,
  `konrad-state` keep their names and their contents. No migration
  needed.

## Why this is right

**Single ownership beats shared ownership.** `.agent/` now belongs to
the agent end-to-end. The framework keeps its state elsewhere. The user
knows what's safe to commit, ignore, or delete: anything under
`.agent/` is the model's work; anything in `~/.local/state/konrad/` is
opencode framework state.

**XDG paths beat ad-hoc paths.** Logs at `~/.local/state/konrad/log/`
are where a Unix-literate user already expects them. No CLI
subcommand needed to find them. Standard tools (`ls -t`, `tail -f`,
`grep`) just work.

**Ephemeral sessions match the model's reality.** The model's context
resets every run anyway; persisting the SQLite "previous conversations"
DB was UI polish at the cost of unbounded workspace growth. The
planning contract already provides durable task memory via
`.agent/task.md`. Dropping the framework's parallel durability path
makes the design coherent.

**Bounded cleanup, predictable disk footprint.** Auto-pruning on
container start (workspace) and CLI launch (host XDG) means neither
location grows without bound. The user never has to remember.

## Implementation pointers

- CLI mount topology + pre-launch host-side prune: [bin/konrad](../../bin/konrad)
- Entrypoint sidecar write + workspace-side prune + legacy warning: [image/entrypoint.sh](../../image/entrypoint.sh)
- Agent prompt's `.agent/` layout conventions: [image/opencode/agents/konrad.md](../../image/opencode/agents/konrad.md)
- PDF skill QA path updated to `.agent/qa/<stamp>/`: [image/opencode/skills/pdf/qa.md](../../image/opencode/skills/pdf/qa.md)
- do-it-manually skill artifact path updated to `.agent/artifacts/manual-output.<ext>`: [image/opencode/skills/do-it-manually/](../../image/opencode/skills/do-it-manually/)
