# Spec: Context compaction handoff

**Date:** 2026-05-27
**Status:** Draft

## Summary

Add a context-compaction step to the feature workflow so that long-running pipelines do not exhaust the orchestrator's context window. Each pipeline agent (Define, Research, Plan, Implement, Validate, Document) writes a brief outcome-focused prose summary (~300–500 tokens) to `workflow.summary` in `context.yaml` immediately before returning. The `/feature` orchestrator then invokes `/compact` as part of its post-return protocol so its own conversation history stays slim across step transitions. The summary that the agent leaves behind is consumed by the next agent when it reads `context.yaml` at the start of its step — it does not replace the step doc itself (the next agent reads that fresh), it only conveys outcome, decisions, gotchas, and constraints.

## Problem Statement

The `/feature` workflow runs six agents in sequence. Each agent loads `context.yaml`, the prior step docs, and any artifacts it needs, then does its own work. By the time the orchestrator reaches the Validate or Document step, its own conversation history contains every step's announce-and-handoff round-trip plus whatever it read in between. On larger features this saturates the orchestrator's context window and degrades its ability to manage the remaining pipeline (post-return protocol bookkeeping, approval gates, escalation handling, the final PR URL announcement). Downstream agents also have no concise narrative of what came before — they must either re-read every prior step doc in full or work without context on the decisions and constraints that shaped them.

## Goals

- The orchestrator's context window stays manageable through every step of a multi-step feature, regardless of feature size.
- Each downstream agent receives a concise, outcome-focused narrative of what the prior step accomplished, the key decisions it made, and any gotchas to respect — without having to re-read the prior step doc in full to extract that signal.
- The summary mechanism is uniform across all six agents — same field, same shape, same token budget, same lifecycle.

## Non-Goals

- This spec does not replace the existing step documents (`1_spec.md`, `2_research.md`, `3_plan.md`, `4_validate.md`). Those remain the authoritative record of each step.
- This spec does not change the existing `workflow.checkpoint` field, which exists for resumability within a step rather than handoff between steps.
- This spec does not introduce a separate "summarize" agent or step. Each agent writes its own summary inline before returning.
- This spec does not change when, how often, or how the orchestrator commits and pushes `context.yaml` — the existing post-return protocol commit/push cadence is unchanged.
- This spec does not modify the spec approval gate, the escalation flow, or any other orchestrator behavior beyond adding the `/compact` invocation.

## User Stories

- As the `/feature` orchestrator, I want to invoke `/compact` after each agent returns so that my own context stays slim through a long pipeline run.
- As a downstream agent (e.g. Plan, Implement, Document), I want to read a short outcome-focused summary of the prior step in `context.yaml` so I get the decisions and constraints that shaped it without re-loading the full step doc just to find them.
- As a developer resuming a workflow on a different machine or after a session ends, I want `workflow.summary` to reflect the most recent completed step so I can orient quickly from `context.yaml` alone.
- As a developer reviewing a feature branch, I want each step's commit to reflect that the summary was updated alongside the step doc, so the git history shows a consistent state at every boundary.

## Requirements

- `context.yaml` includes a `workflow.summary` field. The template at `.claude/skills/agent-context/template.yaml` declares the field with a default value of `""`.
- Each of the six pipeline agents (Define, Research, Plan, Implement, Validate, Document) overwrites `workflow.summary` with a fresh prose summary of its own step's outcome immediately before returning to the orchestrator. Each agent's "After the workflow completes" / "After all tasks complete" section in `.claude/agents/<agent>.md` includes this step explicitly.
- The summary is overwritten each step, not appended. Only the most recent completed step's summary lives in the field at any given time.
- The summary is prose (not bullet lists, not YAML, not structured data). Target length is 300–500 tokens.
- The summary covers, in order of importance: what the step accomplished, key decisions made and why if non-obvious, gotchas and constraints the next agent must respect. It does not recap the contents of the step doc — the next agent reads that fresh.
- The summary is written into the same commit as the step doc and `context.yaml`. No separate commit for the summary alone.
- The `/feature` orchestrator's post-return protocol (in `.claude/skills/feature/SKILL.md`) invokes `/compact` after each agent returns and after the orchestrator has updated and committed `context.yaml`. `/compact` runs unconditionally after every step transition — including after Define on spec approval — except when the orchestrator is halting due to an escalation.
- When an agent escalates (`workflow.escalated: true`), it may write `workflow.summary` with the partial-progress narrative, but the orchestrator does **not** run `/compact` on an escalation halt — it surfaces the escalation and stops, leaving the conversation intact for the user to inspect.
- The `agent-context` skill's `SKILL.md` documents the `workflow.summary` field: its purpose, shape, token budget, lifecycle (overwrite per step), and who writes it.
- Downstream agents read `workflow.summary` when they read `context.yaml` at the start of their step. The agent's gate section notes that the field, when non-empty, describes the immediately preceding step.

## Constraints

- The summary lives in `workflow.summary` as a YAML string. Multi-line content must use YAML block scalar syntax (`|` or `>`) so existing YAML tooling parses it cleanly.
- The token budget (~300–500 tokens) is a guideline, not a hard limit enforceable by tooling. Agents are instructed to aim within that range; nothing rejects an over-budget summary.
- `/compact` is a built-in Claude Code command; the orchestrator invokes it by name in its post-return protocol. The orchestrator does not implement compaction itself.
- This change touches six agent files, one orchestrator skill, the `agent-context` skill doc, the `context.yaml` template, and the in-flight `context.yaml` for any active features. In-flight features without the field default to `""` and gain it on the first step boundary after the change lands.
- No change to commit cadence, push cadence, or escalation semantics. The summary write is folded into the existing per-step commit; the `/compact` call is folded into the existing post-return protocol.

## Acceptance Criteria

- [ ] `context.yaml` template at `.claude/skills/agent-context/template.yaml` includes a `workflow.summary` field with a default of `""` and an inline comment describing its purpose.
- [ ] All six agent files (`define.md`, `research.md`, `plan.md`, `implement.md`, `validate.md`, `document.md`) include an explicit instruction in their post-workflow section to overwrite `workflow.summary` with a fresh ~300–500 token outcome-focused prose summary before returning, covering: what was accomplished, key decisions, and gotchas/constraints for the next agent.
- [ ] Each agent's instructions clarify the summary is prose (not bulleted), is overwritten (not appended), and does not recap the step doc's contents.
- [ ] `.claude/skills/feature/SKILL.md`'s post-return protocol invokes `/compact` after committing and pushing `context.yaml`, on every step transition that is not an escalation halt.
- [ ] `.claude/skills/feature/SKILL.md` notes explicitly that `/compact` is not run when `workflow.escalated` is `true`.
- [ ] `.claude/skills/agent-context/SKILL.md` documents the `workflow.summary` field: purpose, shape (prose, 300–500 tokens), lifecycle (overwrite per step), who writes it (every pipeline agent before returning), and who reads it (the next agent on start, and the orchestrator for orientation).
- [ ] Each agent's gate section directs the agent to read `workflow.summary` from `context.yaml` and treat it (when non-empty) as the prior step's handoff narrative.
- [ ] A dry run of the workflow on a small feature shows that after each step transition: (a) `workflow.summary` reflects the just-completed step in the committed `context.yaml`, (b) `/compact` ran in the orchestrator's session, (c) the next agent's gate logs reading the summary.
- [ ] No existing field in `context.yaml` is renamed, removed, or changed in meaning. `checkpoint`, `escalated`, `escalation_reason`, `completed_steps`, and `current_step` retain their current semantics.

## Open Questions

- None. All design questions resolved during discovery: shape is outcome-focused prose, token budget is 300–500, each agent writes its own summary before returning, the orchestrator runs `/compact` in the post-return protocol, the summary is overwritten each step.
