# 5. Manage worktrees with a developer-run CLI instead of the built-in feature

Date: 2026-08-02

Status: Accepted

Tracking: beads epic `ai-config-qsj`

## Context

The workflow in this repository assumes one worktree per feature, disposable, with several
long-lived Claude sessions running in parallel against the same repo. Claude Code ships a
built-in worktree feature, and `.worktreeinclude` exists to tell it which untracked files to
copy into a new worktree. In practice that arrangement has four gaps:

- **Working directory.** A session that is not rooted in its worktree operates on it from a
  distance, with `git -C <path> …`. The path is re-derived on every call, a wrong path
  silently succeeds against the wrong tree, and every relative path a skill computes is wrong.
  There was no `deny` rule preventing it.
- **Control.** Worktree location and naming are decided for us. We want a known per-repo
  root, branch-derived names, and a base of the *current* `origin` default branch.
- **Teardown.** `CLAUDE.md` says a worktree is disposable and should go once its branch
  merges, but doing so is a manual per-worktree loop of PR-state checks and `git worktree
  remove`. Stale worktrees accumulate because the habit costs more than it saves.
- **Tracker centrality.** Beads works across worktrees only because `bd` resolves its database
  through the git common dir — established in [PR #48](https://github.com/itsacoyote/ai-config/pull/48)
  after `.worktreeinclude` copied `.beads/` into worktrees, forking the database and losing
  writes. That guarantee is implicit, specific to `bd`, and will not transfer to the
  SQLite-based tracker intended to replace beads.

A prior attempt at this existed: `pwt`, a 470-line Pi launcher added in PR #56 and removed
with the rest of the agent-agnostic library ([ADR 0004](0004-revert-agent-agnostic-library.md)).
Its worktree and launch logic was sound; roughly 150 of its lines were PATH sanitization,
executable ownership/permission auditing, and shebang-interpreter resolution.

A hard constraint shapes the whole design: **`claude` has no flag to start in a given
directory** — it inherits its working directory from the process that launched it. So the
only way to root a session in a worktree is `cd <worktree> && exec claude`, and only a
process *outside* Claude can do that. Claude cannot relaunch itself.

## Decision

Add `clwt`, a Bash CLI at `.claude/scripts/clwt`, run by the developer from their shell.

- **It launches by `cd` + `exec`.** Every launching subcommand changes into the target
  directory and `exec`s `claude`, so the session's real working directory is the worktree.
  `git -C` becomes unnecessary, and a `permissions.deny` entry of `Bash(git -C *)` in
  `.claude/settings.json` removes its default spelling. **This is a speed bump, not a boundary** —
  `git -C/tmp` without a space is rejected by git so the glob covers the only valid `-C` form, but
  `git --git-dir=… --work-tree=… status` and `cd <path> && git status` remain available and are not
  denied. Adding patterns for those was considered and rejected as more likely to block legitimate
  work than to catch a real regression; the launcher, not the rule, is what makes reaching across
  directories pointless. Nothing under `.claude/` used `git -C`, so the rule costs nothing today.
  (`statusline-command.sh` at the repo root does use it, but `statusLine` runs outside the Bash
  permission system and is unaffected.)
- **Worktrees live at `~/github/.worktrees/<owner>/<repo>/<branch-with-slashes-as-dashes>/`**,
  a consistent sibling of the `~/github/<owner>/<repo>` checkout layout. `clwt` refuses to
  create, move, or remove anything outside that managed root.
- **`.worktreeinclude` is honored**, so a new worktree can actually run the project. `clwt`
  hard-refuses to copy `.beads/` even when the file matches it, and says why. This guard is
  load-bearing: `git ls-files --others --ignored --exclude-from=<file>` returns gitignored
  paths, so `.beads/` *would* be copied if listed.
- **`CLWT_REPO_ROOT` is exported into every launched session**, holding the absolute path of
  the primary checkout — note this is *not* what `git rev-parse --git-common-dir` returns, which
  is the `.git` directory. This is the tool-agnostic form of the centrality guarantee: `bd`
  keeps using the git common dir untouched, and a future SQLite tracker reads one env var
  instead of reimplementing git internals. Its scope is honestly narrower than "tool-agnostic
  centrality" suggests: it exists only in sessions `clwt` launched, so a tracker must still carry
  a fallback for a `claude` started by hand.
- **Teardown is a first-class command.** `prune` lists managed worktrees whose branch has a
  merged PR and a clean tree, and removes them only with `--yes`. Dirty worktrees are never
  candidates.
- **The security scaffolding from `pwt` is not carried over.** PATH rebuilding, executable
  uid/mode auditing, and interpreter resolution defend against an attacker who already has
  write access to the machine — not the threat model for a CLI the developer runs from their
  own interactive shell. The guards that prevent *mistakes* are kept: managed-root
  containment, `git check-ref-format` on branch names, symlink refusal, and dirty-tree
  refusal on removal. This drops the `python3` dependency and takes the script from ~470 to
  under 300 lines.
- **A thin `.claude/skills/clwt/SKILL.md`** teaches Claude when to recommend `clwt` and states
  that it is already in the target worktree and must use plain git. The skill does not launch
  anything — it cannot.

`worktree-status.sh` and the `reground` skill are unchanged. They report across all worktrees
with plain git and keep working regardless of how a worktree was created.

## Consequences

### Positive

- A session's working directory is correct by construction, not by discipline.
- Worktree location and naming are predictable, so `clwt list` and manual `cd` are both easy.
- The disposable-worktree habit becomes one command, so it will actually be followed.
- The centrality guarantee is explicit and survives the beads → SQLite migration.
- The tool sits beside `worktree-status.sh` and travels with the library on copy.

### Negative / trade-offs

- **`clwt` cannot be invoked by Claude** for the launching subcommands — the developer must
  run it. This is inherent, not an implementation gap.
- **Two ways to make a worktree now exist.** Claude Code's built-in feature is not disabled,
  so a worktree can still appear outside the managed root. `clwt list` shows those as
  unmanaged, but `clwt` will not manage them.
- **`.worktreeinclude` copies drift.** A `.env` copied at creation does not track later edits
  to the original. Accepted, because it matches the built-in feature's semantics and because
  per-worktree divergence is sometimes wanted.
- **`gh` becomes a dependency** for `pr` and `prune`.
- **The `Bash(git -C *)` deny is repo-wide.** A future legitimate cross-worktree read from a
  Bash tool call would be blocked and need the rule revisited. Scripts are unaffected, since
  `bash .claude/scripts/foo.sh` is a single tool call whose contents the matcher never sees.

## Alternatives considered

- **Keep using Claude Code's built-in worktree feature.** Rejected — it does not solve
  working directory, location control, or teardown, which are three of the four problems.
- **A shell function sourced from `.bashrc` instead of a script on `PATH`.** Rejected: it
  would let `clwt` change the *caller's* directory after Claude exits, which is mildly nice,
  but it is shell-specific, harder to test, and gives up `exec` isolation.
- **A skill that Claude runs.** Rejected as impossible for the launching commands: Claude
  cannot `exec` itself into a new working directory. A skill accompanies the CLI instead of
  replacing it.
- **Rely on the git common dir alone for tracker centrality.** Rejected as insufficiently
  future-proof — correct for `bd` today, but it pushes the same git-internals resolution onto
  every future tracker. `CLWT_REPO_ROOT` costs two lines and is tool-agnostic.
- **Write a pointer file (`.clwt-root`) into each worktree** instead of exporting an env var.
  Rejected as the primary mechanism: it adds an untracked file to every worktree and goes
  stale if the repo moves. Reconsider if processes `clwt` did not launch need the value.
- **Symlink `.worktreeinclude` matches instead of copying.** Rejected — it diverges from the
  built-in feature's semantics, prevents per-worktree values, and breaks with tools that
  rewrite `.env` in place.
- **Port `pwt` verbatim and just rename it.** Rejected — most of its length is scaffolding for
  a threat model that does not apply here, and it carries a `python3` dependency for work git
  already does.
