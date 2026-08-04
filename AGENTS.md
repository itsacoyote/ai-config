# AGENTS.md

Guidance for working **in this repository**, whichever agent you are. This repo ships three
self-contained harness libraries as siblings — `claude/` (Claude Code), `codex/` (Codex
CLI), `pi/` (Pi) — of development workflows, skills, rules, and references. Codex and Pi
read this file natively; Claude Code reads it through the `CLAUDE.md` symlink. This file
documents how to maintain the libraries — it does **not** travel to other projects.

For the catalog of skills/agents and the feature workflow they implement, see
[README.md](README.md).

## What lives where

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
- `claude/settings.json` — the settings **template** the installer's merge report diffs
  against. It is not live config; this repo carries no project-level Claude config
  directory.
- `codex/`, `pi/` — the other harnesses' trees, each fully self-contained. See
  `codex/README.md` and the root README's "The three harness trees" section.
- `docs/decisions/` — architectural decisions and their rationale.

Decide by intent: a discoverable technique → **skill**; an always-on convention →
**rule**; isolated/independent execution → **agent**; shared reference data →
**reference**; something that must *run* → **script**.

A script that a human runs directly is worth calling out, because an agent cannot always
invoke one. `clwt`'s launching subcommands `cd` into a worktree and `exec claude` — only a
process outside the agent can do that. `claude/install.sh` is the same: it writes into
`~/.claude`, which agents are denied. When a script has that shape, say so in its skill or
README so agents recommend the command instead of trying to run it.

## Authoring conventions

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

The three harness trees are **never synced** — content was duplicated at porting time and
diverges freely (ADR 0006). Editing one tree carries no obligation to touch the others.

## Testing scripts

There is no CI, no package manager, and no test runner here. A script under
`claude/scripts/` or `claude/hooks/` that is non-trivial gets a sibling suite in
`claude/scripts/tests/`, run manually and self-contained:

```bash
bash claude/scripts/tests/clwt-test.sh        # exits non-zero on any failure
bash claude/scripts/tests/beads-gate-test.sh
bash claude/scripts/tests/install-test.sh
```

Build the world the script needs under `mktemp -d` with a fake `$HOME` — a bare remote,
a clone, stub binaries on `PATH` that log how they were invoked. Stubbing the thing the
script *launches* is what makes its behavior observable; `clwt`'s stub `claude` records
`$PWD` and its environment, which is the only honest way to assert that a launched
session really is rooted where it should be.

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

When an assertion exists to catch a specific regression, say so in a comment — including
what it would *fail* to catch.

## Distribution model

The three trees install differently — this is the crux of what each tree *is*:

- **`claude/` is consumed globally.** `claude/install.sh` (run by the **human**, never an
  agent — treat `~/.claude` as human-owned; on this maintainer's machines a settings-level
  deny enforces it) additively copies the content dirs
  into `~/.claude`, where every Claude session on the machine loads them. There is no
  per-project copy of this library; this repo itself runs off the same global install.
  The installer never touches the global settings files — it prints a merge report.
- **`codex/` is a per-project copy.** Self-contained and copied into a target project
  (see `codex/README.md`); Codex's project-scoped discovery is the point there.
- **`pi/` is a personal global file, never copied into a project.** `pi/AGENTS.md`
  installs once to `~/.pi/agent/AGENTS.md` (`mkdir -p ~/.pi/agent && cp pi/AGENTS.md
  ~/.pi/agent/AGENTS.md`) and applies in every repo
  ([ADR 0008](docs/decisions/0008-pi-global-only-config.md)). It carries personal
  accommodations — copying it into a shared repo is the failure mode.

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
