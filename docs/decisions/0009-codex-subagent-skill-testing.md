# 9. Allow Codex skills to require subagent testing

Date: 2026-08-12

Status: Accepted

Supersedes in part: [ADR 0006](0006-per-harness-config-trees.md)

## Context

ADR 0006 required Codex ports to remove subagent references because Codex did not then have
an equivalent isolated-worker mechanism. That premise has changed: current Codex releases
support subagent workflows, and applicable `AGENTS.md` or skill instructions may request
delegation.

The `writing-skills` methodology depends on fresh-context comparisons. Testing an authored
skill in the same context that wrote it biases the result, while a baseline that inherits
the desired conclusion is not a meaningful baseline.

## Decision

Codex skills may require Codex subagents when isolated context is material to the method.
The `writing-skills` port keeps baseline and skill-enabled evaluation runs read-only
against the shared source worktree. An evaluation that must create artifacts uses an
isolated temporary workspace.

This does not restore source-harness agent wrappers or generated adapters. Each Codex skill
remains self-contained, names the capability rather than a private tool call, and provides a
clean-session fallback when subagents are unavailable.

## Consequences

- Codex skill authors can run genuine RED/GREEN comparisons without contaminating the main
  authoring context.
- Skills may request delegation, so their token and concurrency cost must be justified.
- Read-heavy isolated evaluations are preferred; parallel write-heavy work remains a poor
  fit for a shared worktree.
- ADR 0006's broader requirements still stand: ports are semantic rewrites, contain no
  source-harness mechanics, and are never synchronized automatically.

## Alternatives considered

- **Keep subagents forbidden.** Rejected because it preserves a capability assumption that
  is no longer true and weakens the authoring method.
- **Make subagent evaluation optional.** Rejected for behavioral skills because same-context
  self-review does not establish an unbiased baseline. A separate clean session remains the
  degraded fallback.
- **Port source agent wrappers.** Rejected because Codex provides native subagent workflows;
  wrappers would add coupling without improving isolation.
