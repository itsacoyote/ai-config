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
  `senior-review`/`design-review`/`qa-review` agents, and subagents can't spawn subagents.
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

**Beads-enhanced.** On (re)invoke, **reclaim stranded work first**: `bd ready` lists only
`open` tasks, so a task claimed (`in_progress`) but not yet closed — the common interruption
point — would otherwise be skipped on resume. Pull it back in before taking new work.

```
# resume: reclaim anything left in progress from a prior run
for each in_progress task under the epic (claimed, not closed):
  re-dispatch it (DISPATCH below); on a passing review, bd close <id>

# then drain ready work
while `bd ready` lists an implementable task (skip the epic / non-leaf issues):
  pick the highest-priority ready task
  bd update <id> --claim
  spawn the `implementer` agent (Agent tool) with the DISPATCH below
  on the implementer's returned status:
    DONE               → review per cadence; on pass, bd close <id>
    DONE_WITH_CONCERNS → triage: fix correctness before closing; file follow-up issues for the rest
    NEEDS_CONTEXT      → supply what's missing, re-dispatch the same task (bounded: 3, then exception-stop)
    BLOCKED            → exception-stop: halt and surface to the human
  continue to the next ready task
```

Find stranded tasks with `bd list --status in_progress` scoped to the epic.

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

## Review cadence

Hybrid by default, overridable at launch.

- **Hybrid (default):** a task marked `review-per-task` (by `planning-and-task-breakdown`,
  for sensitive or high-blast-radius work) is reviewed **immediately** after it returns DONE;
  tasks marked `end-of-run` are not reviewed individually — the always-run `validate` pass
  covers them. Escalate any task to per-task review on your own judgment too (e.g. the
  implementer returned DONE_WITH_CONCERNS, or it touched more than its file-map slice).
- **Launch override:** honor a cadence instruction passed at launch over the default — e.g.
  *"review every task"*, *"only validate at the end"*, *"review tasks 3 and 7 individually"*.
  The end-of-run `validate` runs regardless.
- **How a per-task review runs:** reuse the `validate` loop shape on just that task's change —
  spawn `senior-review` (and `qa-review` if it added testable behavior, and `design-review` for
  frontend-risky tasks that touch components/markup/styles), apply fixes, re-review, **bounded
  to 3 iterations**. Don't `bd close` the task until its review passes.

## Models (per-role knob)

Each subagent runs on the model best suited to its role, overridable at launch:

- **implementer** → a fast/capable model (the agent defaults to Sonnet).
- **reviewers** (`senior-review` → Opus, `design-review` → Opus, `qa-review` → Sonnet) → their own frontmatter defaults.

Override per spawn with the `Agent` tool's `model` parameter (resolution:
`CLAUDE_CODE_SUBAGENT_MODEL` env > per-call > agent frontmatter > session model). If the
user names models at launch, use those.

## Exception stops

An exception-stop is a **safety halt** that hands control back to the human mid-run — distinct
from the two gates. Stop and surface — don't grind or guess — when:

- a task's review still fails after the bounded fix cycles (3, per `validate`),
- the implementer returns **BLOCKED**, or
- an action hits a permission denial it can't proceed past.

Report which task, what happened, what was tried, and your read of the cause (context gap /
oversized task / flawed plan / environment). The human decides; autorun does not retry blindly.

## Permissions

autorun runs with **permissions enforced** — every consequential action (writes, commits,
installs, push) surfaces an approval prompt the human answers. This is what makes it safe
where `--dangerously-skip-permissions` is forbidden. **Never** set
`permissionMode: bypassPermissions` (or `dontAsk`) on the subagents autorun spawns — they
inherit the session's permissions by design.

To keep a supervised run from death-by-prompt, pre-approve the safe, high-frequency operations
in `.claude/settings.local.json` (via `update-config`) — for example:

```
Bash(bd *), Bash(git status*), Bash(git diff *), Bash(git log *), <test runner>, <linter>
```

Leave genuinely consequential actions (file writes, `git push`, installs) to prompt. The
allowlist reduces friction; it does not remove supervision.

## Terminal: PR-ready, never merge

The run ends when `document` has opened the PR and marked it **ready for review**. autorun
**never** runs `gh pr merge`, never submits an approving review, and never auto-merges — PR
approval and merge are always the human's call (gate 2). If the PR can't be readied,
exception-stop instead of forcing anything.

## Status & summary

Record per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md):
beads-enhanced — progress is the issue states (claimed → closed) and the validation summary
on the epic; standalone — present a run summary in the session at the end.

## Dual-mode & resuming

- **Beads-enhanced (recommended):** loop state lives in beads, so the run is **resumable** —
  if you stop it, deny a permission, or hit an exception-stop, re-invoking autorun first
  reclaims any `in_progress` task (claimed but not closed) under the epic via the resume step
  in "The implement loop," then continues with the remaining `bd ready` tasks. Closed tasks
  stay closed.
- **Standalone:** the task list lives in the session, so resumability is best-effort — a fresh
  session re-derives the plan from the spec. Use `setup-beads` for any feature you might pause
  and resume.
