# Research: Workflow Orchestrator

**Date:** 2026-05-13
**Spec:** [1_spec.md](1_spec.md)

## Summary

Research was conducted through direct analysis of the existing agent and skill files rather than a separate research pass. All relevant files were read and their handoff logic inventoried before the plan was written.

## Files Examined

### Agents (all in `.claude/agents/`)

| File | Relevant findings |
|---|---|
| `define.md` | Step 7 contained full handoff: user approval dialogue, `context.yaml` update (`current_step: research`, `completed_steps: [define]`), Research agent invocation. Output section listed "approved by the user" as a completion condition. |
| `research.md` | Output section ended with: artifacts registry update, `context.yaml` step update, announcement, Plan agent invocation. |
| `plan.md` | Ended with: "Once complete, commit the plan. Then:" followed by `context.yaml` step update, announcement, Implement agent invocation. |
| `implement.md` | Had a `## Handoff` section (context.yaml update + Validate invocation). Escalation section told the agent to "notify the user and halt" inline. Also has internal Code Reviewer invocations — these are step-internal and untouched. |
| `validate.md` | Completion section ended with context.yaml update + "Validation complete. Starting Document step." + Document agent invocation. Escalation section told the agent to "notify the user and halt" inline. Has internal Senior Reviewer and QA Reviewer invocations — untouched. |
| `document.md` | Completion section had steps 2 and 3: context.yaml `current_step: complete` update + user notification with PR link. |

### Skills (all in `.claude/skills/`)

| File | Relevant findings |
|---|---|
| `feature/SKILL.md` | Simple entry point: checked for in-progress workflows, listed them, offered resume or new. For resume: mapped `current_step` to agent and invoked. For new: invoked Define agent only. No sequencing beyond Define. |
| `agent-context/SKILL.md` | Documents the `context.yaml` protocol. Handoff protocol (step 2–5 of "On handoff") told agents to update `current_step`, append to `completed_steps`, clear checkpoint, write file, then pass folder to next agent. No escalation fields existed. |
| `agent-context/template.yaml` | `workflow` block had: `current_step`, `completed_steps`, `checkpoint`. No `escalated` or `escalation_reason`. |

## Key Patterns Identified

**Handoff logic is identical across all agents:** each agent updated `context.yaml` (same two fields), printed an announcement, and invoked the next agent. This is a clear candidate for extraction.

**Internal vs pipeline orchestration:** Implement and Validate each do sub-orchestration (Code Reviewer, Senior/QA Reviewer). These are tightly coupled to their step logic and should stay in the agent.

**`context.yaml` is already the shared state mechanism:** every agent reads and writes it. The orchestrator can use the same file for step transitions without adding a new mechanism.

**Escalation was inline:** both Implement and Validate told the agent to surface issues to the user directly. Moving this to a context.yaml write + return keeps agents stateless with respect to the pipeline.

**`feature.folder` is the single coupling point:** all agents receive it as their argument and read `context.yaml` from it. The orchestrator passes it through unchanged.

## Constraints Confirmed

- The `/feature` invocation interface must not change — users invoke it the same way.
- `context.yaml` checkpoint writes (Implement) must stay in the agent — the orchestrator does not manage intra-step state.
- No new files needed outside `.claude/skills/feature/SKILL.md` and the existing agent files.
