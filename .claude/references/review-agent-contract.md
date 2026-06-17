# Review Agent Contract

Shared baseline that all six review agents (`security-scan`, `senior-review`,
`efficiency-review`, `qa-review`, `design-review`, `plan-review`) adhere to. Each agent's
file cites this reference and then states its own deviations inline — don't duplicate here
what's stated there.

## Posture

**Read-only on code.** Review agents do not fix, edit, commit, or push code unless their
individual file explicitly permits an exception. They review and report; the caller (or the
orchestrator) applies fixes and re-invokes.

## Do not fix / commit / push

Never apply patches, stage files, commit, or push — except where an agent's own file
explicitly grants a narrow exception (currently only `qa-review`, which may commit e2e fixes
but never pushes).

## Severity vocabulary

Use this fixed vocab, most severe first, in all findings lists:

`CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`

Present findings ordered by severity, blockers first.

## Status protocol

Each subagent that needs to close with a machine-readable status uses
[`subagent-status-protocol.md`](subagent-status-protocol.md) (`DONE` / `DONE_WITH_CONCERNS` /
`NEEDS_CONTEXT` / `BLOCKED`). Not every review agent closes with this status line — see each
agent's **Return** section.

## Beads

Record findings per the beads contract in [`beads.md`](beads.md) **only when the caller
asks**; by default just return them inline.

## Return shape is agent-specific

This contract does **not** define a shared return shape. Each agent's return format differs —
verdicts, field names, and structure are defined in that agent's own **Return** section. Do
not infer a uniform shape from this file.
