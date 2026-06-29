# Diff Scope Contract

Single source of truth for the **diff-scope** mechanism: how spawners compute it, how
agents consume it, and why it exists. Review agents and the validate/autorun skills point
here instead of restating the model.

## What a diff scope is

A diff scope is a **pinned identifier for the change under review**. A spawner (validate or
autorun) resolves it once — from the current git state — and passes the already-pinned range
to every review agent in the dispatch. The agents receive the scope, not the diff content:
each agent fetches the content itself (`git diff <base>..<head>`) against the pinned range.

This matters because:

- Multiple agents reviewing the same commit must pin the **identical base**. Without a
  passed scope each agent re-derives merge-base independently, which can diverge if the repo
  state changes between spawns.
- Pasting diff content into dispatches costs diff×(N+1) tokens and bloats the long-lived
  orchestrator context. Passing only the pinned scope (a few dozen bytes) keeps the
  orchestrator lean.

## Payload format in a dispatch

Include the scope as a single prose line near the top of the agent dispatch:

```
Diff scope: <base-sha>..<head-sha> — changed files: path/A, path/B, …
```

The line carries:
- **base sha** — the already-resolved merge-base (branch scope) or parent commit (per-task
  scope). Full 40-char SHA or a short unambiguous abbreviation.
- **head sha** — the already-resolved tip. Same.
- **range** — the `<base>..<head>` form; agents use this directly.
- **file list** — the `--name-only` output for that range; lets agents skip fetching the
  full diff when a file-list check is enough.

Example:

```
Diff scope: a1b2c3d4..e5f6a7b8 — changed files: .claude/references/diff-scope.md, .claude/agents/senior-review.md
```

## How a spawner computes it

A spawner runs **`diff-scope.sh`** (this directory) — the single source of the resolution
logic — and copies the line it prints into the agent dispatch. Do not re-derive the
merge-base inline.

### Branch scope (validate / end-of-run)

Reviewing everything on the current branch relative to the default branch:

```bash
sh .claude/references/diff-scope.sh
# Diff scope: <merge-base>..<HEAD> — changed files: …
```

The default branch is resolved from `origin/HEAD` (fallback `main`); override with
`--base <branch>`.

### Per-task scope (autorun per-task reviews)

When autorun spawns a per-task reviewer after the implementer commits, pin that task's
commit(s):

```bash
sh .claude/references/diff-scope.sh --task              # single-commit task (base = HEAD~1)
sh .claude/references/diff-scope.sh --task <first-sha>  # multi-commit task: explicit base autorun knows
```

For a multi-commit task, pass the first commit of the task (autorun knows it from the
implementer's return); the range runs through `HEAD`.

### Reading the diff yourself (e.g. document)

A caller that consumes the diff directly rather than dispatching agents gets just the range:

```bash
git diff "$(sh .claude/references/diff-scope.sh --range)"
```

## SHA-resolution boundary (important)

**The spawner resolves all SHAs; the agent only diffs.**

The spawner calls `git rev-parse`, `git merge-base`, and `git symbolic-ref` to produce
already-pinned SHAs. The agent then runs only:

```bash
git diff <base>..<head>           # full diff
git diff --name-only <base>..<head>   # file list
```

`git diff *` is covered by every review agent's existing Bash allowance, so **consuming a
passed diff scope requires no new agent tool permissions**. The rev-parse / merge-base /
symbolic-ref calls stay in the spawner only — or in an agent's self-derive fallback where
they are already present.

## How an agent consumes a passed scope

When the dispatch includes a diff scope line, use the pinned range directly:

1. Parse `<base>` and `<head>` from the scope line.
2. Run `git diff <base>..<head>` (or `--name-only`) — do **not** recompute merge-base.
3. If the diff is empty, report "nothing to review" and stop.

The file list in the scope line is a convenience; the agent may re-derive it with
`--name-only` against the same range if needed.

## Fallback (mandatory)

If no diff scope is passed — standalone invocation, ad-hoc use, or a spawner that has not
yet been updated — the agent falls back to its own base-detection. Behavior is identical to
today:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
git diff $(git merge-base HEAD ${BASE:-main}) HEAD
```

Agents that have `Bash(git merge-base *)` and `Bash(git symbolic-ref *)` in their tool
allowlist use the snippet above. Agents whose allowlist covers only `Bash(git diff *)` may
use the three-dot form instead:

```bash
git diff origin/${BASE:-main}...HEAD
```

Either fallback produces a complete, standalone review with no scope passed.

## Rationale — scope, not content

Each reviewer needs the diff content in its own context regardless; there is no way to avoid
that cost. What **can** be avoided is:

- The orchestrator holding a copy of the diff (bloats the long-lived context for every
  subsequent task).
- N agents each re-deriving the base independently (inconsistency risk, N×symbolic-ref
  calls).
- Pasting the full diff into N dispatch messages (diff×(N+1) token overhead, and still
  doesn't eliminate the per-agent fetch).

Passing only the pinned scope — a single short line — solves all three. The diff content
lands in each reviewer's context when the reviewer fetches it, and nowhere else. Base
detection is canonical here; agents link this file rather than duplicating the logic.

This is why there is no separate ADR: the rationale lives in this file.
