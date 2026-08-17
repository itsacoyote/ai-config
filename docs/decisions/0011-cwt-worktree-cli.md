# 11. Add cwt as an independent Codex worktree CLI

Date: 2026-08-17

Status: Accepted

Related: [ADR 0005](0005-clwt-worktree-cli.md) and
[ADR 0006](0006-per-harness-config-trees.md)

Tracking: beads epic `ai-config-2qy`

## Context

`clwt` provides the repository's established worktree workflow for Claude Code. Codex
needs the same developer-facing commands and safety boundaries, but it has different
launch flags, configuration, and lifecycle behavior. ADR 0006 says harness-specific
implementations are copied at porting time and may diverge without synchronization.

Codex supports native `-C` / `--cd`, but that changes directory as an application option.
The worktree CLI also needs startup hooks and every child process to begin with the target
as their actual process working directory.

## Decision

- Add `codex/scripts/cwt` as an independent Bash implementation with its own completion
  and self-contained tests. It is a port, not a shared core or generated adapter.
- Preserve `clwt`'s ten-command interface and safety model while using Codex terminology,
  `CWT_REPO_ROOT`, and Codex's native `--yolo` flag.
- Keep the managed path at
  `~/github/.worktrees/<owner>/<repo>/<branch-with-slashes-as-dashes>/`. `clwt` and `cwt`
  intentionally see the same worktrees, even though each launches only its own harness.
- Launch with physical `cd` followed by `exec codex` instead of relying on native `-C`.
  This establishes the working directory before Codex, startup hooks, or child processes
  begin.
- Keep `cwt` developer-facing. Launching it inside Codex would create a nested session,
  not move the active one. There is no shared `agents/skills/cwt` wrapper.
- Target stock macOS Bash 3.2. Completion reads local Git state only and treats branch
  names as data rather than passing them through shell word expansion.

## Consequences

### Positive

- Codex gets the complete, tested worktree workflow without depending on Claude files.
- Both harness CLIs interoperate with the same managed worktrees.
- The launched Codex process and its descendants have the correct working directory by
  construction.
- Harness-specific behavior can evolve without a parity or synchronization obligation.

### Negative / trade-offs

- Fixes do not automatically propagate between `clwt` and `cwt`; maintainers decide when
  a behavior should be ported.
- The independent scripts duplicate substantial Bash logic.
- `cwt` must be run by the developer for launching commands; an active Codex session
  cannot relocate itself.

## Alternatives considered

- **Share a core implementation with thin launch adapters.** Rejected because it couples
  harness-specific behavior and recreates the synchronization pressure ADR 0006 removed.
- **Invoke `clwt` and replace only the final executable.** Rejected because the command's
  flags, environment contract, help, completion, tests, and security review must all be
  Codex-specific.
- **Use `codex -C <worktree>` without changing process directory.** Rejected because the
  CLI's contract covers startup hooks and child processes, not only Codex's internal view
  of its working directory.
- **Create a shared cwt Agent Skill.** Rejected because a skill cannot move the active
  process into another worktree; the developer must run the CLI from their shell.
