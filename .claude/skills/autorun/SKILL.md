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

- **Preflight (required).** Verify beads is set up:
  `sh .claude/references/beads-preflight.sh`. If it exits non-zero, **stop** — do not
  proceed without beads — and tell the user to run the `setup-beads` skill, then retry.
- An **approved spec must be in context** (a beads epic from `define`). If there
  isn't one, stop and point the user at `define` — autorun does not replace gate 1.
- **Run from the main session.** autorun spawns the `implementer` agent, the `plan-review`
  agent, and the `senior-review`/`design-review`/`qa-review` agents, plus `efficiency-review`
  (per non-trivial task) and `security-scan` (per-task on `security-sensitive` tasks) —
  subagents can't spawn subagents.
- **Two human gates only:** Define (already done) and the **PR review** at the end.
  Everything between is autonomous reasoning + *supervised execution* (you approve permission
  prompts) + exception-stops. Keep permissions **on** — a recommended allowlist keeps the
  prompts manageable (see "Permissions").

## When NOT to use

- Trivial changes — just make them. autorun is for real features where the loop earns its keep.
- When you can't supervise. autorun keeps permissions on and pauses on prompts; it is not an
  unattended runner.

## The run

1. **Research** — read and follow [`research`](../research/SKILL.md) against the approved spec.
2. **Plan** — run `planning-and-task-breakdown`: file map + dependency-ordered tasks, each
   with a **risk marker** and **skill hints**, recorded as beads child issues under the epic.
3. **Plan review** — run the `plan-review` gate below (autonomous, not a human gate) before
   any code is written.
4. **Implement** — the loop below, one task at a time.
5. **Validate** — read and follow [`validate`](../validate/SKILL.md) (the always-run end-of-run review pass).
6. **Document** — read and follow [`document`](../document/SKILL.md): update docs, write the PR, `gh pr ready`. **Stop here.**

`research`, `validate`, and `document` are `disable-model-invocation` skills — autorun **cannot
fire them through the Skill tool** (the model can't invoke a `disable-model-invocation` skill, and
there is no skill-to-skill trigger). Compose each by **reading its `SKILL.md` and following it**
directly — including spawning the agents that skill directs — so its current content (e.g.
`validate`'s security backstop) always applies. `planning-and-task-breakdown` is model-invocable
and runs normally.

Advance only when the previous step's output is in hand. An exception-stop (see below) can
halt the run at any point and hand control back to the human.

## The plan-review gate

After Plan and **before** the implement loop, spawn the [`plan-review`](../../agents/plan-review.md)
agent (Agent tool) on the spec + plan — a staff-engineer design review of the approach,
decomposition, interfaces, reuse, risk, spec-alignment, and sequencing, before any code is
written. It reads the spec from the epic and the tasks / file map from its children via beads.
This is the pre-build mirror of `validate`:
**autonomous, not a third human gate.**

Triage the returned verdict:

- **Approved (or only trivial findings)** → proceed to the implement loop.
- **Actionable in-plan findings** (a missing task, a leaky interface, wrong sequencing) → **you
  revise the plan** — adjust the beads tasks / file map (you own the beads lifecycle) — and
  re-spawn `plan-review`. **Bounded to 3 iterations, same stop rule as Validate.**
- **A "wrong approach → back to Define" escalation, or unresolved substantive findings after 3
  iterations** → **exception-stop** (see below): halt and surface to the human. This is the
  existing safety-halt, **not** a new routine human gate — revising the plan can't fix a flawed
  premise, so the human decides.

The orchestrator owns the plan revisions; `plan-review` only reviews and reports (read-only on
code and on the plan).

## The implement loop

On (re)invoke, **reclaim stranded work first**: `bd ready` lists only
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

Hybrid by default, overridable at launch. Four reviewers, four triggers — each independent:

- **`efficiency-review` (default, every non-trivial task):** a cheap per-task pass for YAGNI,
  simplification, and unnecessary complexity. Runs on every task that touches more than a
  trivial config change; skipped only for XS/documentation-only tasks.
- **`senior-review` (per-task on `review-per-task` tasks):** triggered by the task's `Risk`
  marker — `review-per-task` for sensitive or high-blast-radius work (auth, payments,
  migrations, public API, crypto, concurrency). Tasks marked `end-of-run` are not reviewed
  individually — the always-run `validate` pass covers them.
- **`security-scan` agent (per-task on `security-sensitive` tasks):** triggered by the
  task's `security-sensitive` marker — **independent of and orthogonal to `Risk`**. A task
  marked `security-sensitive` gets a `security-scan` run per-task regardless of whether its
  Risk is `review-per-task` or `end-of-run`. A typical auth task carries both markers: both
  `senior-review` and `security-scan` run as separate passes.
- **`qa-review` (reserved for end-of-run `validate`):** not spawned per-task; the always-run
  `validate` pass at the end covers test quality and behavioral completeness.

Escalate any task to per-task senior-review on your own judgment too (e.g. the implementer
returned DONE_WITH_CONCERNS, or it touched more than its file-map slice).

- **Launch override:** honor a cadence instruction passed at launch over the default — e.g.
  *"review every task"*, *"only validate at the end"*, *"review tasks 3 and 7 individually"*.
  The end-of-run `validate` runs regardless.
- **How a per-task review runs:** reuse the `validate` loop shape on just that task's change —
  spawn the applicable reviewers (`efficiency-review` always; `senior-review` for risky;
  `security-scan` for security-sensitive; `design-review` for frontend-risky tasks that touch
  components/markup/styles), apply fixes, re-review, **bounded to 3 iterations**. Don't
  `bd close` the task until its review passes.

  Each reviewer is dispatched with the **task's pinned commit range** as the diff scope
  (per [`.claude/references/diff-scope.md`](../../references/diff-scope.md)): `base` = the
  commit before the implementer's first commit for this task, `head` = `git rev-parse HEAD`
  at spawn time. **Recompute the scope on each re-spawn** — fix commits move HEAD, so a
  scope pinned at the first spawn would miss them. The end-of-run `validate` pass computes
  its own branch scope (merge-base of HEAD and default branch); don't pass a per-task range
  there.

## Models (per-role knob)

Each subagent runs on the model best suited to its role, overridable at launch:

- **implementer** → a fast/capable model (the agent defaults to Sonnet).
- **plan-review** → Opus (its own frontmatter default) — the design gate wants the strong model.
- **reviewers** (`senior-review` → Opus, `design-review` → Opus, `qa-review` → Sonnet, `efficiency-review` → Sonnet, `security-scan` → Opus) → their own frontmatter defaults.

Override per spawn with the `Agent` tool's `model` parameter (resolution:
`CLAUDE_CODE_SUBAGENT_MODEL` env > per-call > agent frontmatter > session model). If the
user names models at launch, use those.

## Exception stops

An exception-stop is a **safety halt** that hands control back to the human mid-run — distinct
from the two gates. Stop and surface — don't grind or guess — when:

- `plan-review` returns a **"wrong approach → back to Define"** escalation, or its findings are
  still unresolved after the bounded revise-and-re-review cycles (3, same rule as `validate`),
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

Progress is the issue states (claimed → closed) and the validation summary on the epic — beads
is the system of record. See [`.claude/references/beads.md`](../../references/beads.md) for the full model.

## Resuming

Loop state lives in beads, so the run is **resumable** — if you stop it, deny a permission,
or hit an exception-stop, re-invoking autorun first reclaims any `in_progress` task (claimed
but not closed) under the epic via the resume step in "The implement loop," then continues
with the remaining `bd ready` tasks. Closed tasks stay closed.
