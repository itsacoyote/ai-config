---
name: define
description: Use at the start of a feature to turn an idea into a clear, well-scoped spec through collaborative dialogue — scope, goals, constraints, and acceptance criteria — before any research or code.
disable-model-invocation: true
allowed-tools: Read Write Edit Bash(find *) Bash(git *)
---

# Define

The first step of the feature workflow (Define → Research → Plan → Implement → Validate → Document). Arrive at a clear, well-scoped spec through collaborative dialogue, then record it. If spec context is already in the conversation, build on it; otherwise start from the idea with the user.

## When NOT to use

A one-line, obvious change with no real ambiguity — just make it. Define earns its keep when scope, approach, or acceptance is unclear, or when the work is large enough that a wrong assumption is expensive. Even then, keep the conversation proportional: short for simple features, deeper for nuanced ones. Don't skip it to look fast; don't pad it to look thorough.

## Start: branch and context

1. **Create the feature branch** per the `branch-names` skill (`<type>/<short-slug>`), from an up-to-date default branch:
   ```bash
   git switch main && git pull && git switch -c <type>/<short-slug>
   ```
2. **Explore context first** — read relevant files, docs, and recent commits to understand the current state before asking questions.
3. **Check scope** — if the idea spans multiple independent subsystems (e.g. "a platform with chat, billing, and analytics"), flag it and help decompose into separate features before continuing. A spec should fit a single implementation cycle.

## The conversation

**Ask clarifying questions — one at a time.** Prefer multiple choice over open-ended; one question per message. Focus on purpose, constraints, success criteria, and non-goals.

**Explore approaches.** Propose 2–3 options with trade-offs; lead with your recommendation and say why. When a settled decision is architecturally significant or expensive to reverse — a framework/library choice, a data model, an auth strategy, an API style — capture it as an **ADR** while the alternatives and trade-offs are still fresh, following the `documentation-and-adrs` skill. Don't defer this to the Document step, where the rejected-alternative reasoning is usually lost.

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

Follow the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md):

- **Standalone (default):** present the finished spec in the conversation. It is the working record for Research and Plan.
- **Beads-enhanced:** create the feature **epic** with the spec as its body.

Do not write step-doc files — there is no `.docs/`.

**Record any ADRs.** Write each architecturally significant decision settled during the conversation to the project's ADR location (an existing `docs/decisions/`, `docs/adr/`, etc., or `docs/decisions/` if the project has none yet), using the template and lifecycle in `documentation-and-adrs`. Number them sequentially, set status `Accepted`, and link them from the spec so Research and Plan inherit the rationale. ADR files are the exception to "no step-doc files" — they are durable project records, not workflow scratch. If no decision rose to that bar, write nothing; don't manufacture an ADR for a trivial feature.

## Approval checkpoint

Before handing off to Research, present the **Summary** and **Acceptance Criteria** and ask the user to approve or give feedback. Revise and re-present until approved. Only after approval, move on — either continue by hand with the `research` skill, or hand the rest of the workflow to `autorun` to run Research → Document autonomously under supervision (see `feature-workflow`).
