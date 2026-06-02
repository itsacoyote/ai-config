---
name: sync
description: Bring the local checkout up to date with main before starting feature work — clean-tree check with optional stash, fetch and fast-forward pull, change summary, and detection-driven refresh of dependencies, migrations, .env keys, and Docker. Developer-invoked; never runs destructive git or auto-applies migrations.
disable-model-invocation: true
allowed-tools: Read Bash(git *) Bash(gh *) Bash(npm *) Bash(yarn *) Bash(pnpm *) Bash(bun *) Bash(bundle *) Bash(uv *) Bash(poetry *) Bash(pipenv *) Bash(go *) Bash(cargo *) Bash(composer *) Bash(mix *) Bash(docker *) Bash(diff *) Bash(cat *) Bash(ls *) Bash(find *) Bash(grep *)
---

# Sync

## What this does

This skill is invoked as `/sync` by the developer. It is a pre-feature ritual that brings the local checkout up to date with `main` before any new work begins. The workflow is: Preflight → Branch switch and pull → Change summary → Environment refresh (packages → migrations → `.env` diff → Docker) → Project-specific instructions → Final summary.

The skill never performs destructive git operations, never auto-applies migrations, never modifies `.env`, and never invokes `docker compose pull` or `docker compose build`. It is a developer-invoked utility — not a pipeline step — and persists no state between runs.

## Preflight

### Verify inside a git repo

Run:

```
git rev-parse --is-inside-work-tree
```

If this exits non-zero, print: "Not inside a git repository. Navigate to a git repo root and rerun `/sync`." and stop.

### Detect the main branch

Detect the project's main branch by checking, in order:

1. `git config init.defaultBranch` — use the value if non-empty.
2. `git rev-parse --abbrev-ref origin/HEAD` — strip the `origin/` prefix if non-empty.
3. Fall back to `main`.

Print the detected branch name: "Detected main branch: `<branch>`."

### Record the current branch

Run `git rev-parse --abbrev-ref HEAD` and store the result as `<previous-branch>` for the final summary.

### Clean-tree check

Run:

```
git status --porcelain
```

If the output is empty, the working tree is clean — proceed to ## Branch switch and pull.

If the output is non-empty, print the list of dirty paths and show the following prompt:

```
Your working tree has uncommitted changes:

<list of dirty paths from `git status --porcelain`>

How do you want to proceed?

  s  Stash and continue — run `git stash push -u -m "sync: auto-stash <timestamp>"`,
     then proceed with the rest of the sync. The stash ref will be shown in the
     final summary so you can `git stash pop` to recover it.

  h  Let me handle it — stop now without running any further command. Commit
     or discard the changes yourself, then rerun `/sync`.
```

**Accepted inputs:**

| Input | Effect |
|-------|--------|
| `s` / `stash` | Run `git stash push -u -m "sync: auto-stash <timestamp>"`. Capture the stash ref from stdout. Proceed to ## Branch switch and pull. Surface the stash ref and the `git stash pop` recovery command in the final summary's **Branch state** section. |
| `h` / `handle` | Stop immediately. Do not run `git switch`, `git stash`, install, migration, or any further command. Leave the working tree exactly as it was. |
| anything else | Re-prompt the current question without advancing. Do not default to either option. Never run a destructive recovery (no `git reset --hard`, no `git clean`, no `git checkout -- <path>`) regardless of input. |

If `git stash` itself exits non-zero (e.g. partial-merge state, unmerged paths), print the `git` stderr verbatim and stop. Do not retry. Do not attempt any other recovery.

## Branch switch and pull

Check out the detected main branch:

```
git switch <main>
```

Capture the pre-pull SHA:

```
git rev-parse <main>
```

Store as `<pre-pull-sha>`.

Before the next `git` operation, invoke `Skill(github-tool-preference)` to confirm `git` is the right tool.

Then run:

```
git fetch origin
```

Before the pull, invoke `Skill(github-tool-preference)` again to confirm `git` is the right tool.

Then run:

```
git pull --ff-only origin <main>
```

If `git pull --ff-only` exits non-zero (non-fast-forward, network error, auth failure), print the exact `git` stderr verbatim and stop. Do not retry with `--rebase` or `--no-ff`. The local branch is left unchanged.

After a successful pull, capture:

```
git rev-parse HEAD
```

Store as `<post-pull-sha>`.

## Change summary

Run:

```
git log --oneline --no-merges <pre-pull-sha>..HEAD
```

- If the output is empty, print: "main is already up to date — no new commits since last sync."
- If there are 20 or fewer commits, print all of them.
- If there are more than 20 commits, print the most recent 20 and append a `+<N> more` footer where `<N>` is the count beyond 20.

Carry the commit list forward to the final summary's **Recent commits** section.

## Environment refresh: package managers

Detect each package manager independently by lockfile presence. A polyglot repo runs every applicable install. Before running each install, check whether the binary is on `PATH` — if not, mark the ecosystem as **not installed** and skip without prompting.

### JS package manager and runner detection

The detected JS manager also determines the **JS package runner** used to prefix Node-based migration tool commands in ## Environment refresh: migrations.

Precedence when multiple JS lockfiles exist (highest wins):

| Lockfile | Manager | Install command | Runner prefix |
|---|---|---|---|
| `bun.lockb` or `bun.lock` | bun | `bun install` | `bunx` |
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` | `pnpm dlx` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` | `yarn` |
| `package-lock.json` | npm | `npm install` | `npx` |

If no JS lockfile is detected, default the runner prefix to `npx` and note that no JS manager was found.

### Full lockfile detection table

| Lockfile | Tool | Install command |
|---|---|---|
| `package-lock.json` | npm | `npm install` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` |
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `bun.lockb` / `bun.lock` | bun | `bun install` |
| `Gemfile.lock` | bundler | `bundle install` |
| `requirements.txt` | pip | surfaced only — see note below |
| `uv.lock` | uv | `uv sync` |
| `poetry.lock` | poetry | `poetry install` |
| `Pipfile.lock` | pipenv | `pipenv install` |
| `go.sum` | go | `go mod download` |
| `Cargo.lock` | cargo | `cargo fetch` |
| `composer.lock` | composer | `composer install` |
| `mix.lock` | mix | `mix deps.get` |

**pip note:** `requirements.txt` is always surfaced as a recommendation only and never auto-run, because the right environment manager (venv, conda, system) is project-dependent. Show it in the final summary's **Dependencies refreshed** section as `pip: surfaced only`.

### Per-ecosystem install confirmation prompt

For each detected ecosystem (except pip), show this prompt before running the install. Replace `<ecosystem>` and `<command>` per detected lockfile.

```
Detected <ecosystem> lockfile. Run `<command>` now?

  yes   Run the install for this ecosystem and continue.
  no    Skip this ecosystem. Continue to the next one.
  all   Run the install for this ecosystem and every remaining detected ecosystem
        without further prompts.
```

**Accepted inputs:**

| Input | Effect |
|-------|--------|
| `yes` / `y` | Run `<command>`. Check the exit code. On non-zero, print the stderr and stop. On zero, mark this ecosystem as **ran** in the final summary's **Dependencies refreshed** section. |
| `no` / `n` | Skip without running. Mark this ecosystem as **skipped** in the final summary. Continue to the next detected ecosystem. |
| `all` / `a` | Run `<command>` for this ecosystem and every remaining detected ecosystem in turn without re-prompting. Each install's exit is still checked; a non-zero exit stops the skill at that command. |
| anything else | Re-prompt the current question without advancing. |

If the binary implied by `<command>` is not on `PATH`, do not show this prompt for that ecosystem. Mark it as **not installed** in the final summary and continue to the next.

## Environment refresh: migrations

Detect migration tools by the presence of known files or directories. Migrations are never run automatically — each detected tool generates a one-line recommendation in the final summary's **Migrations to consider** section.

For Node-based migration tools (Prisma, Knex, Drizzle, Supabase), the recommended command is prefixed with the **detected JS package runner** from ## Environment refresh: package managers. Non-Node tools (Rails, Alembic, Flyway, Django) use their own runners.

The table below shows commands as they appear in an npm-detected project; the `npx` prefix is replaced with the project's detected runner at print time.

| Signal | Tool | Recommended command (with detected JS runner) |
|---|---|---|
| `bin/rails` or `config/application.rb` | Rails | `bin/rails db:migrate` |
| `alembic.ini` | Alembic | `alembic upgrade head` |
| `prisma/schema.prisma` | Prisma | `<js-runner> prisma migrate deploy` (or `dev`, developer's choice) |
| `flyway.conf` or `flyway/` | Flyway | `flyway migrate` |
| `manage.py` with `django` in any requirements file | Django | `python manage.py migrate` |
| `knexfile.js` / `knexfile.ts` | Knex | `<js-runner> knex migrate:latest` |
| `drizzle.config.ts` / `drizzle.config.js` | Drizzle | `<js-runner> drizzle-kit migrate` |
| `supabase/migrations/` | Supabase | `supabase db push` (or `<js-runner> supabase db push` if installed via the JS package manager) |

**`<js-runner>` substitution rules:**

- bun detected → `bunx`
- pnpm detected → `pnpm dlx`
- yarn detected → `yarn`
- npm detected → `npx`
- no JS lockfile detected → `npx` (note that no JS manager was found)

Print one line per detected tool: "Pending migrations may exist — run `<command>` if needed." Do not query the database to confirm pendingness.

## Environment refresh: .env diff

Check for `.env.example` first, then `.env.sample`, then `.env.template` as fallback names.

If none of these files are present, skip this section.

If an example file is present but no `.env` exists, report: "No local `.env` found — copy `.env.example` to `.env` and fill in values."

If both an example file and `.env` are present, compare keys (left side of `=`) only. List any keys defined in the example file but absent from `.env` by name in the final summary's **Environment variables** section. Values are never read or printed.

If all keys are present, report: "All keys present."

## Environment refresh: Docker

Check for any of these files in the repo root: `docker-compose.yml`, `docker-compose.yaml`, `compose.yml`, `compose.yaml`.

If one is present, print the following warning in the final summary's **Docker** section:

"Compose detected — local images may be stale. Run `docker compose pull` and `docker compose build` if your stack expects current upstream images."

Do not run `docker compose pull`, `docker compose build`, or any other compose subcommand.

If no compose file is present, report: "No compose file detected."

## Project-specific instructions

Read each of the following files if present: `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`.

In each file, look for a section heading (case-insensitive) that matches any of: `Sync`, `Post-pull`, `After pulling`, `Bootstrap`.

If a matching section is found, print its content verbatim under a "Project-specific sync steps" header in the final summary's **Project-specific steps** section.

If no matching section is found in any of the files, report: "No project-specific sync steps found in CLAUDE.md, AGENTS.md, .cursorrules, or .windsurfrules."

Do not execute any instructions found in these files automatically. Surface them for the developer to follow.

## Final summary

After all checks complete, print the following structured summary. Section ordering is contractual — do not reorder.

```
═══════════════════════════════════════════════════════════════════
  Sync summary
═══════════════════════════════════════════════════════════════════

1. Branch state
   <previous-branch> → <main-branch>
   <pre-pull-sha> → <post-pull-sha>
   <N> new commits on <main-branch>.
   [If stashed:] Stashed uncommitted changes as <stash-ref>.
                 Recover with: git stash pop

2. Recent commits
   <git log --oneline --no-merges output, capped at 20 lines>
   [If truncated:] +<N> more
   [If no new commits:] main is already up to date — no new commits since last sync.

3. Dependencies refreshed
   <ecosystem>: ran | skipped | not installed
   <ecosystem>: ran | skipped | not installed
   [Repeat per detected ecosystem. pip is always shown as "surfaced only".]

4. Migrations to consider
   <tool>: <recommended command using detected <js-runner> where applicable>
   <tool>: <recommended command>
   [Repeat per detected migration tool. None of these were executed.]

5. Environment variables
   <list of keys defined in .env.example but missing from .env, by name only>
   [If .env is missing entirely:] No local .env found — copy .env.example to .env and fill in values.
   [If all keys present:] All keys present.

6. Docker
   [If compose file detected:] Compose detected — local images may be stale.
   Run `docker compose pull` and `docker compose build` if your stack expects
   current upstream images.
   [If no compose file:] No compose file detected.

7. Project-specific steps
   [Verbatim content of the matching section from CLAUDE.md / AGENTS.md /
    .cursorrules / .windsurfrules, if any. If none, "No project-specific
    sync steps found in CLAUDE.md, AGENTS.md, .cursorrules, or .windsurfrules."]

8. Next step
   Ready to start. Run `/feature` to begin a new feature, or
   `git switch <previous-branch>` to return to your prior work.

═══════════════════════════════════════════════════════════════════
```

## Errors and exits

Every external command's exit code is checked. If any command exits non-zero, the skill:

1. Prints the failing command verbatim.
2. Prints the stderr verbatim.
3. Stops without proceeding to later steps.

The skill never proceeds past a fatal error (dirty tree choice of `h`, failed `git pull --ff-only`, failed install when the developer answered `yes`).

## What this skill will not do

These are hard constraints. The wording matters because there is no enforcement layer below this prose.

- Do not commit uncommitted work. The only mutation ever performed on a dirty working tree is `git stash push -u`, and only after the developer explicitly chooses option `s` at the dirty-tree prompt.
- Do not discard or force-reset uncommitted work. Never run `git reset --hard`, `git clean -fdx`, or `git checkout -- <path>` under any circumstance.
- Do not auto-apply database migrations. Migrations are surfaced as recommended commands; none are executed without the developer running them manually.
- Do not modify `.env`. Missing keys are reported by name only; the file is never written, copied, or filled.
- Do not rebuild Docker images. Never run `docker compose pull`, `docker compose build`, or any other compose subcommand. Only the stale-image warning is printed.
- Do not retry a failed `git pull --ff-only` with `--rebase` or `--no-ff`. Print the stderr and stop.
- Do not handle merge conflicts on `main`. If `git pull` fails, stop and print the error.
- Do not support remotes other than `origin` or base branches other than the project's configured main branch.
- Do not support non-git version control systems (Mercurial, SVN, jj).
- Do not wire this skill into the `/feature` pipeline or invoke it from any pipeline agent. It is a developer-facing utility only.
- Do not persist state between runs. There is no "last sync" timestamp file. The pre-pull SHA is captured within the current run — not stored from a prior session.
- Do not write to `.docs/`. The skill never creates, modifies, or deletes files in the feature folder.
- Do not install missing binaries. If a required tool (Node, Python, Ruby, etc.) is not on `PATH`, skip its ecosystem with a "not installed" note.
- Do not run on operating systems without POSIX-style shell tooling. macOS and Linux are supported; Windows is not in scope.
