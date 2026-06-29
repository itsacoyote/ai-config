---
name: sync
description: Bring the local checkout up to date with main before starting feature work — clean-tree check with optional stash, fetch and fast-forward pull, change summary, and detection-driven refresh of dependencies, migrations, .env keys, and Docker. Developer-invoked; never runs destructive git or auto-applies migrations.
disable-model-invocation: true
allowed-tools: Read Bash(sh .claude/skills/sync/scripts/sync.sh*) Bash(bash .claude/skills/sync/scripts/sync.sh*)
---

# Sync

Invoked as `/sync` by the developer — a pre-feature ritual that brings the local checkout up to date with `main` before new work begins. The mechanics live in a script; your job is to run it, make the two human decisions with the developer, and relay its summary.

It **never** performs destructive git operations, never auto-applies migrations, never modifies `.env`, and never runs `docker compose pull`/`build`. It is developer-invoked — not a pipeline step — and persists no state between runs.

## Run it

### 1. Preview (read-only)

```bash
sh .claude/skills/sync/scripts/sync.sh --dry-run
```

This mutates nothing. It detects and reports: the main branch (`init.defaultBranch` → `origin/HEAD` → `main`), the current branch, whether the working tree is **dirty** (with the paths), the **package ecosystems** present (lockfile + `package.json` `packageManager`, with the exact install command), **migration** tools (with the command, using the detected JS runner — `npx`/`pnpm dlx`/`yarn`/`bunx`), the **`.env` key diff** (keys in the example file missing from `.env`, names only), **Docker** compose presence, and any **project-specific** sync section in `CLAUDE.md`/`AGENTS.md`/`.cursorrules`/`.windsurfrules`.

### 2. Make the two decisions with the developer

The script is safe by default — it will not touch a dirty tree and will not install anything unless told. From the preview, settle both:

- **Dirty working tree?** If the preview shows uncommitted changes, ask the developer: **stash** them (pass `--stash` — runs `git stash push -u`, recoverable with `git stash pop`) or **handle it themselves** (stop; they commit/discard, then rerun). Never offer or run a destructive recovery (`git reset --hard`, `git clean`, `git checkout -- <path>`).
- **Which dependencies to install?** For the detected ecosystems, ask which to install. Pass `--install all`, a comma list of the approved tools (e.g. `--install pnpm,bundler`), or omit it to install none (they stay recommendations). `pip`/`pyproject` are always surfaced-only, never installed.

### 3. Execute

```bash
sh .claude/skills/sync/scripts/sync.sh [--stash] [--install all|<csv>] [--main <branch>]
```

This stashes (if `--stash`), switches to main, `git fetch`, `git pull --ff-only`, captures pre/post SHAs, runs the approved installs (checking each exit code), and prints the structured summary — branch state (+ stash recovery), recent commits (capped at 20 with a `+N more` footer), dependencies (ran/skipped/not-installed), migrations to consider, missing `.env` keys, Docker warning, and project-specific steps. **Relay that summary** to the developer.

If the script exits non-zero, it prints the failing command and stderr and stops — surface that verbatim and don't retry (a failed `--ff-only` pull is never retried with `--rebase`/`--no-ff`).

## When NOT to use

- Mid-feature — this is a *pre-feature* refresh, not a mid-stream rebase.
- In any automated pipeline — it's a developer-facing utility only.

## What this skill will not do

These are hard constraints the script enforces; keep them when editing it.

- **Never commit, reset, clean, or discard.** The only mutation to a dirty tree is `git stash push -u`, and only with `--stash`.
- **Never auto-apply migrations** — they are surfaced as recommended commands only.
- **Never modify `.env`** — missing keys are reported by name; the file is never read for values, written, or copied.
- **Never `docker compose pull`/`build`** — only the stale-image warning is printed.
- **Never retry a failed `--ff-only` pull**, never handle merge conflicts on main, and support **only** `origin` + the detected main branch.
- **Never install missing binaries** — an ecosystem whose tool isn't on `PATH` is marked "not installed" and skipped.
- **Never persist state** between runs, and never write to a feature folder.
- Git only (no Mercurial/SVN/jj); POSIX shell only (macOS/Linux, not Windows).
