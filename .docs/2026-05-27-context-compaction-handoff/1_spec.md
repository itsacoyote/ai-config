# Spec: Context compaction handoff

**Date:** 2026-05-27
**Status:** Draft

## Summary

Add a context-compaction step to the feature workflow so that long-running pipelines do not exhaust the orchestrator's context window and so that each downstream agent can start from a concise narrative instead of re-loading every prior step's full artifacts. Each pipeline agent (Define, Research, Plan, Implement, Validate, Document) writes a self-contained outcome-focused prose summary (~300–500 tokens) to `workflow.summary` in `context.yaml` immediately before returning. The summary is rich enough to stand in for re-reading prior step docs: it covers what the step accomplished, the key findings and decisions, and the relevant context the next agent needs to do its work. The `/feature` orchestrator then invokes `/compact` as part of its post-return protocol so its own conversation history stays slim across step transitions. Together, the agent-authored summary and the orchestrator-run `/compact` enable progressive context loading — the next agent reads `workflow.summary` as its primary handoff narrative and only opens prior step docs or artifacts when it needs specific detail beyond what the summary already conveys.

## Problem Statement

The `/feature` workflow runs six agents in sequence. Today each downstream agent re-reads the prior step docs and artifacts in full to extract the decisions, findings, and constraints that shaped them — even though most of that detail is irrelevant to its own step. At the same time, the orchestrator's conversation history accumulates every step's announce-and-handoff round-trip plus whatever it read in between. On larger features both pressures saturate context: downstream agents waste their window re-loading prior artifacts to mine a few sentences of signal, and the orchestrator loses headroom to manage the remaining pipeline (post-return protocol bookkeeping, approval gates, escalation handling, the final PR URL announcement). There is no concise narrative that an agent can read at the start of its step to orient itself without that re-load cost.

## Goals

- The orchestrator's context window stays manageable through every step of a multi-step feature, regardless of feature size.
- Each downstream agent can start its step by reading a single concise narrative — `workflow.summary` — that conveys what the prior step accomplished, the key findings and decisions, and the relevant context for its own phase, without needing to open the prior step's full docs or artifacts.
- Progressive context loading: the summary is the primary handoff. The next agent only reads full prior-step docs or artifacts on demand when it needs specific detail that the summary deliberately does not carry.
- The summary mechanism is uniform across all six agents — same field, same shape, same token budget, same lifecycle.

## Non-Goals

- This spec does not delete or stop producing the existing step documents (`1_spec.md`, `2_research.md`, `3_plan.md`, `4_validate.md`). They remain the authoritative record of each step and remain available for on-demand reads when the summary is insufficient.
- This spec does not change the existing `workflow.checkpoint` field, which exists for resumability within a step rather than handoff between steps.
- This spec does not introduce a separate "summarize" agent or step. Each agent writes its own summary inline before returning.
- This spec does not change when, how often, or how the orchestrator commits and pushes `context.yaml` — the existing post-return protocol commit/push cadence is unchanged.
- This spec does not modify the spec approval gate, the escalation flow, or any other orchestrator behavior beyond adding the `/compact` invocation.

## User Stories

- As the `/feature` orchestrator, I want to invoke `/compact` after each agent returns so that my own context stays slim through a long pipeline run.
- As a downstream agent (e.g. Plan, Implement, Document), I want to read `workflow.summary` at the start of my step and have enough context — what was accomplished, key findings and decisions, what matters for my phase — that I can begin work without first re-loading every prior step doc and artifact.
- As a downstream agent, I want the summary to be self-contained so that on-demand reads of prior step docs are the exception, not the default — they happen only when I need a specific detail the summary deliberately does not carry.
- As a developer resuming a workflow on a different machine or after a session ends, I want `workflow.summary` to reflect the most recent completed step so I can orient quickly from `context.yaml` alone.
- As a developer reviewing a feature branch, I want each step's commit to reflect that the summary was updated alongside the step doc, so the git history shows a consistent state at every boundary.

## Requirements

- `context.yaml` includes a `workflow.summary` field. The template at `.claude/skills/agent-context/template.yaml` declares the field with a default value of `""`.
- Each of the six pipeline agents (Define, Research, Plan, Implement, Validate, Document) overwrites `workflow.summary` with a fresh prose summary of its own step's outcome immediately before returning to the orchestrator. Each agent's "After the workflow completes" / "After all tasks complete" section in `.claude/agents/<agent>.md` includes this step explicitly.
- The summary is overwritten each step, not appended. Only the most recent completed step's summary lives in the field at any given time.
- The summary is prose (not bullet lists, not YAML, not structured data). Target length is 300–500 tokens.
- The summary covers, in order of importance: (1) what the step accomplished, (2) key findings and decisions made during the step (including why, when non-obvious), and (3) the relevant context the next agent needs for its phase — gotchas, constraints, scope boundaries, and anything that shaped the output but isn't self-evident from the artifacts themselves.
- The summary is written to be self-contained: the next agent should be able to start work from `workflow.summary` alone in the common case. Prior step docs and artifacts remain available for on-demand reads when a specific detail is needed beyond what the summary carries, but they are not the default starting point.
- The summary is written into the same commit as the step doc and `context.yaml`. No separate commit for the summary alone.
- The `/feature` orchestrator's post-return protocol (in `.claude/skills/feature/SKILL.md`) invokes `/compact` after each agent returns and after the orchestrator has updated and committed `context.yaml`. `/compact` runs unconditionally after every step transition — including after Define on spec approval — except when the orchestrator is halting due to an escalation.
- When an agent escalates (`workflow.escalated: true`), it may write `workflow.summary` with the partial-progress narrative, but the orchestrator does **not** run `/compact` on an escalation halt — it surfaces the escalation and stops, leaving the conversation intact for the user to inspect.
- The `agent-context` skill's `SKILL.md` documents the `workflow.summary` field: its purpose as the primary handoff narrative for progressive context loading, its shape, token budget, lifecycle (overwrite per step), and who writes it.
- Each downstream agent's gate section directs the agent to read `workflow.summary` from `context.yaml` at the start of its step and treat it as the primary handoff narrative — the first source of context for what came before, with prior step docs and artifacts read only on demand when the summary is insufficient.

## Constraints

- The summary lives in `workflow.summary` as a YAML string. Multi-line content must use YAML block scalar syntax (`|` or `>`) so existing YAML tooling parses it cleanly.
- The token budget (~300–500 tokens) is a guideline, not a hard limit enforceable by tooling. Agents are instructed to aim within that range; nothing rejects an over-budget summary. The budget is tight enough to force concision but loose enough to carry the three required content areas (accomplished / findings & decisions / relevant context).
- `/compact` is a built-in Claude Code command; the orchestrator invokes it by name in its post-return protocol. The orchestrator does not implement compaction itself.
- This change touches six agent files, one orchestrator skill, the `agent-context` skill doc, the `context.yaml` template, and the in-flight `context.yaml` for any active features. In-flight features without the field default to `""` and gain it on the first step boundary after the change lands.
- Progressive context loading is a behavior the spec instructs, not a mechanism the tooling enforces. An agent is free to open a prior step doc if it needs detail beyond the summary; the goal is to make that the exception rather than the default.
- No change to commit cadence, push cadence, or escalation semantics. The summary write is folded into the existing per-step commit; the `/compact` call is folded into the existing post-return protocol.

## Acceptance Criteria

- [ ] `context.yaml` template at `.claude/skills/agent-context/template.yaml` includes a `workflow.summary` field with a default of `""` and an inline comment describing its purpose as the primary handoff narrative for progressive context loading.
- [ ] All six agent files (`define.md`, `research.md`, `plan.md`, `implement.md`, `validate.md`, `document.md`) include an explicit instruction in their post-workflow section to overwrite `workflow.summary` with a fresh ~300–500 token outcome-focused prose summary before returning, covering: (1) what was accomplished, (2) key findings and decisions, and (3) relevant context for the next phase.
- [ ] Each agent's instructions clarify the summary is prose (not bulleted), is overwritten (not appended), and is written to be self-contained so the next agent can start from the summary alone in the common case.
- [ ] Each downstream agent's gate section directs the agent to read `workflow.summary` first as the primary handoff narrative, and notes that prior step docs and artifacts are read on demand only when a specific detail is needed beyond what the summary carries.
- [ ] `.claude/skills/feature/SKILL.md`'s post-return protocol invokes `/compact` after committing and pushing `context.yaml`, on every step transition that is not an escalation halt.
- [ ] `.claude/skills/feature/SKILL.md` notes explicitly that `/compact` is not run when `workflow.escalated` is `true`.
- [ ] `.claude/skills/agent-context/SKILL.md` documents the `workflow.summary` field: its purpose (primary handoff narrative enabling progressive context loading), shape (prose, 300–500 tokens), three required content areas (accomplished / findings & decisions / relevant context for next phase), lifecycle (overwrite per step), who writes it (every pipeline agent before returning), and who reads it (the next agent on start as its primary context source, and the orchestrator for orientation).
- [ ] A dry run of the workflow on a small feature shows that after each step transition: (a) `workflow.summary` reflects the just-completed step in the committed `context.yaml` and covers the three required content areas, (b) `/compact` ran in the orchestrator's session, (c) the next agent's gate logs reading the summary as its primary handoff context.
- [ ] No existing field in `context.yaml` is renamed, removed, or changed in meaning. `checkpoint`, `escalated`, `escalation_reason`, `completed_steps`, and `current_step` retain their current semantics.

## Open Questions

- None. All design questions resolved during discovery and follow-up: shape is outcome-focused prose covering accomplished / findings & decisions / relevant context for next phase, token budget is 300–500, each agent writes its own summary before returning, the orchestrator runs `/compact` in the post-return protocol, the summary is overwritten each step, and the summary is the primary handoff source enabling progressive context loading (prior step docs read on demand only).
