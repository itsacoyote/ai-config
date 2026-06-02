# Spec: Sync Skill

**Date:** 2026-06-01
**Status:** Draft

## Summary

`sync` is a Claude Code skill a developer invokes before starting new feature work. It safely switches the working tree to the latest `main`, then performs project-specific environment refresh steps so the developer is never working against a stale local checkout. The skill verifies the working tree is clean before switching branches, pulls `main`, detects what changed since the previous sync, and runs the install/migrate/check steps implied by the project's lockfiles, config files, and `CLAUDE.md`. The output is a short, human-readable summary of what was synced, what was refreshed, and what (if anything) the developer should look at before starting work.

## Problem Statement

A developer about to start a new feature today has to remember, by hand, every step required to bring their local environment up to date with `main`. The common failure modes:

- They run `git checkout main && git pull` while uncommitted edits sit in another branch, and either get blocked mid-checkout or silently stomp work.
- They pull `main` but forget to run `npm install` / `bundle install` / `uv sync`, and waste 10 minutes debugging a stack trace from a package version mismatch.
- They forget to run pending database migrations and hit a "column does not exist" error on first request.
- A teammate added a key to `.env.example` last week; the developer's local `.env` is missing it, and the app starts but fails at the first call that needs the new variable.
- Docker images referenced by `docker-compose.yml` were rebuilt upstream, but the local cache is stale.
- The developer has no idea what landed on `main` since they last synced, so they're surprised by behavior changes or accidentally duplicate work.

These are all preventable with a deterministic pre-feature ritual. Doing it by hand is error-prone; doing it inside `/feature` is the wrong layer (the pipeline already assumes the branch is current). A dedicated `sync` skill is the right home.

## Goals

- The developer can run a single command and end up on `main`, up to date with origin, with a refreshed local environment, and a short summary of what changed.
- Uncommitted work is never silently lost: if the working tree is dirty, the skill pauses before any branch switch and asks the developer whether to stash the changes and continue, or stop so they can handle it themselves.
- Stale dependencies are caught: the package manager implied by the project's lockfiles is detected and the install step is run using the project's detected JS package runner where applicable.
- Stale schema is caught: well-known migration tools (Rails, Alembic, Prisma, Flyway, Django, Knex) are detected and the developer is told which migration command to run (using the detected JS package runner for Node-based tools), or it is offered as an opt-in.
- Missing environment variables are surfaced: if `.env.example` (or equivalent) lists keys missing from `.env`, those keys are reported by name.
- Stale containers are surfaced: if `docker-compose.yml` / `compose.yaml` is present, the developer is warned that local images may be out of date.
- Project-specific post-pull instructions in `CLAUDE.md` (and adjacent rules files such as `AGENTS.md`, `.cursorrules`, `.windsurfrules`) are read and executed or surfaced.
- The developer sees a `git log` summary of commits that landed on `main` since the previous local `main` HEAD.

## Non-Goals

- The skill will not commit uncommitted work for the developer, and will not discard or force-reset it. The only mutation it ever performs on a dirty tree is `git stash`, and only after the developer explicitly chooses that option at the dirty-tree prompt.
- The skill will not run destructive operations (`git reset --hard`, `git clean -fdx`, `rm -rf node_modules`) under any circumstance.
- The skill will not auto-apply database migrations without explicit developer confirmation. Migrations are surfaced as a recommended command, not silently executed.
- The skill will not rewrite or modify `.env`. Missing keys are reported, not copied or filled.
- The skill will not rebuild Docker images or run `docker compose pull` automatically. It surfaces the recommendation only.
- The skill will not be wired into the `/feature` pipeline. It is invoked directly by the developer.
- The skill will not support non-git VCS (Mercurial, SVN, jj).
- The skill will not handle merge conflicts on `main`. If `git pull` fails, the skill stops and prints the error.
- The skill will not support remotes other than `origin` or base branches other than the project's configured main branch.

## User Stories

- As a developer about to start a new feature, I want to run `/sync` and have my checkout brought up to date with `main`, including dependencies and migrations, so that I don't waste the first 15 minutes of work debugging a stale environment.
- As a developer with uncommitted changes on a feature branch, I want `/sync` to pause, show me exactly which files are dirty, and ask whether to stash them and continue or stop so I can handle them myself, so that I don't lose work and I'm not blocked when a quick stash would do.
- As a developer returning after a week off, I want `/sync` to show me a `git log` of what landed on `main` while I was out, so that I know what to expect.
- As a developer on a polyglot repo (e.g. Node + Python), I want `/sync` to detect both lockfiles and run both install commands, so that I don't have to remember each one.
- As a developer whose teammate just added `STRIPE_WEBHOOK_SECRET` to `.env.example`, I want `/sync` to tell me my local `.env` is missing that key by name, so that I add it before my app silently breaks.
- As a developer on a Rails project, I want `/sync` to detect pending migrations and tell me the exact command to run, so that I'm not surprised by a schema mismatch.

## Requirements

### Skill structure

- The skill lives at `.claude/skills/sync/SKILL.md` with frontmatter `name: sync`, a `description` field, and `allowed-tools` declaring the Bash patterns the skill uses (`git`, `gh`, package-manager binaries, `docker compose`, `diff`, `cat`, `ls`, `find`, `grep`).
- The frontmatter sets `disable-model-invocation: true` so the skill only runs when the developer explicitly invokes `/sync`.
- The skill is documented in `README.md` alongside the other top-level skills (`/feature`, `/pr-review`).

### Preflight: cleanliness check

- Before any branch operation, the skill runs `git status --porcelain`. If the output is non-empty, the skill prints the list of dirty paths and prompts the developer with exactly two options:
  1. **Stash and continue** — the skill runs `git stash push -u -m "sync: auto-stash <timestamp>"` and proceeds with the rest of the workflow. The stash ref is captured and surfaced in the final summary so the developer knows how to recover (`git stash pop` / `git stash list`).
  2. **Let me handle it** — the skill stops without running any further command, leaving the working tree exactly as it was. The developer commits or discards the changes themselves and reruns `/sync`.
- The prompt accepts only those two answers (e.g. `s` / stash, `h` / handle). Any other input re-asks until one of them is given. There is no "discard" option — the skill never runs `git reset --hard`, `git clean`, or `git checkout -- <path>`.
- If `git stash` itself fails (e.g. partial-merge state, unmerged paths), the skill prints the stash stderr and stops; it does not fall back to any destructive recovery.
- The skill also runs `git rev-parse --is-inside-work-tree` to confirm it's inside a git repo. If not, it stops with a clear message.
- The skill detects the project's main branch by checking, in order: the `init.defaultBranch` config, then `origin/HEAD`, then falling back to `main`. The detected branch name is printed before checkout.

### Branch switch and pull

- After preflight, the skill records the current branch name (for the optional return-to-branch summary).
- The skill checks out the detected main branch and runs `git fetch origin` followed by `git pull --ff-only origin <main>`.
- If `git pull --ff-only` fails (non-fast-forward, network error, auth), the skill stops and prints the exact stderr. It does not attempt `--rebase` or `--no-ff`.
- After a successful pull, the skill records the new `HEAD` SHA.

### Change summary

- The skill prints a `git log --oneline --no-merges <previous-main-sha>..HEAD` between the pre-pull `main` SHA and the post-pull SHA. The pre-pull SHA is captured from `git rev-parse <main>` before `git pull`.
- If there are no new commits, the skill prints "main is already up to date — no new commits since last sync."
- If there are more than 20 new commits, the skill prints the most recent 20 and a "+N more" footer.

### Environment refresh: package managers

The skill detects package managers by lockfile presence and runs the matching install command. Each detection is independent — a polyglot repo runs every applicable install.

Detection of the **JS package manager** (npm / yarn / pnpm / bun) doubles as detection of the **JS package runner** used to invoke locally-installed CLI tools (`prisma`, `drizzle-kit`, `knex`, etc.). The detected runner is reused by the migrations section below. Precedence when multiple JS lockfiles exist: `bun.lockb`/`bun.lock` → `pnpm-lock.yaml` → `yarn.lock` → `package-lock.json`. The runner for each manager is:

| JS manager (lockfile) | Detected runner prefix |
|---|---|
| bun (`bun.lockb` / `bun.lock`) | `bunx` |
| pnpm (`pnpm-lock.yaml`) | `pnpm dlx` (or `pnpm exec` for binaries already in `node_modules/.bin`) |
| yarn (`yarn.lock`) | `yarn` (i.e. `yarn prisma migrate deploy`) |
| npm (`package-lock.json`) | `npx` |

If no JS lockfile is detected, the skill defaults to `npx` when surfacing Node-based recommended commands, and notes that no JS manager was detected.

| Lockfile | Tool | Install command |
|---|---|---|
| `package-lock.json` | npm | `npm install` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` |
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `bun.lockb` / `bun.lock` | bun | `bun install` |
| `Gemfile.lock` | bundler | `bundle install` |
| `requirements.txt` | pip | `pip install -r requirements.txt` (surfaced only — not run) |
| `uv.lock` | uv | `uv sync` |
| `poetry.lock` | poetry | `poetry install` |
| `Pipfile.lock` | pipenv | `pipenv install` |
| `go.sum` | go | `go mod download` |
| `Cargo.lock` | cargo | `cargo fetch` |
| `composer.lock` | composer | `composer install` |
| `mix.lock` | mix | `mix deps.get` |

- Before running each install, the skill checks whether the corresponding binary is on `PATH`. If not, it skips with a "tool not installed" warning rather than failing.
- The actual install commands are surfaced to the developer with a one-line confirmation prompt per ecosystem before they run. The developer can answer `yes`, `no`, or `all` (run every remaining install without further prompts).
- pip's `requirements.txt` is surfaced as a recommendation only (never auto-run), because the right environment manager (venv, conda, system) is project-dependent.

### Environment refresh: migrations

- The skill detects migration tools by the presence of known files or directories and surfaces the recommended migration command. Migrations are never run automatically.
- For Node-based migration tools (Prisma, Knex, Drizzle, and the Supabase CLI when installed via npm), the recommended command is prefixed with the **detected JS package runner** from the package-managers section above (`bunx` / `pnpm dlx` / `yarn` / `npx`), so the printed command matches the project's actual JS tooling rather than hardcoding `npx`. Non-Node tools (Rails, Alembic, Flyway, Django) are unaffected — they use their own runners.

The table below shows commands as they would appear in an **npm-detected** project; the leading `npx` is replaced with the project's detected runner at print time. The Supabase row shows both the standalone-CLI form and the npm-installed form.

| Signal | Tool | Recommended command (with detected JS runner) |
|---|---|---|
| `bin/rails` or `config/application.rb` | Rails | `bin/rails db:migrate` |
| `alembic.ini` | Alembic | `alembic upgrade head` |
| `prisma/schema.prisma` | Prisma | `<js-runner> prisma migrate deploy` (or `dev`, dev choice) |
| `flyway.conf` or `flyway/` | Flyway | `flyway migrate` |
| `manage.py` with `django` in any requirements file | Django | `python manage.py migrate` |
| `knexfile.js` / `knexfile.ts` | Knex | `<js-runner> knex migrate:latest` |
| `drizzle.config.ts` / `drizzle.config.js` | Drizzle | `<js-runner> drizzle-kit migrate` |
| `supabase/migrations/` | Supabase | `supabase db push` (or `<js-runner> supabase db push` if installed via the JS package manager) |

Substitution rules for `<js-runner>`:

- bun → `bunx`
- pnpm → `pnpm dlx`
- yarn → `yarn` (no `dlx`/`exec` needed for the common case — yarn resolves the binary)
- npm → `npx`
- no JS lockfile detected → `npx` (with a note that no JS manager was found)

- For each detected tool, the skill prints a one-line "Pending migrations may exist — run `<command>` if needed" message using the substituted command. It does not query the database to confirm pendingness; that requires credentials and is out of scope.

### Environment refresh: .env diff

- If `.env.example` is present, the skill compares its keys (left side of `=`) against `.env` (if present). Keys defined in `.env.example` but missing from `.env` are listed by name.
- The skill also checks for `.env.sample` and `.env.template` as fallback names.
- If `.env` does not exist but `.env.example` does, the skill reports "no local `.env` found — copy `.env.example` to `.env` and fill in values."
- Values are never read or printed. Only key names are compared.

### Environment refresh: Docker

- If any of `docker-compose.yml`, `docker-compose.yaml`, `compose.yml`, `compose.yaml` is present in the repo root, the skill prints a warning: "Compose detected — local images may be stale. Run `docker compose pull` and `docker compose build` if your stack expects current upstream images."
- The skill does not run `docker compose pull`, `docker compose build`, or any compose subcommand.

### Project-specific instructions

- The skill reads `CLAUDE.md` (project root) and `AGENTS.md` (if present) and looks for a section titled `Sync`, `Post-pull`, `After pulling`, or `Bootstrap` (case-insensitive). If found, the skill prints that section verbatim under a "Project-specific sync steps" header so the developer can follow it.
- The skill also reads `.cursorrules` and `.windsurfrules` if present and treats them the same way.
- Instructions found in these files are surfaced, never executed automatically.

### Final summary

- After all checks complete, the skill prints a single structured summary with sections in this fixed order:
  1. **Branch state** — old branch → `main`, old SHA → new SHA, number of new commits. If the developer chose **Stash and continue** at the dirty-tree prompt, this section also notes the stash ref and the `git stash pop` command to recover it.
  2. **Recent commits** — the `git log --oneline` block (capped at 20).
  3. **Dependencies refreshed** — list of ecosystems with install status (ran / skipped / not installed).
  4. **Migrations to consider** — list of detected migration tools and their recommended commands.
  5. **Environment variables** — missing keys by name, or "all keys present".
  6. **Docker** — compose warning if applicable.
  7. **Project-specific steps** — content extracted from `CLAUDE.md` / `AGENTS.md` / rules files.
  8. **Next step** — a one-line suggestion: "Ready to start. Run `/feature` to begin a new feature, or `git checkout <previous-branch>` to return to your prior work."

### Errors and exits

- Every external command exit is checked. Non-zero exits halt the skill, print the failing command and the stderr verbatim, and recommend the next step.
- The skill never proceeds past a fatal error (dirty tree, failed pull, failed install when the developer answered `yes`).
- The skill never writes to `.docs/`, never persists state between runs, and never modifies files in the repo other than what the install commands themselves modify.

## Constraints

- The skill runs in the developer's local Claude Code session and has only the tools declared in `allowed-tools`. It cannot install missing binaries (Node, Python, Ruby, etc.); it can only detect their absence and skip.
- All git operations must use the `gh` / `git` CLI per the project's `github-tool-preference` skill. The skill invokes `Skill(github-tool-preference)` before any `gh` call.
- The skill cannot run interactive commands that require TTY input beyond the simple yes/no/all prompts it controls itself. Tools that prompt mid-run (e.g. `bundle install` asking for credentials) must be configured non-interactively at the project level; the skill does not work around them.
- The skill must complete without persisting state across runs. There is no "last sync" timestamp file. The "previous main SHA" used for the change summary is the SHA recorded immediately before `git pull` in the current run — not a stored value from a prior session.
- The skill cannot run on operating systems without POSIX-style shell tooling (`grep`, `diff`, `find`). macOS and Linux are supported; Windows is not in scope.
- The skill respects the project's pinned tool versions implicitly by invoking the project's local binaries (`bin/rails`, `./node_modules/.bin/*`, `npx`). It does not pin or bootstrap tool versions itself.
- The skill must not be invoked from inside any pipeline agent. It is a developer-facing utility, not a pipeline step.

## Acceptance Criteria

- [ ] `.claude/skills/sync/SKILL.md` exists with `name: sync`, a clear `description`, `disable-model-invocation: true`, and an `allowed-tools` list that includes the Bash patterns and Read.
- [ ] The skill is documented in the repo's `README.md` next to `/feature` and `/pr-review`.
- [ ] Running `/sync` in a clean repo on `main` performs a fetch + fast-forward pull and prints the structured summary described in **Final summary**.
- [ ] Running `/sync` with uncommitted changes prints the list of dirty paths and prompts the developer with exactly two options: **Stash and continue** or **Let me handle it**. No "discard" option is offered.
- [ ] At the dirty-tree prompt, choosing **Stash and continue** runs `git stash push -u -m "sync: auto-stash <timestamp>"`, proceeds with the rest of the workflow, and the final summary's **Branch state** section names the stash ref and prints the `git stash pop` recovery command.
- [ ] At the dirty-tree prompt, choosing **Let me handle it** stops without running any `git checkout`, `git stash`, install, or migration command. The working tree is left exactly as it was.
- [ ] At the dirty-tree prompt, any input other than the two valid choices re-asks the prompt rather than defaulting to a destructive action.
- [ ] Running `/sync` outside a git repo prints a clear error and stops.
- [ ] Running `/sync` when `git pull --ff-only` fails prints the exact `git` stderr and stops; the local branch is not changed.
- [ ] In a repo with `package-lock.json`, `/sync` prompts to run `npm install` and (on `yes`) runs it. In a repo with both `package-lock.json` and `Gemfile.lock`, the skill prompts independently for each ecosystem.
- [ ] For each migration tool detected (Rails, Alembic, Prisma, Flyway, Django, Knex, Drizzle, Supabase), the summary's **Migrations to consider** section names the tool and its recommended command. No migration command is executed automatically.
- [ ] For Node-based migration tools (Prisma, Knex, Drizzle, Supabase CLI), the recommended command uses the detected JS package runner (`bunx`, `pnpm dlx`, `yarn`, or `npx`) rather than hardcoding `npx`.
- [ ] In a repo with `.env.example` listing keys `A`, `B`, `C` and a local `.env` defining only `A`, the summary reports `B` and `C` as missing by name. The `.env` file is not modified.
- [ ] In a repo with `docker-compose.yml`, the summary's **Docker** section prints the stale-image warning. No `docker` command is executed.
- [ ] In a repo whose `CLAUDE.md` contains a `## Sync` section, the summary's **Project-specific steps** section prints the content of that section verbatim.
- [ ] The summary's **Recent commits** section shows `git log --oneline --no-merges <pre-pull-sha>..HEAD` and is capped at 20 entries with a "+N more" footer when truncated.
- [ ] When no commits have landed on main since the previous local `main` HEAD, the **Recent commits** section prints "main is already up to date — no new commits since last sync."
- [ ] The skill never modifies `.env`, never runs `git reset`, `git clean`, `git checkout -- <path>`, or any migration command, and never invokes `docker compose pull` or `docker compose build`. The only `git stash` it ever runs is the explicit-consent stash from the dirty-tree prompt.
- [ ] Every external command is checked for non-zero exit; on failure the skill prints the failing command, the stderr, and stops without proceeding to later steps.

## Open Questions

None. All decisions called out by the user during Define are captured in **Requirements** above.
