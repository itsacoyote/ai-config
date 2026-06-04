---
name: autorun
description: Use after Define to carry an approved spec through Research → Plan → Implement → Validate → Document to a ready-for-review PR — supervised but not re-steered. Implements one task at a time in fresh subagents with permissions enforced; stops at the PR and never merges or approves. Run from the main session.
disable-model-invocation: true
allowed-tools: Read Bash(*) Agent
---

# Autorun

Supervised autonomous feature execution. Given an **approved spec** (gate 1, from `define`),
autorun drives the rest of the workflow — Research → Plan → Implement → Validate → Document —
to a **PR that's ready for human review** (gate 2), with no further semantic steering in
between. autorun reasons autonomously; you supervise *execution* by approving the permission
prompts its actions surface. It is the in-session, permissions-on path — **not** a headless
or overnight loop.

See `feature-workflow` for how the manual steps fit together; autorun is the automation that
runs them after Define.

## Before you run

- An **approved spec must be in context** (ideally a beads epic from `define`). If there
  isn't one, stop and point the user at `define` — autorun does not replace gate 1.
- **Run from the main session.** autorun spawns the `implementer` agent and the
  `senior-review`/`qa-review` agents, and subagents can't spawn subagents.
- **Two human gates only:** Define (already done) and the **PR review** at the end.
  Everything between is autonomous reasoning + *supervised execution* (you approve permission
  prompts) + exception-stops. Keep permissions **on** — a recommended allowlist keeps the
  prompts manageable (see "Permissions").

## When NOT to use

- Trivial changes — just make them. autorun is for real features where the loop earns its keep.
- When you can't supervise. autorun keeps permissions on and pauses on prompts; it is not an
  unattended runner.

## The run

1. **Research** — run `research` against the approved spec.
2. **Plan** — run `planning-and-task-breakdown`: file map + dependency-ordered tasks, each
   with a **risk marker** and **skill hints**, recorded as beads child issues (beads mode) or
   an in-session task list (standalone). The plan is **surfaced but not gated** — it is not a
   third human gate.
3. **Implement** — the loop below, one task at a time.
4. **Validate** — run `validate` (the always-run end-of-run review pass).
5. **Document** — run `document`: update docs, write the PR, `gh pr ready`. **Stop here.**

Advance only when the previous step's output is in hand. An exception-stop (see below) can
halt the run at any point and hand control back to the human.

## The implement loop

Detect mode per [`.claude/references/beads.md`](../../references/beads.md).

**Beads-enhanced:**

```
while `bd ready` lists an implementable task (skip the epic / non-leaf issues):
  pick the highest-priority ready task
  bd update <id> --claim
  spawn the `implementer` agent (Agent tool) with the DISPATCH below
  on the implementer's returned status:
    DONE               → review per cadence; on pass, bd close <id>
    DONE_WITH_CONCERNS → triage: fix correctness before closing; file follow-up issues for the rest
    NEEDS_CONTEXT      → supply what's missing, re-dispatch the same task (bounded)
    BLOCKED            → exception-stop: halt and surface to the human
  continue to the next ready task
```

**Standalone:** work down the plan's task list the same way, tracking status in the session.

Statuses follow [`.claude/references/subagent-status-protocol.md`](../../references/subagent-status-protocol.md).
You own the beads lifecycle (`claim`/`close`) and the terminal push; the implementer only
commits.

### The dispatch (lean + pull)

Hand the implementer **only its task's extracted essentials** — description, acceptance
criteria, named tests, file-map slice, skill hints, risk marker — plus the **beads IDs** of
the task, its dependencies, and the epic. Tell it explicitly: *you may `bd show <id>` to pull
more on a need-to-know basis.* Do **not** paste the whole plan or sibling tasks into the
dispatch — that lean dispatch is the point (it keeps both contexts small). The implementer
pulls anything extra it needs from beads itself.

### Review after each task

After a task returns DONE, review it according to the cadence (hybrid by default — see
"Review cadence"). Risky tasks are reviewed immediately; the rest are covered by the
always-run `validate` pass at the end. Only `bd close` a task once its review passes.

## Terminal: PR-ready, never merge

The run ends when `document` has opened the PR and marked it **ready for review**. autorun
**never** runs `gh pr merge`, never submits an approving review, and never auto-merges — PR
approval and merge are always the human's call (gate 2). If the PR can't be readied,
exception-stop instead of forcing anything.

## Status & summary

Record per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md):
beads-enhanced — progress is the issue states (claimed → closed) and the validation summary
on the epic; standalone — present a run summary in the session at the end.
