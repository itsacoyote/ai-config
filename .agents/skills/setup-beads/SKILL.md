---
name: setup-beads
description: Use when setting up beads (the `bd` issue tracker) in a project for the first time so workflow skills can track tasks.
metadata:
  category: git-maintenance
---

# Setup Beads

Stand up [beads](https://github.com/gastownhall/beads) (`bd`) in a project so the workflow skills (`define`, `research`, `planning-and-task-breakdown`, `incremental-implementation`, `validate`, `document`, `standup`) can track features, tasks, and findings as real issues.

The default — **personal, local, isolated use** — is fully deterministic and lives in a script: the issue database lives only on this machine, nothing beads-related is committed to the repo, and there is no remote or push. That suits public, private, and shared repos alike — beads stays invisible to everyone else. Your job is the two judgment calls the script deliberately leaves out (installing `bd`, and whether the user wants the non-default *tracked* mode); the script does the rest.

## Do this

For the standard local/isolated setup, resolve `scripts/setup-beads.sh` relative to this skill directory and run its absolute path from the repository root:

```bash
sh <skill-dir>/scripts/setup-beads.sh            # prefix defaults to the dir name
sh <skill-dir>/scripts/setup-beads.sh -p myprefix  # override the issue prefix
```

It is idempotent and self-guarding. In one pass it refuses to run in a git worktree, no-ops if `.beads/` already exists, stops with install instructions if `bd` is missing, runs `bd init --stealth --non-interactive`, reverts bd's `.gitignore` edit, ensures the `.git/info/exclude` entry, verifies with `bd version` and `bd ready`, and prints a recap. It does not install software or mutate harness-specific permissions/settings.

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

- **Local / isolated (default—the script's job).** Issues live only on this machine. Nothing beads-related is committed; no remote; no push. The script runs `bd init --stealth`, which configures `.git/info/exclude` (local, never committed) so `.beads/` stays invisible to the repo and collaborators. Best for shared/public/private repos where beads is just *your* tracker.
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
- **Never copy `.beads/**` into a worktree through any harness or worktree include mechanism.** A copy creates a fork. Leave `.beads/` out and let git-common-dir resolution share the one database. See [`beads.md`](../../references/beads.md).

## Do not install harness-generated beads configuration

Avoid `bd setup <harness>` generators in this library. They may append opinionated instructions, hooks, permissions, or push protocols that conflict with the portable workflow and its isolated no-push default. Root `AGENTS.md` and the installed adapters own startup guidance; the setup script intentionally changes no harness settings.

Do not add `bd prime` as an automatic startup hook. Its broad injected workflow can conflict with the library's concise beads contract. Use `bd ready` when current task state is needed.

## After the script succeeds

Relay the script's recap: mode, flags, `.gitignore` restoration, local exclude, and verification. Then point the user at the next step: workflow skills now run with beads—`define` creates a feature epic, `planning-and-task-breakdown` files tasks, and [`beads.md`](../../references/beads.md) defines the lifecycle. Try `define` to start a feature or `standup` to read current state.

## What this skill will not do

- **Never install software without confirming first.** Installing `bd` touches the user's machine.
- **Never push beads data or add a remote in local/isolated mode.** No `bd dolt push`, no `bd dolt remote add`.
- **Never leave beads-related changes in the tracked tree.** Revert bd's `.gitignore` edit; rely on `.git/info/exclude` (stealth). After setup, `git status` shows nothing beads-related.
- **Never run a harness-specific `bd setup` generator in this config**—adapters and root guidance are managed by the library.
- **Never write hooks or permissions to harness settings**—setup is tracker-only.
- **Never pass `--contributor` or `--team`** — this is personal-use setup.
- **Never trust a flag it hasn't verified** against `bd <command> --help` — the CLI evolves (e.g. `--skip-agents` does not exist; `-q` only suppresses output).
- **Never `bd init` in a git worktree or copy `.beads/` into one** — worktrees share the main repo's single database via the git common dir; forking it loses writes.
