# 12. Add pwt as an independent Pi worktree CLI

Date: 2026-09-08

Status: Accepted

Related: [ADR 0004](0004-revert-agent-agnostic-library.md),
[ADR 0005](0005-clwt-worktree-cli.md), [ADR 0006](0006-per-harness-config-trees.md),
[ADR 0008](0008-pi-global-only-config.md), and
[ADR 0011](0011-cwt-worktree-cli.md)

Tracking: beads epic `ai-config-jh0`

## Context

The current `cwt` provides the complete ten-command worktree lifecycle and the safety
behavior established by `clwt`. Pi needs that same developer-facing workflow and shared
managed root, but its launch and trust interfaces differ from Codex.

The historical `pwt` added in PR #56 established two useful ideas: keep Pi worktrees under
the central `~/github/.worktrees/` tree, and physically enter the target before executing
Pi. It was removed with the failed agent-agnostic configuration architecture, not because
those ideas were unsound. Its five-command surface permanently refused pull requests and
carried a Python-based PATH and executable-provenance subsystem that is not part of the
local-user threat model adopted for the later launchers.

Pi has no native `--yolo` option and no OS-level sandbox. Its project-trust controls and
tool selection are ordinary command-line arguments, with later values overriding earlier
ones. Extensions can execute code and replace tool names before the restricted agent
session begins. A dependable pull-request mode therefore needs a Pi-specific argument
boundary rather than a flag rename from `cwt`.

## Decision

- Add `pi/scripts/pwt` as an independent Pi port with its own completion and
  self-contained Bash suite. It is copied from the proven behavior at porting time, not
  generated from or synchronized with another harness tree.
- Preserve the ten commands, managed-root layout, `.worktreeinclude` copying with
  unconditional `.beads/` exclusion, PR identity markers, and destructive-operation
  safeguards from `cwt`.
- Launch with physical `cd -P` followed by `exec pi`. Export `PWT_REPO_ROOT` to the new
  session, and also accept it as a validated primary-repository override for controlled
  use and tests.
- Provide no `--yolo` behavior. Normal launch arguments after `--` pass through to Pi
  unchanged.
- Treat pull-request launch as a restricted model-tool boundary. Keep repository context
  files enabled, reject forwarded options that can change tools or project trust, load
  extensions, or switch to another session directory, then append
  `--no-extensions --tools read,grep,find,ls --no-approve` immediately before execution.
- Document PR mode for trusted pull requests under a local-user threat model.
  It is not an OS sandbox: Git hooks and filters, copied secrets, model-provider traffic,
  user shell input, session storage, and trusted global Pi configuration remain outside
  the tool allowlist's protection.
- Keep the CLI developer-facing. An active Pi process cannot relocate itself by launching
  `pwt`; the developer runs launching commands from an outside shell. Do not add a shared
  `agents/skills/pwt` wrapper.
- Target stock macOS Bash 3.2. Completion reads local Git state and inserts branch names
  as inert, shell-escaped data.

Compared with the historical `pwt`, this implementation adds `pr`, `root`, `prune`, and
`install`, handles linked-worktree repository discovery, copies `.worktreeinclude` files,
and replaces permanent PR refusal with the explicit Pi tool boundary. It does not restore
the Python PATH-rebuilding and executable-provenance subsystem. Compared with `cwt`, it
launches Pi, has no `--yolo`, validates the `PWT_REPO_ROOT` override, and enforces the
Pi-specific PR suffix above.

## Consequences

### Positive

- Pi gets the complete, tested worktree lifecycle and interoperates with worktrees created
  by the other harness launchers.
- Normal sessions begin in the intended physical checkout without changing their Pi
  arguments.
- PR sessions cannot receive model tools that write or execute shell commands, and project
  extensions cannot replace the allowlisted read tools.
- Harness-specific behavior can evolve without a cross-tree synchronization obligation.

### Negative / trade-offs

- Independent Bash implementations duplicate substantial logic, so fixes must be evaluated
  and ported deliberately.
- PR restrictions reduce model capabilities but do not isolate the host or make arbitrary
  pull requests safe to check out.
- Context files remain visible in PR sessions by design; their contents can influence the
  model even though they cannot grant additional tools.
- `pwt` must be run by the developer for launching commands; an active Pi session cannot
  move itself into another worktree.

## Alternatives considered

- **Share a core implementation with `cwt` and `clwt`.** Rejected because launch flags,
  trust behavior, completion, tests, and future lifecycle needs are harness-specific; a
  shared core would recreate the coupling rejected by ADR 0006.
- **Restore the historical `pwt` unchanged.** Rejected because its command surface and
  repository discovery are incomplete, it cannot review pull requests, and its large
  provenance subsystem solves a different threat model.
- **Invoke `cwt` and replace only the final executable.** Rejected because Codex's yolo and
  sandbox flags do not map to Pi's tool and trust controls.
- **Keep refusing every pull request until Pi provides an OS sandbox.** Rejected because
  the approved workflow needs repository context with read-only model tools, and the
  remaining local-user risks can be stated honestly instead of claiming host isolation.
