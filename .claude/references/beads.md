# Beads Integration Reference

Single source of truth for how the workflow skills (`define`, `research`,
`planning-and-task-breakdown`, `plan-review`, `incremental-implementation`, `efficiency-review`,
`senior-review`, `security-scan`, `design-review`, `qa-review`, `validate`, `document`, `standup`)
use **beads** as the project's task tracker and system of record. Beads is a **hard requirement**
for the workflow — skills point here instead of restating the model, and when the beads model
changes, this file is the only edit.

Beads: <https://github.com/gastownhall/beads>. CLI is `bd`. To install and
initialize it in a project, use the **`setup-beads`** skill.

## How beads stores data

`bd` keeps issues in an **embedded [Dolt](https://www.dolthub.com/) database** under
`.beads/embeddeddolt/`, running in-process — there is no daemon. `bd init` writes
`.beads/config.yaml` plus a nested `.beads/.gitignore` that excludes the Dolt data
dirs. Any `.beads/issues.jsonl` is an **export for interchange — not the source of
truth.** `dolt.auto-commit` (on by default) makes a *local* Dolt commit after writes
— internal versioning, not a git commit or network push; `dolt.auto-push` is off by
default. In the recommended personal/local setup, `.beads/` is git-ignored entirely
and nothing syncs anywhere.

## Beads is required (read this first)

Beads is a **hard requirement** for the workflow. Every workflow skill assumes beads is
present and does not fall back to conversational tracking.

### Preflight gate

Before doing any workflow work, every skill must verify beads is set up:

```bash
test -d .beads && command -v bd >/dev/null 2>&1
```

If the check fails, **stop** — do not proceed without beads — and tell the user to run
the `setup-beads` skill, then retry.

The canonical copy-pasteable block for embedding in step skills:

> **Preflight (required).** Before doing any workflow work, verify beads is set up:
> `test -d .beads && command -v bd >/dev/null 2>&1`. If it is NOT, **stop** — do not
> proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

`setup-beads` and `bd-cleanup` are exempt — they are the bootstrap and maintenance paths
and cannot require what they install.

## The feature model

A feature maps onto the issue graph like this:

| Workflow concept | Beads representation |
|---|---|
| A feature / spec | An **epic** issue (`bd-a3f8`) created at **Define** |
| Research findings | Notes/comments on the epic (or a `research` child issue) |
| Plan tasks | **Child issues** of the epic created at **Plan**, with dependencies |
| Implementation progress | Child issues moved to `in_progress` then `closed` at **Implement** |
| Review / QA findings | Issues (linked to the epic, or to the task they concern) created at **Validate** |
| Documentation follow-ups | Issues if anything is deferred at **Document** |

Status vocabulary: `open` → `in_progress` → `blocked` → `closed`. Priority is `-p 0`
(highest) … `-p 3`. Type is `-t` (`task`, `feature`, `epic`, …).

## Command cheat sheet

```bash
bd ready                               # list unblocked issues ready to start
bd create "Title" -p 1 -t epic         # create an issue (epic, feature, or task)
bd create "Task title" -p 1 -t task --parent <epic-id>   # create a child task
bd dep add <child-id> <parent-id>      # express a blocking/ordering dependency
bd update <id> --claim                 # claim/start an issue (sets assignee + in_progress, idempotent)
bd close <id>                          # complete an issue (or: bd update <id> --status closed)
bd show <id>                           # view an issue's details
bd list --json                         # list issues (use --json for programmatic reads)
```

The CLI is large and evolving — **verify exact flags with `bd <command> --help`
before relying on them.** If a flag here has changed, prefer what `--help` reports.

## Operational notes (driving bd from scripts and agents)

Hard-won details when an agent (not a human) runs `bd`:

- **Capturing a new issue's ID — don't scrape human output.** `bd create` prints a
  decorated message; when `--parent` is set it also echoes the **parent** ID, so a naive
  `grep -oE 'prefix-[a-z0-9]+' | head -1` grabs the **wrong** ID. Use one of:
  ```bash
  ID=$(bd create "Title" -t task --parent <epic> --silent)   # prints ONLY the new ID
  ID=$(bd create "Title" -t task --json | jq -r '.id')        # or parse JSON
  ```
- **Child IDs are hierarchical.** `--parent ai-config-c78` yields children
  `ai-config-c78.1`, `ai-config-c78.2`, … (dot suffixes), not flat IDs.
- **Dependency direction:** `bd dep add <blocked-id> <blocker-id>` — the **first** depends
  on (is blocked by) the second. Equivalent inverse: `bd dep <blocker> --blocks <blocked>`.
  `bd dep cycles` checks for cycles; self/cyclic deps are rejected.
- **`bd ready` lists the epic itself** (a container with no blockers) alongside real work.
  When looping over implementable tasks, **skip the epic / non-leaf issues**.
- **`bd ready` excludes `in_progress` (and `blocked`/`deferred`).** A task you've `--claim`ed
  but not yet `bd close`d will **not** reappear in `bd ready`. So in a claim→work→close loop,
  an interruption *between* claim and close strands the task: on resume it's invisible to
  `bd ready`. **Reclaim it explicitly** — sweep `bd list --status in_progress` (scoped to the
  epic) and re-dispatch those before draining `bd ready`. (This is the resumability contract
  the `autorun` skill's resume preamble implements.)
- **Materialize a whole plan atomically:** `bd create --graph <plan.json>` creates many
  issues *and* their dependencies from one JSON file — cleaner than N creates + N `dep add`s.
- **Long bodies:** pass `--body-file <f>` / `--stdin` (and `--acceptance`, `--design`) to
  avoid shell-escaping multi-line markdown; attach notes later with `bd comment <id> --file`.
- **When `.beads/` grows large**, use the `bd-cleanup` skill — it reclaims space
  (`bd doctor --fix`, Dolt GC, compaction) and prunes old closed issues safely (dry-run first).
  The usual cause is Dolt commit history, not issue count, so `bd admin compact --dolt`
  (non-destructive) is typically the fix.

## How each step uses beads

- **Define** → create the feature **epic** with the spec as its body; record the
  approval in the epic.
- **Research** → attach findings to the epic (comment or `research` child issue).
- **Plan** → create one **child task** per plan task, with `bd dep add` for ordering;
  the file map and TDD test names go in each task's body.
- **Plan → Implement gate (`plan-review`)** → read-only: reads the spec from the epic
  (`bd show <epic>`) and the tasks / file map from its children; reports findings (it never
  mutates issues). Actionable findings drive plan revisions (the orchestrator or human edits
  the tasks / file map and re-reviews); a fundamentally wrong approach sends the work back to
  Define.
- **Implement** → `bd ready` to find the next task, `bd update <id> --claim` before
  starting it, `bd close <id>` once its commit lands. `efficiency-review` findings during
  implementation are addressed in-flight; no separate beads issues are created for them.
- **Validate** → file an issue per unresolved finding from the reviewers
  (`senior-review`, `security-scan`, `design-review` on frontend changes, `qa-review`);
  close them as fixes land. The validation summary goes on the epic.
- **Document** → file issues for any documentation deliberately deferred; otherwise
  close out the epic when the PR is ready.
- **Standup** → read-only: `bd ready` for what's next, plus closed/in-progress issues
  for what's done and in flight. Never mutates.

## Guardrails

- **Never run `bd` until the preflight passes.** Run the detection snippet first. If
  beads is not set up, redirect the user to the `setup-beads` skill — do not proceed.
- **Never auto-close or auto-transition** issues the user owns without surfacing it.
- **Don't invent issue IDs.** Read them back from `bd` output (e.g. capture the ID
  printed by `bd create`).
- If a `bd` command fails, **report the stderr to the user** — do not silently swallow
  the error or continue as though the command succeeded. Surface the failure and let the
  user decide how to proceed.
- In the recommended personal/local setup there is **no remote and no push** — don't
  run `bd dolt push` / `bd dolt remote add` unless the project was deliberately set up
  in tracked mode (see `setup-beads`).
