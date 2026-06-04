# Beads Integration Reference

Single source of truth for how the workflow skills (`define`, `research`,
`planning-and-task-breakdown`, `incremental-implementation`, `senior-review`,
`qa-review`, `validate`, `document`) use **beads** as the project's task tracker
and system of record. Skills point here instead of restating the model — when the
beads model changes, this file is the only edit.

Beads: <https://github.com/gastownhall/beads>. CLI is `bd`. Data lives in `.beads/`.

## Dual-mode contract (read this first)

Every workflow skill runs in one of two modes, decided by whether beads is set up:

```bash
# Detection — beads is active only if BOTH are true:
test -d .beads && command -v bd >/dev/null 2>&1 && echo "beads-enhanced" || echo "standalone"
```

- **Standalone (default).** `.beads/` is absent or `bd` is not installed. The skill
  works fully **conversationally** — it presents its output (spec, task list,
  findings, summary) in the session for the user to act on. **Never run `bd` in this
  mode.** Nothing is lost: the work is real, it's just tracked in the conversation
  and git instead of beads.
- **Beads-enhanced.** `.beads/` exists and `bd` is on PATH. The skill additionally
  records its output as beads issues using the model below.

A skill must never block, error, or degrade in quality because beads is missing.
Beads is an enhancement, not a dependency.

## The feature model

When beads is active, a feature maps onto the issue graph like this:

| Workflow concept | Beads representation |
|---|---|
| A feature / spec | An **epic** issue (`bd-a3f8`) created at **Define** |
| Research findings | Notes/comments on the epic (or a `research` child issue) |
| Plan tasks | **Child issues** of the epic (`bd-a3f8.1`, …) created at **Plan**, with dependencies |
| Implementation progress | Child issues claimed and closed at **Implement** |
| Review / QA findings | Issues (linked to the epic, or to the task they concern) created at **Validate** |
| Documentation follow-ups | Issues if anything is deferred at **Document** |

Status vocabulary: `open` → `in_progress` → `blocked` → `closed`. Priority is `-p 0`
(highest) … `-p 3`.

## Command cheat sheet

```bash
bd create "Title" -p 1                 # create an issue (epic or task)
bd create "Task title" -p 1 --parent <epic-id>   # create a child task
bd dep add <child-id> <parent-id>      # express a blocking/ordering dependency
bd ready                               # list unblocked issues ready to start
bd update <id> --claim                 # claim an issue (sets in_progress)
bd update <id> --status closed         # close an issue
bd show <id>                           # view an issue's details
```

Verify exact flags with `bd --help` / `bd <subcommand> --help` before relying on
them — the CLI evolves, and this reference may lag a version.

## How each step uses beads (when active)

- **Define** → create the feature **epic** with the spec as its body; record the
  approval in the epic.
- **Research** → attach findings to the epic (comment or `research` child issue).
- **Plan** → create one **child task** per plan task, with `bd dep add` for ordering;
  the file map and TDD test names go in each task's body.
- **Implement** → `bd ready` to find the next task, `bd update <id> --claim`, do the
  work, `bd update <id> --status closed` when its commit lands.
- **Validate** → file an issue per unresolved review/QA finding; close them as fixes
  land. The validation summary goes on the epic.
- **Document** → file issues for any documentation deliberately deferred; otherwise
  close out the epic when the PR is ready.

## Guardrails

- **Never run `bd` until `.beads/` exists.** Detect first (snippet above).
- **Never auto-close or auto-transition** issues the user owns without surfacing it.
- **Don't invent issue IDs.** Read them back from `bd` output (e.g. capture the ID
  printed by `bd create`).
- If a `bd` command fails, report the stderr and fall back to standalone (present the
  result conversationally) — don't halt the workflow.
- Beads is **not set up in this project yet** as of this writing, so in practice the
  workflow runs standalone today. These hooks activate automatically once `.beads/`
  exists.
