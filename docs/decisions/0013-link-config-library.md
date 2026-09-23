# 13. Link the config library into harness homes instead of copying

Date: 2026-09-21

Status: Accepted

Supersedes: the installer decisions of [ADR 0007](0007-claude-tree-global-install.md) and
[ADR 0010](0010-shared-agent-skills-library.md). Their tree layout and the "global install is
canonical" position stand.

Partially supersedes: [ADR 0008](0008-pi-global-only-config.md) (its manual copy of
`pi/AGENTS.md` into `~/.pi/agent/`; the global-only position stands).

Tracking: beads epic `ai-config-0ox`

## Context

ADR 0007 introduced `claude/install.sh`, an additive copy into `~/.claude` with a settings
merge report. ADR 0010 added `agents/install.sh` for `~/.agents/skills`, and a third script
copied Codex approval rules. Each grew its own guard set (symlink refusal, containment, staging,
two-phase copy) for a total near 500 lines plus tests. The global instruction files for all
three harnesses stayed hand-merged. In practice the copies drifted: the live `~/.claude` was
behind main on several skills and scripts, `~/.agents/skills` carried 49 skills the repo no
longer shipped, and `~/.local/bin/pwt` pointed at a retired script.

The copy model existed to protect local-only files living next to library files. Once work-only
content moved to a private directory, nothing local-only remained that the repo should not own.

The worktree CLIs (`clwt`, `cwt`, `pwt`) already install themselves as symlinks into the checkout
and have never needed a reinstall step.

Claude Code 2.1.277 started reading `AGENTS.md` directly at project scope when no `CLAUDE.md`
is present, so the repo-root `CLAUDE.md -> AGENTS.md` symlink is no longer needed. User scope is
unchanged: the global file is still `~/.claude/CLAUDE.md`.

## Decision

- One human-run script, `link.sh` at the repo root, symlinks every top-level entry of the repo's
  harness trees and of a private directory (`~/.ai-private`, same layout) into `~/.claude`,
  `~/.agents/skills`, `~/.codex`, and `~/.pi/agent`.
- Global instruction files are symlinks to the repo templates. Work rules live in the private
  directory and load through parent-directory discovery, wired by extra symlink pairs listed in
  a private `links.txt`.
- The managed directories are fully cleaned: anything not linked by the script is deleted,
  except a short allowlist of harness-owned entries.
- The script plans before it writes. Every action, including every deletion, is classified
  first; `--dry-run` prints that plan, and a fatal case stops the run before any change.
- The three copy installers, their tests, and the settings merge report are removed. Settings
  files remain untouched and hand-maintained; the repo keeps `claude/settings.json` as the
  documented reference.
- The repo-root `CLAUDE.md` symlink is dropped; `AGENTS.md` alone is the project instruction
  file.

## Consequences

### Positive

- `git pull` on main is the update. No reinstall step for content changes.
- One command establishes or repairs the whole local setup for all three harnesses.
- Nothing lives in the managed directories that the repo or the private directory does not own,
  so drift is visible as a dry-run diff instead of a forgotten copy.

### Negative / trade-offs

- The primary working tree is live config. Links point into it, so it must stay on `main`;
  `link.sh` refuses to run from a linked worktree, and it is never run from a feature branch.
- Renaming or moving the checkout breaks every link; re-running `link.sh` repairs it.
- A repo/private name collision is a hard error, so a private override of a repo skill is not
  possible by design.
- The full clean makes the script destructive inside the managed directories. `--dry-run`
  lists every deletion, the containment guards are mutation-tested, and the first run is
  preceded by an archive of the managed directories.
- A hook registered in settings by absolute path keeps working only while its link exists. The
  script never deletes a registered hook that it does not re-create.

## Alternatives considered

- **Keep the copy installers and fix the drift.** Rejected because three scripts with three
  guard sets and a manual settings merge are the drift; every content change still needs a
  human to run them.
- **Symlink the whole tree (`~/.claude -> claude/`).** Rejected because the harness homes hold
  harness-owned state (`skills/synced`, `plugins/`, `settings.json`) that cannot live in the
  repo, and because one link per tree cannot merge a second, private source root.
- **A manifest or catalog describing what to link.** Rejected as a new framework for a fixed
  layout; the directory structure already is the manifest.
- **Copy for Codex and Pi, link for Claude.** Rejected because it keeps two update paths and
  the same drift for the two harnesses that are already furthest behind.

ADR 0007 rejected a symlink for a different case: aliasing the repo's own `.claude/` directory
to `claude/`, where the objection was the hidden directory and tools that do not follow links
inside a checkout. Per-entry links from a home directory into a checkout are the mechanism the
worktree CLIs have used since ADR 0005 without that problem.
