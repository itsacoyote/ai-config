# Spec: Workflow Orchestrator

**Date:** 2026-05-13  
**Status:** Draft

## Summary

Centralize pipeline coordination into a single workflow orchestrator skill, replacing the current model where each agent is responsible for invoking the next. Today, handoff logic (transition announcements, context.yaml step updates, next-agent invocations) is duplicated across five agents, making the pipeline difficult to understand or modify. The new orchestrator skill owns the full sequence — agents become pure domain workers that do their job and return.

## Problem Statement

The development pipeline (Define → Research → Plan → Implement → Validate → Document) is currently self-coordinating: each agent invokes the next one. This means the pipeline logic is scattered across five agent files. Adding a step, reordering steps, or changing transition behavior requires editing multiple agents. There is also no single place to read to understand the full workflow sequence.

## Goals

- One skill owns the full pipeline sequence and all step transitions
- Agents have no knowledge of what comes before or after them
- Transition announcements ("Define complete. Starting Research...") live in the orchestrator
- The spec approval gate (user must approve before Research starts) lives in the orchestrator
- Escalation handling lives in the orchestrator
- Resume logic (currently in `/feature`) is preserved in the orchestrator
- The `/feature` invocation continues to work unchanged for users

## Non-Goals

- Changing any agent's core domain logic
- Changing the pipeline sequence or adding/removing steps
- Changing the `context.yaml` schema beyond adding `workflow.escalated` and `workflow.escalation_reason`
- Parallelizing any pipeline steps

## User Stories

- As a developer, I want to invoke `/feature` and have the workflow run end-to-end without manually invoking each agent, so I can focus on reviewing approvals rather than managing the pipeline.
- As a developer, I want to see clear transition announcements between steps so I know exactly where the pipeline is at all times.
- As a maintainer, I want to modify the pipeline sequence by editing one skill file, so changes are low-risk and easy to reason about.

## Requirements

- The `feature` skill is rewritten as the pipeline orchestrator. Its invocation interface (`/feature [idea]`) is unchanged.
- The orchestrator runs the pipeline in sequence: Define → Research → Plan → Implement → Validate → Document.
- After each step completes, the orchestrator updates `context.yaml` (`current_step`, `completed_steps`) before invoking the next agent.
- After Define completes, the orchestrator pauses, presents a spec summary, and asks the user to approve before continuing to Research. On rejection, the orchestrator re-invokes Define with the user's feedback.
- If an agent sets `workflow.escalated: true` in `context.yaml`, the orchestrator halts and surfaces `workflow.escalation_reason` to the user.
- After Document completes, the orchestrator announces completion and surfaces the PR link.
- Resume logic: on invocation, the orchestrator scans for in-progress `context.yaml` files and offers to resume or start new. Resuming jumps directly to the `current_step` agent.
- The `feature` skill file is replaced in-place (same path: `.claude/skills/feature/SKILL.md`).

### Agent changes

Each agent listed below loses the specified sections. No other agent logic changes.

| Agent | What is removed |
|---|---|
| Define | User approval dialogue; Research invocation; context.yaml `current_step`/`completed_steps` update |
| Research | Plan agent invocation; context.yaml step update |
| Plan | Implement agent invocation; context.yaml step update |
| Implement | Validate agent invocation; context.yaml step update at completion. Escalation: write `workflow.escalated: true` + `workflow.escalation_reason` to context.yaml instead of halting inline |
| Validate | Document agent invocation; context.yaml step update at completion. Same escalation signaling as Implement |
| Document | workflow-complete notification; context.yaml `current_step: complete` update |

### context.yaml changes

Two new fields added to the `workflow` block, and the `template.yaml` updated accordingly:

```yaml
workflow:
  escalated: false        # Set to true by an agent when it cannot continue
  escalation_reason: ""   # Human-readable description of the escalation
```

The `agent-context` skill doc is updated to describe these fields and when agents should write them.

## Constraints

- The `/feature` invocation interface must not change — users invoke it the same way as today.
- Implement's mid-step checkpoint writes (`workflow.checkpoint`) stay in the Implement agent — the orchestrator does not manage intra-step state.
- Internal sub-orchestration within agents (Code Reviewer invocations from Implement, Senior/QA Reviewer loops in Validate) stays in those agents.

## Acceptance Criteria

- [ ] `/feature <idea>` kicks off the full pipeline end-to-end without the user manually invoking any agent
- [ ] A clear transition announcement is printed between every step
- [ ] After Define, the orchestrator presents the spec and asks for approval before proceeding
- [ ] Rejecting the spec re-invokes Define with the provided feedback
- [ ] If Implement or Validate escalates, the pipeline halts and the reason is shown to the user
- [ ] `/feature` with an existing in-progress workflow offers resume or new
- [ ] Resuming an in-progress workflow starts at the correct step without re-running completed steps
- [ ] No agent invokes another agent (verified by reading each agent file)
- [ ] No agent updates `current_step` or `completed_steps` in context.yaml (verified by reading each agent file)
- [ ] `context.yaml` template includes `workflow.escalated` and `workflow.escalation_reason`
- [ ] `agent-context` skill documents the new escalation fields

## Open Questions

- None. Design fully resolved.
