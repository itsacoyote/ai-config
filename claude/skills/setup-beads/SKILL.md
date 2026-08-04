---
name: setup-beads
description: Use when setting up beads (the `bd` issue tracker) in a project for the first time so workflow skills can track tasks.
disable-model-invocation: true
allowed-tools: Read Write Edit Bash(bd *) Bash(git *) Bash(command -v *) Bash(test *) Bash(ls *) Bash(uname *) Bash(brew *) Bash(npm *) Bash(sh ${CLAUDE_SKILL_DIR}/scripts/setup-beads.sh*) Bash(bash ${CLAUDE_SKILL_DIR}/scripts/setup-beads.sh*)
---

# Setup Beads

Stand up [beads](https://github.com/gastownhall/beads) (`bd`) in a project so the workflow skills (`define`, `research`, `planning-and-task-breakdown`, `incremental-implementation`, `validate`, `document`, `standup`) can track features, tasks, and findings as real issues.

The default — **personal, local, isolated use** — is fully deterministic and lives in a script: the issue database lives only on this machine, nothing beads-related is committed to the repo, and there is no remote or push. That suits public, private, and shared repos alike — beads stays invisible to everyone else. Your job is the two judgment calls the script deliberately leaves out (installing `bd`, and whether the user wants the non-default *tracked* mode); the script does the rest.

## Do this

For the standard local/isolated setup, run the script from the repo root:

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/setup-beads.sh            # prefix defaults to the dir name
sh ${CLAUDE_SKILL_DIR}/scripts/setup-beads.sh -p myprefix  # override the issue prefix
```

It is idempotent and self-guarding. In one pass it: refuses to run in a git worktree, no-ops if `.beads/` already exists, stops with install instructions if `bd` is missing (it never installs software), runs `bd init --stealth --non-interactive`, reverts bd's `.gitignore` edit, ensures the `.git/info/exclude` entries, adds `Bash(bd *)` to `.claude/settings.local.json`, then verifies (`bd version` / `bd ready`) and prints a recap.

**Read the script's output.** If it exits non-zero it tells you exactly why (not a git repo, in a worktree, or `bd` not installed) — handle that condition per the sections below, then re-run. If it succeeds, the recap is your report to the user; relay it. There is nothing to do by hand on the happy path.

## When NOT to use

- Beads is already initialized here (`.beads/` exists and `bd ready` works) — there's nothing to set up. Re-run only to change the git mode or the session hook.
- **You are in a git worktree.** Worktrees share the main repo's single `.beads/` (see "Worktrees share the database" below) — `bd ready` already works there. Never run setup or `bd init` from a worktree; doing so forks the database.

Note: beads is now **required** by the workflow skills (they hard-stop and redirect here when `.beads/` is absent). This skill is how you satisfy that requirement — it is the bootstrap and must remain runnable without beads itself.

## How beads stores data (read this first)

`bd` keeps its issues in an **embedded [Dolt](https://www.dolthub.com/) database** under `.beads/embeddeddolt/`, running in-process — there is **no daemon and nothing to "start."** `bd init` writes a `.beads/config.yaml` and a nested `.beads/.gitignore` that already excludes the Dolt data dirs. The `.beads/issues.jsonl` file, if present, is an **export for interchange — not the source of truth.**

Two consequences shape this setup:

- You never `git add` the database. The git question is really *"should issues sync anywhere?"* — and for personal/local use the answer is **no**.
- `dolt.auto-commit` is **on** by default, but that is a *local* Dolt commit (internal versioning of your issues), **not** a git commit or a network push. Leave it on. `dolt.auto-push` is **off** by default — leave it off for isolated use.

**The CLI is large and evolves.** Before relying on any flag below, verify it with `bd <command> --help`. If a flag named here has changed, prefer what `--help` reports.

## When the script says `bd` is missing

The script never installs software — if `bd` is not on PATH it stops and prints the methods below. **Confirm with the user before installing anything** (it touches their machine), then run the chosen command and re-run the script.

| Method | Command |
|--------|---------|
| Homebrew (macOS/Linux) | `brew install beads` |
| npm | `npm install -g @beads/bd` |
| curl (Linux/macOS/FreeBSD) | `curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh \| bash` |

Pick the one matching the user's environment (prefer an already-present package manager). After install, verify with `bd version`. If it fails, surface the error and stop — don't re-run the script.

## Choose the git mode

The script only does the **default, local/isolated** mode. Before running it, confirm that's what the user wants — it's the right answer for personal use and shared repos, so default to it unless they ask otherwise.

- **Local / isolated (default — the script's job).** Issues live only on this machine. Nothing beads-related is committed; no remote; no push. The script runs `bd init --stealth`, which configures `.git/info/exclude` (local, never committed) so `.beads/` and `.claude/settings.local.json` stay invisible to the repo and collaborators. Best for shared/public/private repos where beads is just *your* tracker.
- **Tracked (advanced — manual, NOT the script).** Issues travel with the repo via a git-backed Dolt remote on the `refs/dolt/data` ref (separate from code branches). Only choose this if the user explicitly wants issues shared through the repo. Do **not** run the script; instead `bd init` (no `--stealth`), then `bd dolt remote add origin <repo-url>` and optionally enable `dolt.auto-push`; a fresh clone re-hydrates with `bd bootstrap`. Never push for the user without asking.

### Why stealth, and what the script reverts

Useful context if you need to debug a run or do tracked mode by hand:

- `--stealth` is the purpose-built personal-use mode — `.git/info/exclude` (local, never committed), not a tracked `.gitignore`, is how "nothing committed" is achieved. `--non-interactive` skips prompts (role defaults to `maintainer`).
- Even in stealth, `bd init` appends a beads block to the **tracked** root `.gitignore`. Since the exclude already hides `.beads/`, that block is redundant and would commit beads-related lines — so the script reverts `.gitignore` to its pre-init content. After a run, `git status` shows **nothing** beads-related.
- **The CLI is large and evolves — verify flags with `bd <command> --help` before relying on them.** Notably there is **no** `--skip-agents`; the `AGENTS.md` profile is `--agents-profile` (default `minimal`); `-q/--quiet` only *suppresses output*, it does not skip prompts. If a flag the script passes has changed, update the script.

## Worktrees share the database

There is **one `.beads/` per repository**, in the main working tree, and **every git
worktree shares it** — `bd` resolves the database through the repo's shared git common dir,
so `bd` run from a worktree reads and writes the main repo's `.beads/`. This is what lets
parallel sessions reference each other's issues. Two rules protect it:

- **Never `bd init` in a worktree** — it forks a second database that drifts from the main one.
- **Never add `.beads/**` to `.worktreeinclude`** — Claude Code *copies* (does not symlink)
  those patterns, so each worktree would get its own fork. Leave `.beads/` out and let the
  git-common-dir resolution share the one database. See [`.claude/references/beads.md`](../../references/beads.md).

## Do NOT run `bd setup claude`

beads ships a `bd setup claude` command, but **avoid it in this config.** It writes hooks to the **committed** `.claude/settings.json` and appends a beads section to the **committed** `CLAUDE.md` — and that injected section tells the agent to stop using `MEMORY.md` and the harness task tools (`TaskCreate`/TodoWrite) and to follow a mandatory git-push session protocol. All of that conflicts with how this workflow operates. Wire only what you need, by hand, below.

## Session-start gate hook

A committed `SessionStart` hook (`.claude/hooks/beads-gate.sh`, wired in the committed `.claude/settings.json`) ships as standard in this config. It runs automatically at the start of every session and:

- detects whether beads is present (`.beads/` exists, `bd` on PATH)
- warns and tells the user to run `setup-beads` when beads is absent
- injects `bd ready` context when beads is present, so the session starts with current task state

**Do NOT wire `bd prime` as an additional hook.** `bd prime` injects ~1–2k tokens of opinionated context that instructs the agent not to use `MEMORY.md` or `TaskCreate` and to run a session-close/push protocol — that fights this config's memory system and isolated (no-push) setup. The committed gate hook is purpose-built and avoids those conflicts.

The script writes the `Bash(bd *)` permission to **`.claude/settings.local.json`** (git-excluded under stealth) using `jq` — never to committed settings. If `jq` is unavailable it says so; add the permission by hand with the `update-config` skill.

## After the script succeeds

The script's recap is your report — relay it (mode, flags, that `.gitignore` was reverted, the exclude and permission, and that the gate hook ships committed). Then point the user at the next step: the workflow skills now run with beads — `define` creates a feature epic, `planning-and-task-breakdown` files tasks, and so on, per [`.claude/references/beads.md`](../../references/beads.md). Try `define` to start a feature, or `standup` to read current state.

## What this skill will not do

- **Never install software without confirming first.** Installing `bd` touches the user's machine.
- **Never push beads data or add a remote in local/isolated mode.** No `bd dolt push`, no `bd dolt remote add`.
- **Never leave beads-related changes in the tracked tree.** Revert bd's `.gitignore` edit; rely on `.git/info/exclude` (stealth). After setup, `git status` shows nothing beads-related.
- **Never run `bd setup claude` in this config** — it pollutes committed `CLAUDE.md` + `settings.json` with conflicting rules.
- **Never write hooks or permissions to committed settings** — `.claude/settings.local.json` only (git-excluded under stealth).
- **Never pass `--contributor` or `--team`** — this is personal-use setup.
- **Never trust a flag it hasn't verified** against `bd <command> --help` — the CLI evolves (e.g. `--skip-agents` does not exist; `-q` only suppresses output).
- **Never `bd init` in a git worktree or copy `.beads/` into one** — worktrees share the main repo's single database via the git common dir; forking it loses writes.
