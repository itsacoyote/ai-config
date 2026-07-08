---
name: feature-workflow
description: Use when starting or resuming a feature, or when you want the map of the development workflow — the ordered Define → Research → Plan → Implement → Validate → Document steps and which skill or agent to use at each.
---

# Feature Workflow

The development workflow: **Define → Research → Plan → Implement → Validate → Document.** This skill is the map — it tells you the sequence and which skill/agent owns each step. Run each step deliberately by hand — or, after Define, hand the rest to `autorun` (see "Running it: by hand or with autorun" below).

This is portable on purpose — it travels with the skills when copied into another project, where the project's own `CLAUDE.md` will not.

## The steps

| # | Step | Skill / agent | Output |
|---|------|---------------|--------|
| 1 | **Define** | `define` skill (+ `documentation-and-adrs`) | An approved spec; ADRs for any significant decisions; the feature branch created |
| 2 | **Research** | `research` skill → spawns parallel lens agents (`research-reuse`, `research-patterns`, `research-risks`; conditional `research-libraries`, ask-first `research-history`) | Findings: reuse, gaps, patterns, risks, architectural context — synthesized |
| 3 | **Plan** | `planning-and-task-breakdown` skill | File map + dependency-ordered tasks with named tests |
| 4 | **Implement** | `incremental-implementation` skill (+ `writing-tests`; `efficiency-review` for per-chunk cheaply during implementation) | The change, built task by task, tests passing, committed |
| — | *Gate: Plan → Implement* | `plan-review` skill → `plan-review` agent | Plan reviewed before any code; design findings fixed (see below) |
| 5 | **Validate** | `validate` skill → spawns `senior-review` + `security-scan` + `design-review` (conditional, frontend) + `qa-review` agents | Reviews passed; findings fixed |
| 6 | **Document** | `document` skill (+ `create-pr`, `documentation-and-adrs`) | Docs updated, PR description written, PR readied |

## How to run it

1. **Define** — `define` walks the spec conversation, creates the branch, and ends at an approval checkpoint. Don't proceed until the spec is approved.
2. **Research** — `research` fans out to parallel read-only lens agents (reuse & gaps, patterns & architecture, risks) — plus conditional `research-libraries` and ask-first `research-history` — and synthesizes their reports into the findings against the approved spec.
3. **Plan** — `planning-and-task-breakdown` turns spec + research into a file map and ordered tasks.
   - **Gate (Plan → Implement):** before building, run `plan-review` — a staff-engineer design review of the spec + plan (approach, decomposition, interfaces, reuse, risk, spec-alignment, sequencing). It's the pre-build mirror of Validate's reviewers: it catches design flaws while they're a paragraph, not a diff. The skill spawns the `plan-review` agent in a fresh context; fix what it surfaces (a fundamentally wrong approach goes back to Define), then implement. In manual mode it's surfaced for you to act on; under `autorun` it runs automatically (revise-and-re-review, bounded to 3) and only interrupts you if the whole approach is wrong.
4. **Implement** — `incremental-implementation` builds the tasks in order, one increment at a time, with optional mid-implement review checkpoints for risky work. Use `efficiency-review` for cheap per-chunk reviews during implementation (reuse, simplification, efficiency cleanups) without waiting for the full Validate gate.
5. **Validate** — run `validate` from the main session; it spawns the reviewer agents (`senior-review`, `security-scan`, `design-review` when the change touches frontend, and `qa-review`) in isolated contexts and loops fixes until they pass.
6. **Document** — `document` audits every doc surface, writes the PR, and readies it.

Each step has a clear entry/exit; advance only when the previous step's output is in hand.

**Optional side-step — `prototype`.** When Define or Research stalls on a question that's cheaper to answer with throwaway code than discussion ("does this state model feel right?", "what should this look like?"), the `prototype` skill builds a disposable artifact to react to. Its *answer* feeds the spec or plan; the prototype itself is deleted.

**Situational on-ramp — `wayfinder`.** When an idea is too big and too foggy for even Define to get traction — the way to the destination isn't visible yet — the `wayfinder` skill charts it as a shared map of investigation tickets in beads, resolved one per session until the route is clear. Most maps end by handing one or more definable features to Define.

## Step handoff: recommend, then wait

In manual mode, **every step ends the same way** — this is the contract each step skill implements:

1. **Present the step's output** (the spec, the findings, the plan, the validation summary).
2. **Recommend the next move by name** — the default next step, plus any situational skill the output signals (table below). The user shouldn't have to remember which skills exist; the recommendation is the reminder.
3. **Stop and wait for explicit approval.** Do not begin the next step's work — no research reads, no task creation, no code — until the user says go. "No objection" is not approval; ask and wait.

| After | Default next | Recommend instead / first, when the output signals it |
|---|---|---|
| Define | `research` | Spec approved but *how it behaves or looks* is still fuzzy (novel/complex UI, unsettled state model) → `prototype` first, fold the answer back in. Idea still foggy despite the conversation → `wayfinder`. |
| Research | `planning-and-task-breakdown` | Findings surfaced a design question cheaper to answer in code than in the plan → `prototype` first. |
| Plan | `plan-review` (the mandatory gate) | — |
| Plan review passed | `incremental-implementation` | Fundamental approach concerns → back to Define. |
| Implement | `validate` | Risky chunk mid-implement → `efficiency-review` / `senior-review` checkpoint now rather than at the end. |
| Validate | `document` | Unresolved findings → fix or file them first. |
| Document | done — PR ready for human review | — |

Under `autorun` this per-step gate deliberately does **not** apply — autorun is the explicit opt-in to run Research → Document without stopping; Define and the PR stay the only human gates there.

## State and handoff

**Preflight (required).** Before doing any workflow work, verify beads is set up:
`sh ${CLAUDE_SKILL_DIR}/../../references/beads-preflight.sh`. If it exits non-zero, **stop** — do not
proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

State flows through **beads** (required) — see [`.claude/references/beads.md`](../../references/beads.md) for the full model. There is no `.docs/` folder and no `context.yaml`; beads is the system of record.

## Scope

Skip steps for trivial work — a one-line fix doesn't need the full pipeline. The workflow earns its keep on real features where a missed requirement or a skipped review is expensive. Match the rigor to the change.

## Running it: by hand or with autorun

Run the steps yourself, one at a time — the manual flow above. Or, after Define, hand the rest to **`autorun`**: a supervised orchestrator that runs Research → Document in one pass, implementing each task in a fresh `implementer` subagent, with permissions enforced (you approve actions as they happen) and stopping at a ready-for-review PR. **Two human gates either way — Define and the PR review.**

`autorun` is the in-session, permissions-on automation — *not* an unattended/headless runner; that remains future work. (The archived `/feature` skill automated this differently and is not active.)
