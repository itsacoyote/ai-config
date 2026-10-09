# The workflow

It runs **manual by default** — you drive each step — with an optional **supervised orchestrator** (`autorun`) that runs the post-Define steps for you, implementing one task at a time in fresh subagents while keeping permissions on and stopping at a ready-for-review PR. There's deliberately no *unattended* runner yet — the human stays in the loop at two gates (Define and the PR) and approves actions as they happen.

Run the steps in order; advance only when the previous step's output is in hand. **Every step ends by recommending the next move — the default next step, plus situational skills its output signals (e.g. `prototype` after a Define that left UI behavior fuzzy) — and waits for your explicit go before starting it** (`autorun` is the opt-out). Skip the whole thing for trivial changes — it earns its keep on real features where a missed requirement or skipped review is expensive. Start with `feature-workflow` if you want the full map.

## Tracking: requires beads

State and tasks flow through **[beads](https://github.com/gastownhall/beads)** (the `bd` CLI) — it is required. Workflow skills hard-stop and redirect to `setup-beads` when beads is absent. A feature becomes an epic, plan tasks become child issues, review findings become issues. There is no `.docs/` folder or `context.yaml` — beads is the system of record.

Run the **`setup-beads`** skill to install `bd` and initialize an isolated local database (nothing committed by default). The session-start gate hook (`claude/hooks/beads-gate.sh`, installed to `~/.claude/hooks`) stays silent where beads is absent and injects current task context where it's present.

To orient Claude to the workflow in a target project, paste the snippet below into that
project's `CLAUDE.md` and adapt it. Optionally copy `.mcp.json` (see
[MCP servers](install.md#mcp-servers)); then start with `/define` (or read `feature-workflow`
first).

## Example: paste into your project's `CLAUDE.md`

```markdown
## Development workflow

This project uses a manual feature workflow: **Define → Research → Plan →
Implement → Validate → Document**. Run each step deliberately — there is no
orchestrator. See the `feature-workflow` skill for the map.

- Start a feature with `/define` (it writes the spec and creates the branch).
- Then: `/research` → `planning-and-task-breakdown` → `incremental-implementation`
  → `/validate` → `/document`.
- `/validate` spawns the `senior-review`, `security-scan`, and `qa-review` agents for independent review.
- Match rigor to the change — skip the workflow for trivial fixes.

## Task tracking

[beads](https://github.com/gastownhall/beads) is required — the workflow records
features/tasks/findings as beads issues and hard-stops when beads is absent. Run
the `setup-beads` skill to install and initialize it. See
`~/.claude/references/beads.md`.

## Conventions

- Conventional Commits for all commits and PR titles; no AI-attribution trailers
  (the `git-commit` skill enforces this).
- Prefer the `gh`/`git` CLI for git and GitHub operations.
```
