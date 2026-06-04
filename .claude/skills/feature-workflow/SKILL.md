---
name: feature-workflow
description: Use when starting or resuming a feature, or when you want the map of the development workflow — the ordered Define → Research → Plan → Implement → Validate → Document steps and which skill or agent to use at each.
---

# Feature Workflow

The manual development workflow: **Define → Research → Plan → Implement → Validate → Document.** This skill is the map — it tells you the sequence and which skill/agent owns each step. It is guidance, not automation: you (or the model) run each step deliberately and decide when to advance.

This is portable on purpose — it travels with the skills when copied into another project, where the project's own `CLAUDE.md` will not.

## The steps

| # | Step | Skill / agent | Output |
|---|------|---------------|--------|
| 1 | **Define** | `define` skill | An approved spec; the feature branch created |
| 2 | **Research** | `research` skill (+ `analyze-code`, `find-patterns`, `web-search`) | Findings: reusable code, gaps, patterns, constraints |
| 3 | **Plan** | `planning-and-task-breakdown` skill | File map + dependency-ordered tasks with named tests |
| 4 | **Implement** | `incremental-implementation` skill (+ `writing-tests`) | The change, built task by task, tests passing, committed |
| 5 | **Validate** | `validate` skill → spawns `senior-review` + `qa-review` agents | Both reviews passed; findings fixed |
| 6 | **Document** | `document` skill (+ `create-pr`, `documentation-and-adrs`) | Docs updated, PR description written, PR readied |

## How to run it

1. **Define** — `define` walks the spec conversation, creates the branch, and ends at an approval checkpoint. Don't proceed until the spec is approved.
2. **Research** — `research` studies the codebase against the approved spec.
3. **Plan** — `planning-and-task-breakdown` turns spec + research into a file map and ordered tasks.
4. **Implement** — `incremental-implementation` builds the tasks in order, one increment at a time, with optional mid-implement review checkpoints for risky work.
5. **Validate** — run `validate` from the main session; it spawns the two reviewer agents in isolated contexts and loops fixes until both pass.
6. **Document** — `document` audits every doc surface, writes the PR, and readies it.

Each step has a clear entry/exit; advance only when the previous step's output is in hand.

## State and handoff

State flows through **beads** when it's set up, and conversationally when it isn't — every step skill follows the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md). There is no `.docs/` folder and no `context.yaml`; beads (or the conversation) is the system of record.

## Scope

Skip steps for trivial work — a one-line fix doesn't need the full pipeline. The workflow earns its keep on real features where a missed requirement or a skipped review is expensive. Match the rigor to the change.

## Not automated (yet)

There is intentionally no orchestrator running these end to end. Run the steps yourself, in order. (The archived `/feature` skill automated this; it was removed in favor of the manual flow.)
