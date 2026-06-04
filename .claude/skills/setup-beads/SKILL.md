---
name: setup-beads
description: Use when setting up beads (the `bd` issue tracker) in a project so the workflow skills can track tasks — installs `bd` if missing, runs an isolated local `bd init`, keeps `.beads/` out of git, and optionally wires the `bd prime` session-start hook. Developer-invoked one-time setup; defaults to personal/local use with nothing committed.
disable-model-invocation: true
allowed-tools: Read Write Edit Bash(bd *) Bash(git *) Bash(command -v *) Bash(test *) Bash(ls *) Bash(uname *) Bash(brew *) Bash(npm *)
---

# Setup Beads

Stand up [beads](https://github.com/gastownhall/beads) (`bd`) in a project so the workflow skills (`define`, `research`, `planning-and-task-breakdown`, `incremental-implementation`, `validate`, `document`, `standup`) can track features, tasks, and findings as real issues. This is a guided, one-time setup — it asks a couple of questions and applies the right configuration, it is not a fixed script.

The default it steers toward is **personal, local, isolated use**: the issue database lives only on this machine, nothing beads-related is committed to the repo, and there is no remote or push. That suits public, private, and shared repos alike — beads stays invisible to everyone else.

## When NOT to use

- Beads is already initialized here (`.beads/` exists and `bd ready` works) — there's nothing to set up. Re-run only to change the git mode or the session hook.
- You don't actually want issue tracking for this project — the workflow skills all run fine standalone without beads (see [`.claude/references/beads.md`](../../references/beads.md)).

## How beads stores data (read this first)

`bd` keeps its issues in an **embedded [Dolt](https://www.dolthub.com/) database** under `.beads/embeddeddolt/`, running in-process — there is **no daemon and nothing to "start."** `bd init` writes a `.beads/config.yaml` and a nested `.beads/.gitignore` that already excludes the Dolt data dirs. The `.beads/issues.jsonl` file, if present, is an **export for interchange — not the source of truth.**

Two consequences shape this setup:

- You never `git add` the database. The git question is really *"should issues sync anywhere?"* — and for personal/local use the answer is **no**.
- `dolt.auto-commit` is **on** by default, but that is a *local* Dolt commit (internal versioning of your issues), **not** a git commit or a network push. Leave it on. `dolt.auto-push` is **off** by default — leave it off for isolated use.

**The CLI is large and evolves.** Before relying on any flag below, verify it with `bd <command> --help`. If a flag named here has changed, prefer what `--help` reports.

## Preflight

1. Confirm this is a git repository: `git rev-parse --is-inside-work-tree`. If not, tell the user beads can still run but the isolated-mode `.gitignore` step won't apply, and ask whether to continue.
2. Check whether `bd` is already on PATH: `command -v bd`. If present, run `bd version` and skip to **Initialize**. If absent, go to **Install bd**.

## Install bd

`bd` is not installed. Offer the install methods below and **confirm before running anything** — this installs software on the user's machine.

| Method | Command |
|--------|---------|
| Homebrew (macOS/Linux) | `brew install beads` |
| npm | `npm install -g @beads/bd` |
| curl (Linux/macOS/FreeBSD) | `curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh \| bash` |

Pick the one matching the user's environment (prefer an already-present package manager). After install, verify with `bd version`. If it fails, surface the error and stop — don't proceed to `bd init`.

## Choose the git mode

Ask which mode the user wants. **Default to Local/isolated** — it's the right answer for personal use and shared repos.

- **Local / isolated (default).** Issues live only on this machine. Nothing beads-related is committed; no remote; no push. Achieved with `bd init --stealth`, which configures `.git/info/exclude` (local, never committed). Best for shared/public/private repos where beads is just *your* tracker.
- **Tracked (advanced).** Issues travel with the repo via a git-backed Dolt remote on the `refs/dolt/data` ref (separate from code branches). Only choose this if the user explicitly wants issues shared through the repo. Setup: after init, `bd dolt remote add origin <repo-url>` and optionally enable `dolt.auto-push`; a fresh clone re-hydrates with `bd bootstrap`. This skill does not push for the user.

The rest of this skill assumes **Local/isolated** unless the user picked Tracked.

## Initialize (local/isolated)

Initialize in **stealth + non-interactive** mode:

```bash
bd init --stealth --non-interactive
```

- `--stealth` — the purpose-built personal-use mode: configures `.git/info/exclude` (local, never committed) so `.beads/` and `.claude/settings.local.json` stay invisible to the repo and collaborators. This — not a tracked `.gitignore` — is how "nothing committed" is achieved.
- `--non-interactive` — skips all prompts (role defaults to `maintainer`; `--contributor`/`--team` are rejected here anyway). Auto-detected for non-TTY, but pass it explicitly.
- The issue prefix defaults to the directory name (e.g. `ai-config` → `ai-config-<hash>`); pass `-p <prefix>` to override.
- **Verify flags with `bd init --help` first — they evolve.** Notably there is **no** `--skip-agents`; the `AGENTS.md` profile is `--agents-profile` (default `minimal`, just a pointer to `bd prime`), and `-q/--quiet` only *suppresses output*, it does not skip prompts.

(For **tracked mode**, omit `--stealth`, then add a remote — see "Tracked mode" below.)

## Clean up bd's tracked `.gitignore` edit

Even in stealth mode, `bd init` appends a beads block (`.dolt/`, `*.db`, `.beads-credential-key`) to the repo's **tracked** root `.gitignore`. Since `.git/info/exclude` already hides all of `.beads/`, that block is redundant and would commit beads-related lines — so remove it:

```bash
git diff .gitignore         # confirm the only change is bd's "# Beads / Dolt files" block
git checkout -- .gitignore  # revert if that block is the sole change
```

If `.gitignore` had other unstaged edits, delete just the bd-added block by hand instead of reverting the whole file. Then confirm the local exclude is in place:

```bash
grep -q '\.beads/' .git/info/exclude && echo "✓ .beads/ excluded locally"
```

After this, `git status` should show **nothing** beads-related.

## Do NOT run `bd setup claude`

beads ships a `bd setup claude` command, but **avoid it in this config.** It writes hooks to the **committed** `.claude/settings.json` and appends a beads section to the **committed** `CLAUDE.md` — and that injected section tells the agent to stop using `MEMORY.md` and the harness task tools (`TaskCreate`/TodoWrite) and to follow a mandatory git-push session protocol. All of that conflicts with how this workflow operates. Wire only what you need, by hand, below.

## Let the skills drive bd without prompts

Add `Bash(bd *)` to the `allow` list in **`.claude/settings.local.json`** (project-local, git-excluded under stealth) so the workflow skills can run `bd` smoothly. Use the `update-config` skill for the edit.

## Session-start priming (optional — off by default)

`bd prime` injects ~1–2k tokens of beads context at session start — useful, **but** its injected text is opinionated: it instructs the agent not to use `MEMORY.md` or `TaskCreate` and to run a session-close/push protocol, which fights this config's memory system and isolated (no-push) setup. So **don't wire it automatically.**

The workflow skills already invoke beads on demand via [`.claude/references/beads.md`](../../references/beads.md) (`bd ready`, `bd prime`, etc.) when doing real workflow work — that's enough, without injecting contradictory guidance into every session.

If a user explicitly wants auto-priming despite the caveat, add a `SessionStart` (and optionally `PreCompact`) hook running `bd prime --stealth` to **`.claude/settings.local.json`** (git-excluded) via the `update-config` skill — never to the committed `settings.json`.

## Verify and recap

1. `bd version` — confirm the CLI works.
2. `bd ready` — smoke-test the database (empty list is success: it means beads is initialized with no ready issues yet).
3. Recap what was configured: install method, mode (local/isolated), `bd init` flags used, that bd's `.gitignore` edit was reverted and `.beads/` is excluded via `.git/info/exclude`, the `Bash(bd *)` permission, and whether a `bd prime` hook was added (default: no).

Then point the user at the next step: the workflow skills now run in **beads-enhanced** mode automatically — `define` creates a feature epic, `planning-and-task-breakdown` files tasks, and so on, per [`.claude/references/beads.md`](../../references/beads.md). Try `define` to start a feature, or `standup` to read current state.

## What this skill will not do

- **Never install software without confirming first.** Installing `bd` touches the user's machine.
- **Never push beads data or add a remote in local/isolated mode.** No `bd dolt push`, no `bd dolt remote add`.
- **Never leave beads-related changes in the tracked tree.** Revert bd's `.gitignore` edit; rely on `.git/info/exclude` (stealth). After setup, `git status` shows nothing beads-related.
- **Never run `bd setup claude` in this config** — it pollutes committed `CLAUDE.md` + `settings.json` with conflicting rules.
- **Never write hooks or permissions to committed settings** — `.claude/settings.local.json` only (git-excluded under stealth).
- **Never pass `--contributor` or `--team`** — this is personal-use setup.
- **Never trust a flag it hasn't verified** against `bd <command> --help` — the CLI evolves (e.g. `--skip-agents` does not exist; `-q` only suppresses output).
