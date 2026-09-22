# AGENTS.md

Guidance for working **in this repository**, whichever agent you are. This repo ships
harness-specific configuration under `claude/`, `codex/`, and `pi/`, plus portable Agent
Skills under `agents/skills/`. Codex, Pi, and Claude Code (2.1.277 or later) read this file
natively; there is no `CLAUDE.md` in this repo. This file documents how to maintain the
libraries — it does **not** travel to other projects.

For the catalog of skills/agents and the feature workflow they implement, see
[README.md](README.md).

## What lives where

- `claude/CLAUDE.md` — the personal user-preferences file, linked as `~/.claude/CLAUDE.md`.
  Its personal instructions are for global use, not for maintaining this repository; this
  root file governs repository maintenance.
- `claude/skills/<name>/SKILL.md` — a skill (methodology/reference loaded when relevant).
  Supporting files live alongside it.
- `claude/agents/<name>.md` — a subagent: a **thin** wrapper that runs a skill in an
  isolated context. Methodology stays in the skill, not the agent. (Claude-specific —
  the other harnesses have no subagents.)
- `claude/rules/<name>.md` — an always-on convention (auto-applied), for rules that should
  apply without being invoked.
- `claude/references/<name>.md` — shared knowledge multiple skills point to (kept in one
  place so it doesn't drift).
- `claude/scripts/<name>` — executable tooling. Two kinds live here: helpers a skill
  shells out to (`worktree-status.sh`) and **developer-facing CLIs**
  (`clwt`), which the human runs from their own shell rather than an agent invoking.
  Tests go in `claude/scripts/tests/`.
- `claude/hooks/<name>.sh` — SessionStart hooks, registered in the user's global
  settings (Claude-specific).
- `claude/settings.json` — the settings **template**: the documented reference for which
  hooks, permissions, and statusline to register by hand. It is not live config and is never
  linked or written; this repo carries no project-level Claude config directory.
- `codex/scripts/<name>` — Codex-specific executable tooling. `cwt` is a developer-facing
  CLI with its completion beside it and tests under `codex/scripts/tests/`.
- `pi/scripts/<name>` — Pi-specific executable tooling. `pwt` is a developer-facing Pi launcher
  with its completion beside it and tests under `pi/scripts/tests/`.
- `codex/rules/ai-config.rules` — Codex command approval rules; `link.sh` symlinks it into
  `~/.codex/rules/`.
- `agents/skills/<name>/SKILL.md` — portable Open Agent Skills shared by Codex and Pi.
  New cross-harness skills belong here; harness-specific behavior stays in its own tree.
- `codex/`, `pi/` — harness-specific configuration and guidance. See `codex/README.md`,
  `pi/README.md`, and the root README's distribution section.
- `docs/decisions/` — architectural decisions and their rationale.

Decide by intent: a discoverable technique → **skill**; an always-on convention →
**rule**; isolated/independent execution → **agent**; shared reference data →
**reference**; something that must *run* → **script**.

A script that a human runs directly is worth calling out, because an agent cannot always
invoke one. `clwt`, `cwt`, and `pwt` launch their harnesses by replacing the current process —
only a process outside the active agent can do that. `pwt pr` also enforces Pi's
`--no-extensions --tools read,grep,find,ls --no-approve` boundary; document it as a model-tool
restriction for trusted pull requests, not an OS sandbox. `link.sh` is the same: it writes
into `~/.claude`, `~/.agents`, `~/.codex`, and `~/.pi`, which agents are denied, and it deletes
inside the managed directories. When a script has that shape, say so in its skill or README so
agents recommend the command instead of trying to run it.

## Authoring conventions

**Keep private external work out of this repository.** Never commit employer-, client-, or
external-project-specific names, ticket prefixes, account/repository paths, environment
instructions, service identifiers, or related helpers. Remove entire related sections
before importing personal configuration; replacing names alone is not sufficient. This
applies to all repository content, including examples, archives, commit messages, and PR
text. Do not repeat excluded names in exclusion rules or test fixtures. This repository's
own identifiers, ordinary tool names, generic examples, and unrelated personal preferences
are allowed.

When creating or editing skills, follow the `writing-skills` skill, and:

- **Descriptions are triggers-led.** Start with "Use when…"; describe *when* to reach for
  the skill, not *what it does*. A workflow summary in the description makes an agent
  shortcut reading the body.
- **Single source of truth.** Don't restate shared facts across skills — put them in one
  place and link. The conventional-commit type list is canonical in `git-commit`; the
  beads model is canonical in `claude/references/beads.md`; shared checklists live in
  `claude/references/`.
- **Cross-link at boundaries** rather than duplicating. Skills that meet (e.g. design vs.
  implementation, discover vs. prescribe) point to each other instead of overlapping.
- **Scope down.** Include a "When NOT to use" so a skill isn't over-applied to trivial work.
- **No dead links.** Every referenced skill/agent/file must exist. Verify before committing.
- **Avoid name collisions with built-in commands.** (Claude-specific.) Built-ins include
  `code-review`, `security-review`, `review`, `verify`, `init`, `run`. (That's why this
  repo uses `senior-review` and `security-scan`.)

Harness-specific trees are **never synced** — content duplicated at porting time diverges
freely (ADR 0006). `agents/skills/` is different: it is one canonical portable source loaded
by Codex and Pi, not synchronized copies. Editing a harness tree still carries no obligation
to touch another tree.

## Testing scripts

There is no CI, no package manager, and no test runner here. A script under
`claude/scripts/` or `claude/hooks/` that is non-trivial gets a sibling suite in
`claude/scripts/tests/`; the root-level `link.sh` has its suite in `tests/`. All run manually
and self-contained:

```bash
bash tests/link-test.sh                       # exits non-zero on any failure
bash claude/scripts/tests/clwt-test.sh
bash codex/scripts/tests/cwt-test.sh
bash pi/scripts/tests/pwt-test.sh
bash claude/scripts/tests/beads-gate-test.sh
```

Build the world the script needs under `mktemp -d` with a fake `$HOME` — a bare remote,
a clone, stub binaries on `PATH` that log how they were invoked. Stubbing the thing the
script *launches* is what makes its behavior observable; the `clwt`, `cwt`, and `pwt` suites
stub `claude`, `codex`, and `pi` respectively, recording `$PWD`, arguments, and environment.
That is the only honest way to assert that a launched session really is rooted where it
should be.

**Target stock macOS bash 3.2** — scripts and their suites both. A bash 4+ builtin
(`mapfile`, associative arrays) does not fail loudly here; `mapfile` left `COMPREPLY`
empty, which kept ten completion assertions unrunnable on the only machine that runs
them. Where a version-specific builtin is tempting, write the portable loop and pin the
rule with a source-level check.

**Mutation-test every guard: delete it, re-run, restore.** On the `clwt` branch this
caught three guards that could be removed with the suite fully green — the destructive
`prune` containment checks, a symlink guard whose test was rejected by a *different*
check first, and a `git`-failure guard whose test ran against the wrong directory
entirely. A passing suite is not evidence that an assertion tests what its name says.
Two recurring causes, both worth checking directly:

- **A test that passes for the wrong reason.** It asserts the right outcome via the wrong
  path — an error message that matches a substring of an unrelated failure, a command
  that fails because `env` cannot invoke a shell function, a fixture rejected by an
  earlier guard than the one under test.
- **A fixture that works around the bug.** `clwt`'s harness pre-resolved `$HOME`, which
  hid a real path-resolution defect completely. If a fixture normalizes something, ask
  whether the code should have been the one to normalize it.
- **A fixture that never reaches the failure under test.** `clwt pr`'s auto-force tests
  used a "force-pushed" head built as a *child* of the old tip — a fast-forward, so the
  checkout succeeded on its own and every assertion stayed green with the feature
  disabled. Mutating the feature off, not just the guard, is what exposed it; where a
  fixture must have a shape, assert that shape.

When an assertion exists to catch a specific regression, say so in a comment — including
what it would *fail* to catch.

## Distribution model

One human-run script, `link.sh` at the repo root, symlinks every top-level entry of the
harness trees, and of a private directory with the same layout (`~/.ai-private`), into the
harness homes; inside the managed directories it deletes everything it did not link, except a
short allowlist of harness-owned entries ([ADR 0013](docs/decisions/0013-link-config-library.md)).
Agents never run it: the harness homes are human-owned, and on this maintainer's machines a
settings-level deny enforces it. It never touches settings files, `config.toml`, or auth files.
`git pull` on `main` is the update. What each tree *is*:

- **`claude/` is consumed globally.** Its six content dirs, `CLAUDE.md`, and
  `statusline-command.sh` are linked into `~/.claude`, where every Claude session on the
  machine loads them. There is no per-project copy of this library; this repo itself runs off
  the same global links.
- **`agents/skills/` is shared by Codex and Pi.** Both harnesses discover project
  `.agents/skills/` and personal `~/.agents/skills/` automatically; the personal location is
  linked. `agents/AGENTS.md` is linked as `~/.codex/AGENTS.md`.
- **`codex/` contains Codex-specific guidance.** Its `AGENTS.md` remains a manually merged
  project template; `codex/rules/ai-config.rules` is linked into `~/.codex/rules/`.
- **`pi/` contains Pi-specific guidance and developer tooling.** `pi/AGENTS.md` is a
  personal global file, linked as `~/.pi/agent/AGENTS.md`; copying it into a shared repo is
  the failure mode ([ADR 0008](docs/decisions/0008-pi-global-only-config.md)).
  `pi/scripts/pwt` remains a developer-run CLI; `link.sh` runs its `install`, and those of
  `clwt` and `cwt`, so `~/.local/bin` points into the primary checkout.

## Workflow state: beads is required

This project uses **beads** as the system of record — there is **no `.docs/` folder and no
`context.yaml`**. Workflow skills hard-stop and redirect to `setup-beads` when beads is
absent; there is no standalone/conversational fallback. See
[docs/decisions/0001-beads-required.md](docs/decisions/0001-beads-required.md) for the
rationale. Don't reintroduce step-doc files.

## Commits and PRs

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages
and PR titles: `type(scope): description`. **Never add AI attribution** — no
`Co-Authored-By` trailers, no generated-by text, no mention of the agent. After
committing, surface the exact message back (see the `git-commit` skill).

## Archive

The previous automated pipeline (the `/feature` orchestrator, step agents, `context.yaml`)
is preserved in [`archive/`](archive/) for reference. It is **not** active — don't wire
current skills to it. Treat references to `context.yaml`, `.docs/`, the `/feature`
orchestrator, or personas in archived material as historical.
