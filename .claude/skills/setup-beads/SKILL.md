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

- **Local / isolated (default).** Issues live only on this machine. Nothing beads-related is committed; no remote; no push. Best for shared/public/private repos where beads is just *your* tracker.
- **Tracked (advanced).** Issues travel with the repo via a git-backed Dolt remote on the `refs/dolt/data` ref (separate from code branches). Only choose this if the user explicitly wants issues shared through the repo. Setup: after init, `bd dolt remote add origin <repo-url>` and optionally enable `dolt.auto-push`; a fresh clone re-hydrates with `bd bootstrap`. This skill does not push for the user.

The rest of this skill assumes **Local/isolated** unless the user picked Tracked.

## Initialize

Run a **non-interactive** init so it never blocks on prompts (the skills drive `bd`, not the user):

```bash
bd init --quiet --skip-agents
```

- `--quiet` — non-interactive init intended for AI agents; skips the contributor-mode prompt.
- `--skip-agents` — don't generate beads' own `AGENTS.md`. This config already carries beads guidance in [`.claude/references/beads.md`](../../references/beads.md); a second, bd-generated instructions file would duplicate and drift. (Drop this flag only if the user explicitly wants bd's `AGENTS.md`.)
- Do **not** pass `--contributor` or `--team` — those are for OSS-fork and team-branch workflows, not personal use.

Verify the flags first with `bd init --help`, then run it. Capture and show the output.

## Keep `.beads/` out of git (local/isolated mode)

So nothing beads-related is committed, ensure the repo's **root `.gitignore`** ignores the whole directory:

```gitignore
# beads (personal issue tracker — local only)
.beads/
```

- If `.gitignore` doesn't exist, create it with that block.
- If `.beads/` (or an equivalent) is already ignored, leave it and say so.
- If `.beads/` was already accidentally tracked from a prior run, surface it and offer to untrack: `git rm -r --cached .beads/` (this removes it from git, not from disk). `bd doctor --fix` can also repair the gitignore state.

Do not commit anything in this step — only edit `.gitignore`. Whether the developer commits that one-line `.gitignore` change is their call.

## Session-start priming (optional but recommended)

`bd prime` injects ~1–2k tokens of current beads context (ready work, workflow state) into a session at start and after compaction — a local read, no network. Wiring it as a `SessionStart` hook means every Claude Code session opens already aware of the beads state.

To honor "nothing beads-related committed," put the hook in **`.claude/settings.local.json`** (project-scoped but git-ignored), **not** the committed `.claude/settings.json`. Delegate the edit to the `update-config` skill, adding a `SessionStart` hook that runs `bd prime`:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bd prime" } ] }
    ]
  }
}
```

Ask before adding the hook — it changes session startup behavior. (`bd setup claude` is beads' own command for this, but it may target committed settings; prefer the `settings.local.json` route above for isolated use, and offer `bd setup claude` only if the user doesn't mind committed hooks.)

## Verify and recap

1. `bd version` — confirm the CLI works.
2. `bd ready` — smoke-test the database (empty list is success: it means beads is initialized with no ready issues yet).
3. Recap what was configured: install method, mode (local/isolated), `bd init` flags used, the `.gitignore` entry, and whether the `bd prime` hook was added and where.

Then point the user at the next step: the workflow skills now run in **beads-enhanced** mode automatically — `define` creates a feature epic, `planning-and-task-breakdown` files tasks, and so on, per [`.claude/references/beads.md`](../../references/beads.md). Try `define` to start a feature, or `standup` to read current state.

## What this skill will not do

- **Never install software without confirming first.** Installing `bd` touches the user's machine.
- **Never push beads data or add a remote in local/isolated mode.** No `bd dolt push`, no `bd dolt remote add`.
- **Never commit.** It only edits `.gitignore` and (with consent) `settings.local.json`; the developer decides what to commit.
- **Never write the session hook to committed settings** in isolated mode — `settings.local.json` only.
- **Never pass `--contributor` or `--team`** — this is personal-use setup.
- **Never trust a flag it hasn't verified** against `bd <command> --help` — the CLI evolves.
