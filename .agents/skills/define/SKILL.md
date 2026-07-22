---
name: define
description: Use when starting a non-trivial feature whose scope, goals, constraints, behavior, or acceptance criteria need collaborative clarification before research or code.
metadata:
  category: workflow
---

# Define

The first step of the feature workflow (Define → Research → Plan → Implement → Validate → Document). Arrive at a clear, well-scoped spec through collaborative dialogue, then record it. If spec context is already in the conversation, build on it; otherwise start from the idea with the user.

## When NOT to use

A one-line, obvious change with no real ambiguity — just make it. Define earns its keep when scope, approach, or acceptance is unclear, or when the work is large enough that a wrong assumption is expensive. Even then, keep the conversation proportional: short for simple features, deeper for nuanced ones. Don't skip it to look fast; don't pad it to look thorough.

**Preflight (required).** Before doing any workflow work, verify beads is set up: resolve
`../../scripts/beads-preflight.sh` relative to this skill's directory and execute the resolved
absolute path. If it exits non-zero, **stop** — do not proceed without beads — and tell the user
to run the `setup-beads` skill, then retry.

## Start: branch and context

1. **Create the feature branch** per the `branch-names` skill (`<type>/<short-slug>`), from an up-to-date default branch:
   ```bash
   git switch main && git pull && git switch -c <type>/<short-slug>
   ```
2. **Explore context first** — read relevant files, docs, and recent commits to understand the current state before asking questions.
3. **Check scope** — if the idea spans multiple independent subsystems (e.g. "a platform with chat, billing, and analytics"), flag it and help decompose into separate features before continuing. A spec should fit a single implementation cycle. If the idea is not just big but **foggy** — the open questions can't even be phrased sharply yet, and decomposing in conversation isn't getting traction — hand off to the `wayfinder` skill to chart it as a map of investigation tickets; it returns definable features to Define later.

## The conversation

**Ask clarifying questions — one at a time.** Prefer multiple choice over open-ended; one question per message. Focus on purpose, constraints, success criteria, and non-goals.

**Explore approaches.** Propose 2–3 options with trade-offs; lead with your recommendation and say why. If the conversation stalls on how something should behave or look — a question that's cheaper to answer with throwaway code than more discussion — offer the `prototype` skill and fold its answer back into the spec. When a settled decision is architecturally significant or expensive to reverse — a framework/library choice, a data model, an auth strategy, an API style — capture it as an **ADR** while the alternatives and trade-offs are still fresh, following the `documentation-and-adrs` skill. Don't defer this to the Document step, where the rejected-alternative reasoning is usually lost.

**Present the design section by section.** Scale each section to its complexity. Cover architecture, components, data flow, error handling, and testing. Ask after each section whether it looks right. Be ready to go back and clarify.

**Design for isolation.** Break the system into units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently. For each: what does it do, how do you use it, what does it depend on?

**In existing codebases**, follow established patterns; include targeted fixes only where existing problems block the work — no unrelated refactoring.

**Principles:** YAGNI ruthlessly · explore alternatives before settling · validate incrementally · stay flexible.

## The spec

Once the design is agreed, capture it as a spec with these sections. Each must clear its quality bar before the spec is considered done:

- **Summary** — one paragraph; a reader with no context understands what this is and why it exists.
- **Problem statement** — concrete; who is affected and how (the actual pain, not "users want X").
- **Goals** — specific outcomes ("users can do X"), not activities.
- **Non-goals** — explicit; anything not listed here is assumed in scope.
- **User stories** — primary path plus at least one edge case. "As a [role], I want [action] so that [outcome]."
- **Requirements** — decided functional facts; no "should"/"maybe". Each is true or false after implementation.
- **Constraints** — real blockers (technical, time, third-party), not preferences.
- **Acceptance criteria** — testable; a reviewer can mark each done without asking what it meant.
- **Open questions** — only unresolved blockers; fold answered ones into the relevant section.

Avoid TBDs/TODOs/placeholders and contradictions between sections.

## Recording the spec

Create the feature **epic** with the spec as its body — beads is the system of record.
See [`beads.md`](../../references/beads.md) for the full model.

Do not write step-doc files — there is no `.docs/`.

**Record any ADRs.** Write each architecturally significant decision settled during the conversation to the project's ADR location (an existing `docs/decisions/`, `docs/adr/`, etc., or `docs/decisions/` if the project has none yet), using the template and lifecycle in `documentation-and-adrs`. Number them sequentially, set status `Accepted`, and link them from the spec so Research and Plan inherit the rationale. ADR files are the exception to "no step-doc files" — they are durable project records, not workflow scratch. If no decision rose to that bar, write nothing; don't manufacture an ADR for a trivial feature.

An ADR written here is a real file that must reach the repo. It won't be picked up by the task-scoped commits during Implement (no task owns it) and it's invisible to a `git diff` until committed, so **stage it now** (`git add` + commit it with the branch's first commit) rather than leaving it untracked — `document` sweeps for orphaned ADRs as a backstop, but don't rely on the backstop.

## Approval checkpoint

Before handing off to Research, present the **Summary** and **Acceptance Criteria** and ask the user to approve or give feedback. Revise and re-present until approved.

Once the spec is approved, **recommend the next move and wait for an explicit go** (the step-handoff contract in `feature-workflow`):

- **Default:** the `research` skill.
- **Recommend `prototype` first** when the spec settled *what* but left *how it behaves or looks* fuzzy — novel or complex UI, an unsettled state model, a data shape nobody can quite picture. Name the open question; the prototype's answer folds back into the spec before Research.
- **Recommend `autorun`** if the user wants the rest of the workflow (Research → Document) run autonomously under supervision.

Do not start Research (or anything else) until the user picks.
