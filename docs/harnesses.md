# Harness configuration and shared skills

This repo ships harness-specific configuration plus a portable Agent Skills library:

- **[`claude/`](../claude/)** — the full workflow library for Claude Code, linked
  **globally** by `link.sh` (see [Installing the library](install.md#installing-the-library)).
- **[`agents/`](../agents/)** — portable Open Agent Skills shared by Codex and Pi, authored in
  `agents/skills/` (currently `branch-names`, `create-pr`, `git-commit`, `pr-review`,
  `writing-skills`). Both harnesses auto-discover project `.agents/skills/` and personal
  `~/.agents/skills/`; `link.sh` links the personal location.
- **[`codex/`](../codex/)** — Codex-specific `AGENTS.md` guidance, manually merged into a
  project when wanted. Skill installation is documented in [`codex/README.md`](../codex/README.md).
- **[`pi/`](../pi/)** — Pi-specific guidance and developer tooling. `pi/AGENTS.md` is a
  **personal global context file** (communication rules, conventions, workflow, change
  gate, execution guardrails), linked as `~/.pi/agent/AGENTS.md` and active
  in every repo ([ADR 0008](decisions/0008-pi-global-only-config.md)). The
  [Pi guide](../pi/README.md) documents the developer-run `pwt` CLI and its separate install.
  Pi also auto-discovers the shared Agent Skills locations
  ([official Pi skills documentation](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md)).

The shared `agents/skills/` tree is one portable source, not synchronized harness copies.
Harness-specific content still diverges freely ([ADR 0006](decisions/0006-per-harness-config-trees.md),
[ADR 0010](decisions/0010-shared-agent-skills-library.md)). `claude/` remains canonical
for the Claude workflow used by this repo.

## Personal user preferences

- **[`claude/CLAUDE.md`](../claude/CLAUDE.md)** — personal preferences for Claude Code, linked
  as `~/.claude/CLAUDE.md`.
- **[`agents/AGENTS.md`](../agents/AGENTS.md)** — equivalent personal preferences expressed
  for a generic coding agent, with a self-contained workflow and no required Claude-only
  tools, linked as `~/.codex/AGENTS.md`. See the
  [shared library guide](../agents/README.md#personal-user-preferences).
- **[`pi/AGENTS.md`](../pi/AGENTS.md)** — the Pi personal global context, linked as
  `~/.pi/agent/AGENTS.md`.

These are standalone, independently maintained files — not generated or synchronized copies —
and because they are linked verbatim into the harness homes, they are the live user
instructions. Keep reusable personal preferences here and put anything work-specific in the
private directory's `work-rules.md`, never in the repo. Follow the
[repository authoring boundary](../AGENTS.md#authoring-conventions); do not preserve private
operational details by merely substituting generic names. The personal instructions in these
files are for global use, not for maintaining this repository; the root `AGENTS.md` governs
that.

This repo's own guidance lives in `AGENTS.md`, read natively by Codex, Pi, and Claude Code
2.1.277 or later (which reads `AGENTS.md` whenever no `CLAUDE.md` exists in the working
directory or above it). There is no `CLAUDE.md` in this repo. Claude Code confirms the load
with an `AGENTS.md loaded` line at session start; the file does not appear in `/memory` or
`/context`.

## `cwt` — Codex worktree CLI

`codex/scripts/cwt` is an independent Codex port of `clwt`. It preserves the same ten
commands and the shared `~/github/.worktrees/<owner>/<repo>/` managed root, but launches
Codex, exports `CWT_REPO_ROOT`, and passes Codex's native `--yolo` flag. Run its launching
commands from your shell, not from inside an active Codex session. Unlike `clwt` and `pwt`,
`cwt` does not name sessions: Codex has no launch-time session-name option.

```bash
codex/scripts/cwt install
```

Installation, Bash/zsh completion, command behavior, safety boundaries, and the manual
test command are documented in the [Codex cwt guide](../codex/README.md#cwt--worktree-cli).
The independent-port rationale is recorded in
[ADR 0011](decisions/0011-cwt-worktree-cli.md).

## `pwt` — Pi worktree CLI

`pi/scripts/pwt` is the developer-facing Pi launcher for the same ten-command worktree
lifecycle. It shares the managed `~/github/.worktrees/<owner>/<repo>/` root with `clwt`
and `cwt`, physically enters the selected checkout, exports `PWT_REPO_ROOT`, and executes
Pi. Run its launching commands from your shell, not from inside an active Pi session.

Pi has no yolo mode. For pull requests, `pwt` keeps context-file discovery but disables
extensions and restricts the model to the `read`, `grep`, `find`, and `ls` tools without
project approval. This is a Pi tool boundary for trusted PRs, not an OS sandbox.

Every launching subcommand also passes `--name` to `pi`, the same way `clwt` does. An
override must use the two-token form, `--name X` or `-n X` — Pi silently ignores
`--name=X` — and `pwt` adds no name when the first argument after `--` is a Pi command
word (`auth`, `install`, `remove`, `uninstall`, `update`, `list`, `config`), so that
command still runs.

```bash
pi/scripts/pwt install
```

Installation, completion, all ten commands, safety boundaries, and the manual test command
are documented in the [Pi pwt guide](../pi/README.md#pwt--worktree-cli). The independent-port
rationale is recorded in [ADR 0012](decisions/0012-pwt-worktree-cli.md).

## Codex command approval rules

The Codex-specific command allowlist lives in codex/rules/ai-config.rules using Codex's
experimental prefix_rule format. `link.sh` symlinks it into ~/.codex/rules/ next to Codex's
own default.rules; it never touches config.toml or the user's other rules. See
[Installing the library](install.md#installing-the-library) and the Codex guide in codex/README.md.
