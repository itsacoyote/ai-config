# Isolated Worker Orchestration

Shared contract for workflow skills that need fresh-context research, review, verification, or implementation. Skills describe the role and outcome; each harness chooses its native execution mechanism.

## Core rules

- Keep methodology in Agent Skills and scope/return behavior in neutral role prompts.
- Use isolated workers when independence or context isolation materially improves the result, not as automatic ceremony.
- Parallelize only independent read-heavy work. Never run source-editing workers concurrently in one worktree.
- Pass bounded inputs: the beads epic/task id, a pinned diff scope, relevant paths, and the required return contract.
- Treat skill or role tool declarations as capability documentation, not a portable security boundary. Enforcement belongs to each harness or an external sandbox.
- The parent owns synthesis, human handoffs, beads lifecycle changes, and retry limits.

## Capability modes

| Mode | Intended work | Write policy |
|---|---|---|
| Read-only | Research and independent review | No source, artifact, git, or beads writes |
| Verification | Tests and evidence capture | Test/evidence artifacts only; no source edits |
| Implementation | One planned task or one validated fix request | Source edits allowed; exactly one worker at a time |

A verification role that finds a source defect returns its defined result or fix-request contract. The parent dispatches one implementation worker, then reruns verification. Review roles do not silently become implementers.

## Claude Code

Use the corresponding thin agent under `.claude/agents/`. Existing Claude settings and tool policies remain authoritative for Claude; the portable library does not replace them.

## Codex

Use the corresponding custom agent under `.codex/agents/`. Read-only roles should use Codex's read-only sandbox. A source-editing worker inherits the parent session's live sandbox and approval policy. Keep nesting depth at one unless a workflow explicitly proves deeper delegation is necessary.

## Pi

Prefer Pi's minimal process model rather than requiring a subagent extension:

- Run Research as a dedicated session, persist its synthesis to beads, and begin implementation in a fresh session.
- For independent review or verification, invoke a fresh `pi --print` process through bash using the generic library runner. That runner rejects implementation roles.
- For bounded implementation, use the sandbox-required launcher bundled with `autorun`; it holds the shared writer lease and invokes Pi only inside a verified external sandbox.
- The runner controls system prompts, role methodology, tools, trust, and session persistence explicitly; ambient project/global resources are excluded unless deliberately added.
- Default child sessions are ephemeral. Saved sessions are an explicit observability choice.
- Tmux is optional for interactive observation, steering, or long-running processes; it is not a library dependency.
- Pi tool allowlists do not make bash read-only. Use behavioral contracts and, when enforcement matters, an external container or sandbox.

Pi may run multiple independent read-only processes, but source-editing processes remain serialized.

## Failure and return behavior

Workers always return an explicit status or role-specific verdict. They do not wait indefinitely for human input. Missing context returns `NEEDS_CONTEXT`; inability to proceed returns `BLOCKED`; partial or risky completion returns `DONE_WITH_CONCERNS`. See `subagent-status-protocol.md` for the shared status vocabulary.
