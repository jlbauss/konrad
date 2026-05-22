# `.agent/task.md` + `todowrite` — the planning contract

Status: accepted 2026-05-20. Implements ROADMAP "Understanding → planning →
refinement roundtrip" and "Plan visibility via TodoWrite," and replaces the
`planning-with-files` skill.

This note records *why* the contract looks the way it does. The contract
itself is enforced by Konrad's agent prompt at
[image/opencode/agents/konrad.md](../../image/opencode/agents/konrad.md);
when the prompt and this note disagree, the prompt is canonical and this
note is stale — update it.

## What this replaces

`planning-with-files` was imported from Claude Code's marketplace and never
adapted to opencode. Its `SKILL.md` registered five Claude-Code-only hook
event types (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`,
`PreCompact`) and used `${CLAUDE_PLUGIN_ROOT}` throughout — none of which
opencode honours. The skill was therefore ~300 lines of dead machinery in
konrad's runtime. The observed failure mode was rational: the agent loaded
the skill, recognised the framing as over-engineered for the local task,
and routed around it. We were getting the cost (long skill page eating
context) without the benefit (durable, structured planning).

Earlier versions of the agent prompt also enforced a three-tier scope
classification (quick / session / complex) where "complex" reached for
`planning-with-files`. The classification step itself wasn't free — it
forced the agent to commit to a scope before any tool calls, and in
practice the agent under-classified to avoid invoking the heavy skill.

## The contract

Two **independent** gates. They compose; neither subsumes the other.

| Gate | Trigger | Artifact |
|---|---|---|
| **`.agent/task.md`** | The task has *side effects* — file edits, side-effecting shell commands, anything that changes state outside the agent's context | A single file with a fixed shape |
| **`todowrite`** | The task is anything beyond a single Q&A / single lookup | The live in-UI checklist provided by opencode's `todowrite` tool |

Composition matrix:

| Example | `task.md`? | `todowrite`? |
|---|---|---|
| "What version of pdftotext is installed?" | no | no |
| "Explain how config layering works" | no | **yes** |
| "Rotate page 3 of this PDF" | **yes** | **yes** |
| "Refactor the auth layer" | **yes** | **yes** |

The `todowrite` gate tilts toward use. The agent only skips it for the
unambiguously trivial case (one tool call, one answer).

## `.agent/task.md` shape

Fixed-shape skeleton, kept short — a typical file fits on a screen:

```markdown
# <one-line task title>

## Understanding
<1–2 sentences: what the user wants and why, as I read it>

## Plan
<3–5 bullets: the path I'm taking. Not micro-steps — those go in todowrite.>

## Success looks like
<1–2 bullets: how I'll know I'm done. The quality-assurance skill reads this later.>

## Decisions & findings
<appended to during execution: key forks taken, things discovered>

## Outcome
<filled at end: what shipped, what didn't, any caveats>
```

The file is durable: it survives context compaction, lives at a fixed
path, and is the post-task receipt the user can read later.

## Roundtrip behaviour

The agent writes `Understanding` + `Plan` + `Success looks like` **before**
the first side-effecting tool call. Then it branches by certainty:

- **Confident** → surface the file inline in the response and proceed.
  The user can interrupt at any time.
- **Uncertain** → call `question` quoting the plan, wait for the user.
  Triggers: ambiguous goal, multiple valid interpretations, irreversible
  step, scope unclear.

Default friction is low: most tasks proceed without an explicit
confirmation round-trip. The agent only round-trips when the cost of
guessing wrong actually warrants it. This is the operational form of the
ROADMAP "Understanding → planning → refinement roundtrip" bullet.

## Why these specific decisions

**Why a single file, not three?** The previous shape was `task_plan.md`
(phases) + `findings.md` (research) + `progress.md` (session log). Three
files meant three sync surfaces; agents kept one updated and let the
others rot. One file with named sections gives the same separation of
concerns without the bookkeeping tax.

**Why "side effects" as the file gate, not "complex"?** Complexity is a
prediction the agent has to make before it knows enough; "does this task
edit state?" is a binary check the agent can make at the first
tool-selection step. Removing the prediction removes the failure mode of
under-classifying to dodge work.

**Why "anything but a trivial Q&A" as the todowrite gate?** TodoWrite is
cheap — one tool call to declare intent, then check-offs as work
progresses. Used aggressively, it makes "where are you?" answerable
without the user asking. The previous threshold (3+ steps) was set when
todowrite was being weighed against `planning-with-files`; with the heavy
skill gone, todowrite has no rival and should be the default for any
work-shaped request.

**Why does `task.md` not enumerate every micro-step?** That's
`todowrite`'s job. The file holds *what* and *why*; `todowrite` holds
*where the agent is right now*. Each tool stays in its lane — no
duplication, no sync burden, no drift.

**Why does the quality-assurance skill read the file, not `todowrite`?**
Verification's input is "user wanted X; did we deliver X?" — that's
`Plan` + `Success looks like` + `Outcome`, all in `task.md`. The
in-flight checklist isn't relevant to the verdict. This is also why
the design pairs naturally with the ROADMAP "no AI slop" bullet: both
rely on the same artifact.

## What got dropped from the old skill

For posterity, the explicit non-survivors:

- **Three-file layout** (`task_plan.md` / `findings.md` / `progress.md`).
- **Parallel-plan directories** (`.planning/<id>/`) and the active-plan
  pointer.
- **SHA-256 plan attestation.** Useful in adversarial contexts; not worth
  the surface area for konrad's threat model.
- **Hook-based context injection.** Required Claude-Code-only events.
- **`session-catchup.py`** (post-`/clear` context recovery). The new file
  is small enough that re-reading it after compaction is the recovery
  path; no script needed.
- **`/plan-attest`, `/plan-loop`, `/plan-goal` slash commands.**
  Claude-Code-only constructs.
- **The 3-strike error protocol** as a separate doctrine. The agent
  prompt's existing "report → propose → ask via `question`" rule already
  covers this; we don't need an additional escalation ladder on top.

## Implementation pointers

- Agent contract: [image/opencode/agents/konrad.md](../../image/opencode/agents/konrad.md)
- Skill directory: deleted (`image/opencode/skills/planning-with-files/`
  was removed).
- Files referencing the old contract were updated in the same commit
  that introduced this note: `CLAUDE.md`, `README.md`, `ROADMAP.md`.
