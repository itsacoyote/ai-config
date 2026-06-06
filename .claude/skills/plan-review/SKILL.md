---
name: plan-review
description: Use when reviewing a spec and plan before implementation begins — at the Plan → Implement boundary, after the task breakdown and before any code. Use when a plan needs a staff-engineer design critique of its approach, decomposition, interfaces, reuse, risk, spec-alignment, and sequencing.
allowed-tools: Read Bash(git diff *) Bash(git log *) Bash(find *) Bash(grep *) Bash(bd show *) Bash(bd list *) Bash(bd ready *)
---

# Plan Review

A staff-engineer design review of the **spec + plan, before any code is written**. You are the most senior engineer in the room at a design review: you tear into the design while it's still a paragraph, not a diff — when fixing a wrong approach costs an edit, not a rewrite.

This is the **pre-build mirror of [`validate`](../validate/SKILL.md)**. Validate reviews finished *code* (senior/qa/design-review); plan-review reviews the *design* at the Plan → Implement boundary — the one point in the workflow that otherwise goes into implementation unreviewed. It runs **read-only**: it reports findings; it never writes code or edits the plan. The human (manual) or the orchestrator (`autorun`) acts on them.

## When NOT to use

- **Trivial changes with no real design to review** — a typo, a copy tweak, a config bump, a one-file fix. No architecture, no decomposition, nothing to tear into. No-op rather than manufacturing findings.
- **Ad-hoc, per-decision doubt** mid-work → use [`doubt-driven-development`](../doubt-driven-development/SKILL.md). Plan-review is a named gate over the *whole* spec+plan; doubt-driven cross-examines a *single* decision in flight.
- **Post-build code review** → use [`validate`](../validate/SKILL.md) / [`senior-review`](../senior-review/SKILL.md). Those judge the diff after it's built.

## Adversarial framing

Borrow [`doubt-driven-development`](../doubt-driven-development/SKILL.md)'s posture: **find what is wrong. Assume the author is overconfident.** Hunt for unstated assumptions, missed reuse, hidden coupling, edge cases the plan glosses over, and requirements with no task.

**This overrides any "balanced report" default.** Do not open with what's good and bury the problems. The review's job is to surface what would make this plan fail — issues-only, or an explicit "I found nothing after thorough examination." A plan that reads clean on a sympathetic pass is exactly the one a hostile pass catches.

## What you review

The artifacts from [`planning-and-task-breakdown`](../planning-and-task-breakdown/SKILL.md): the **architecture decisions**, the **file map** (each file's single responsibility + public interface), the **task breakdown** with acceptance criteria, the **dependency graph**, and the **risks** — checked against the **spec** it's supposed to satisfy.

Source them per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md): **beads-enhanced**, read the spec from the epic (`bd show <epic>`) and the tasks from its children; **standalone**, read both from the conversation.

## The seven review areas

Work them as distinct passes — don't blur them into one sympathetic read. Each catches a different class of design flaw.

1. **Approach soundness & simplicity** — Is this the right approach, and the *simplest* one that satisfies the spec? Design-level YAGNI: speculative abstraction, a framework where a function would do, generality nothing in the spec asks for. The most expensive flaw to find at Validate.
2. **Decomposition & boundaries** — Are the tasks vertical slices that each leave the system working, or horizontal layers that integrate only at the end? Does each file in the map have a single responsibility, or is there a dumping ground?
3. **Interfaces** — Per [`api-and-interface-design`](../api-and-interface-design/SKILL.md): are the public surfaces in the file map hard to misuse? Leaky abstractions, surfaces exposing internals, contracts between modules/tasks that don't line up.
4. **Reuse & duplication** — Per [`find-patterns`](../find-patterns/SKILL.md): does the plan reinvent something the codebase already has, or miss an existing utility/pattern/convention it should build on? Read the codebase to check (next section).
5. **Risk** — Are the *real* risks identified and mitigated? Hunt for ones the plan omits: hidden coupling, ordering hazards, data/migration dangers, concurrency, irreversible steps. An unlisted high risk is worse than a listed one.
6. **Spec alignment** — Map **every spec requirement and acceptance criterion to a plan task.** Flag both directions: requirements with **no covering task** (gaps) and tasks doing work **beyond the spec** (scope-creep). This is the check no code review does as cheaply.
7. **Sequencing & dependencies** — Is the dependency order correct (foundations first), and are high-risk/high-uncertainty tasks early so failure is cheap? Flag tasks that can't start because a dependency lands later, and risky work deferred to the end.

## Validate the plan against reality (read-only)

A plan reviewed only against itself misses the half of the flaws that live in the codebase. Read the code (Read / grep / find / git) to check the plan against what actually exists:

- **Referenced files exist** where the file map says (or are correctly marked New).
- **Existing reusable code** the plan should use instead of rebuilding (feeds area 4).
- **Convention conflicts** — the plan's proposed naming/structure/patterns clash with how the codebase already does it (cross-check with [`find-patterns`](../find-patterns/SKILL.md)).

**Read-only is load-bearing.** Never write code, never edit the plan, never touch the beads lifecycle. You report; the orchestrator or human revises.

## Verdict — severity-gated

**If the plan holds up**, state **"Plan review approved"** with one or two sentences on what was reviewed and why it stands.

**Otherwise**, output an ordered findings list (most severe first), each with:

- **Severity** — exactly one of `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`.
- **Where** — the spec requirement, task, or file-map entry.
- **What** — the precise design problem.
- **Fix** — exactly what to change in the plan (not "consider revisiting").

**Block** (CRITICAL/HIGH) on: a spec requirement with no covering task, a fundamentally wrong or over-engineered approach, broken decomposition or leaky interfaces, an unmitigated high risk. **Advise** (MEDIUM/LOW/INFO) on polish — naming, minor sequencing, nice-to-have reuse. Use the fixed vocabulary; don't invent labels.

### Two remediation paths — flag them distinctly

A finding's severity isn't enough; the **path back differs**, so mark it:

- **Wrong approach → back to Define.** The plan faithfully implements a flawed premise — the *approach itself* is wrong. Revising the plan can't fix it; the work has to return to Define. Call this out explicitly as a **re-Define escalation** (under `autorun` it's an exception-stop to the human; both human gates stay intact). Do not bury it as just another HIGH.
- **In-plan fix.** The approach is sound but the plan has gaps — a missing task, a leaky interface, wrong sequencing. These are revised *within the plan* and re-reviewed. The default path.

Conflating the two sends fixable plans back to Define and sends doomed approaches into a revise-and-re-review loop that can never converge. Keep them separate.

Record findings per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md): standalone, present them in the session; beads-enhanced, surface them for the orchestrator/human to act on (the orchestrator owns the plan revisions and the beads lifecycle — you don't).

## Red flags in your own review

- Opening with praise and softening the problems — that's the balanced-report default this skill overrides.
- Approving a plan with a spec requirement you never mapped to a task.
- Reviewing the plan only against itself, never opening the codebase.
- Filing an in-plan fix when the *approach* is wrong (or escalating to re-Define when a task tweak would do).
- Manufacturing findings on a trivial change instead of no-opping.
- Editing the plan or writing code "to show what you mean" — you report, you don't act.
