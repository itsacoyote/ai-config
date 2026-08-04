# Subagent Status Protocol

Shared vocabulary a **work subagent** (e.g. the `implementer` agent) returns to the
**orchestrator** that spawned it (the main session, e.g. `autorun`). Subagents cannot use
the `Agent` or `AskUserQuestion` tools — they can't spawn helpers and can't ask the human
anything. So a subagent **never hangs and never asks**: it finishes its turn with one of the
statuses below, and the orchestrator (the only party that talks to the human) decides what
happens next.

This is the protocol for *work* subagents. Reviewer subagents keep their own verdicts —
`senior-review` returns *approved / findings*, `qa-review` returns *Approved / Gaps /
Blocked* — see those skills. The orchestrator maps all of them to the same response logic.

## The statuses

| Status | Meaning | Orchestrator response |
|---|---|---|
| **DONE** | Work complete; tests/checks pass; committed (if the task produces commits). | Proceed — run review per cadence, then advance to the next task. |
| **DONE_WITH_CONCERNS** | Complete, but the subagent flags something — a smell, a risk, a deviation from the plan, work it noticed but didn't do. | Read the concerns. If correctness-related, address before advancing. If observational, note it (file a follow-up issue) and continue. |
| **NEEDS_CONTEXT** | Cannot finish without information the orchestrator can supply — a decision, a missing interface, an ambiguous spec point. | Provide the missing context and **re-dispatch the same task** (counts against the bounded-retry budget). |
| **BLOCKED** | Cannot proceed, and re-dispatching as-is won't help — flawed plan, oversized task, environmental failure, or an unpassable permission denial. | Diagnose the root cause (context gap / oversized / flawed plan / environment), then respond: split the task, fix the plan, or **HALT and surface to the human**. Never force a blind retry. |

## Return shape

End the subagent's turn with an explicit status line plus the specifics, e.g.:

```
STATUS: DONE
Summary: implemented <task>; tests <named tests> pass; committed as <type>(scope): ...

STATUS: BLOCKED
Reason: the plan's file map references a module that doesn't exist; cannot satisfy the
acceptance criteria without a design decision. Tried: <what>. Need: <what>.
```

## Guardrails

- **Subagents always return a status — never hang, never ask the human.** The orchestrator
  owns every human touchpoint (permission approvals, the Define/PR gates, exception-stops).
- **Bounded retries.** `NEEDS_CONTEXT` re-dispatches and fix loops are bounded — align with
  the cap in the `validate` skill (3 iterations). After the bound, treat it as `BLOCKED` and
  escalate to the human rather than looping again.
- **A subagent that can't decide picks `BLOCKED` and explains** — surfacing uncertainty is
  cheaper than guessing wrong.
