# 7. Rename .claude/ to claude/ and make the global install canonical

Date: 2026-08-03

Status: Accepted

Tracking: beads epic `ai-config-5d3`

## Context

[ADR 0006](0006-per-harness-config-trees.md) added `codex/` and `pi/` as visible,
self-contained harness trees. That left `.claude/` as the odd sibling: a hidden directory
shaped like live project configuration, while the maintainer actually consumes the library
**globally** — every machine mirrors it into `~/.claude` by hand, a workflow documented
nowhere in the repo. The dot-directory also made this repository double as a live Claude
project (SessionStart hooks, a bd/git permission allowlist, a statusline), entangling the
library's source with one repo's session config.

Claude Code's plugin system was considered as the installation mechanism and rejected for
this feature: plugin-delivered skills and commands are namespaced, which would break the
bare `/define`-style invocations the workflow is built around, and the library's rules,
references, and settings have no plugin primitive. A rename plus a plain install script
achieves the goal without those costs.

## Decision

- Rename `.claude/` to `claude/` (a `git mv`; internal layout unchanged) so the three
  harness trees are symmetric: `claude/`, `codex/`, `pi/`.
- The user-global `~/.claude` is **canonical** for running the library. This repository
  ships source; it no longer carries live project-level Claude config. The pieces that
  existed only project-locally — the SessionStart hooks, the bd/git permission allowlist,
  the statusline — move into the user's global configuration.
- `claude/install.sh` is the installation path: it copies the content directories
  (`skills/`, `agents/`, `rules/`, `references/`, `scripts/`, `hooks/`) into `~/.claude`,
  idempotently. It **never creates or edits `~/.claude/settings.json`** — settings are
  merged by hand from the report it prints, because a user's global settings file carries
  personal configuration no script should silently rewrite. `claude/settings.json` stays
  in the tree as the template that report diffs against.
- `beads-gate.sh` becomes safe as a global hook: silent (exit 0, no output) in any project
  without a beads database, unchanged where beads exists. A globally-installed hook runs
  in every repo, so warning noise in non-beads projects is a defect, not a feature.
- The per-project copy model for the Claude library ("copy `.claude/` into the target
  project") is retired from the docs. The `codex/` and `pi/` trees keep their per-project
  copy model — their harnesses' project-scoped discovery is the point there.
- This repo's own guidance becomes agent-agnostic: the root guidance file is `AGENTS.md`
  (which Codex and Pi read natively), with `CLAUDE.md` kept as a symlink to it so Claude
  sessions load the same content. One file, three harnesses.
- `archive/` and prior ADRs keep their `.claude/` mentions; history is not rewritten.

## Consequences

### Positive

- The three trees read as what they are: three harness libraries, none of them live config.
- Installing or updating a machine is one command plus a printed settings-merge checklist,
  replacing an undocumented manual mirror.
- Sessions in unrelated repos stop being one global-hook-install away from beads-gate
  warning noise.

### Negative / trade-offs

- Sessions in this repo depend on the user's global config being installed and current —
  a stale `~/.claude` means stale skills here too (previously the project `.claude/`
  pinned them). The install script being one command is the mitigation.
- Project-scoped permissions (`settings.local.json`, the repo allowlist) become global:
  the bd/git allowlist applies everywhere, which is acceptable for this user but is a
  wider grant than before.
- Anyone who previously copied `.claude/` into their own project must switch to the
  install script; the README documents the change.

## Alternatives considered

- **Claude Code plugin packaging.** Rejected — command/skill namespacing breaks bare
  invocations; rules/references/settings have no plugin primitive; a marketplace adds
  moving parts for a single-user library.
- **Keep a thin `.claude/` shim (settings.json only) for live-in-repo behavior.**
  Rejected by the maintainer — anything project-level that matters belongs in global;
  two config sources is the confusion this feature removes.
- **Symlink `claude/` from `.claude/`.** Rejected — keeps the hidden dir, breaks on
  machines/tools that don't follow symlinks, and preserves the ambiguity.
- **Leave `.claude/` as-is.** Rejected — the asymmetry with `codex/`/`pi/` and the
  undocumented mirror workflow are the problem statement.
