# AI Config

## What this is

A portable library of [Claude Code](https://docs.claude.com/en/docs/claude-code) **skills, agents, rules, and references**. It gives Claude a structured, manual feature-development workflow — **Define → Research → Plan → Implement → Validate → Document** — plus a deep bench of engineering-quality skills (testing, security, API design, frontend, git, docs).

Run `link.sh` once and every project on the machine gets the workflow; after that,
`git pull` is the update (see [Installing the library](docs/install.md#installing-the-library)).

---

## Quick start

```bash
bash link.sh --dry-run   # preview every link and delete
bash link.sh             # link the library into the harness homes
/define                  # in Claude Code: start your first feature
```

**Before `bash link.sh`:** it deletes what it did not link inside the managed directories. Archive your existing harness homes and read every `delete` line of the dry run first. See [Before the first run](docs/install.md#before-the-first-run).

Run `link.sh` from the primary checkout, on `main`.

---

## The workflow

Six steps, each a skill you invoke when you're ready to move on. The `feature-workflow` skill is the in-repo map of all of this.

```text
Define ──▶ Research ──▶ Plan ──▶ Implement ──▶ Validate ──▶ Document
(spec +    (study the   (file    (build it    (senior +    (docs +
 approval)  codebase)    map +    task by      QA review)   PR ready)
                         tasks)   task)
```

| Step | Invoke | What it produces |
|------|--------|------------------|
| **Define** | `/define` | An approved spec and the feature branch |
| **Research** | `/research` | Findings: reuse, patterns, risks — fan-out across parallel lens agents, synthesized |
| **Plan** | `planning-and-task-breakdown` | A file map + dependency-ordered tasks with named tests |
| **Implement** | `incremental-implementation` | The change, built task by task, tests passing, committed |
| **Validate** | `/validate` | Reviews passed (spawns the `senior-review` + `security-scan` + `design-review` (conditional, frontend) + `qa-review` agents), findings fixed |
| **Document** | `/document` | Docs updated, PR description written, PR readied |

Beads is required for state and task tracking. Details, the autorun orchestrator, and a CLAUDE.md snippet for your own projects are in [docs/workflow.md](docs/workflow.md).

---

## What's inside

- **Workflow steps:** `define`, `research`, `planning-and-task-breakdown`, `incremental-implementation`, `validate`, `document`, `feature-workflow`, `autorun`, `wayfinder`
- **Research support:** `analyze-code`, `edge-cases-and-risks`, `find-patterns`, `onboard`, `web-search`
- **Review & quality:** `pr-review`, `plan-review`, `senior-review`, `efficiency-review`, `design-review`, `qa-review`, `security-scan`, `security-and-hardening`, `writing-tests`, `project-checks`, `debugging-and-error-recovery`
- **Engineering craft:** `api-and-interface-design`, `prototype`, `frontend-ui-engineering`, `impeccable`, `documentation-and-adrs`, `deprecation-and-migration`, `ci-cd-and-automation`, `browser-testing-with-devtools`
- **Technology specialists:** `postgres-pro`, `playwright-expert`, `rails-expert`
- **Git, PRs & meta:** `branch-names`, `git-commit`, `git-workflow-and-versioning`, `create-pr`, `sync`, `standup`, `setup-beads`, `bd-cleanup`, `wait-what`, `writing-skills`, `doubt-driven-development`
- **Agents:** `plan-review`, `senior-review`, `efficiency-review`, `security-scan`, `design-review`, `qa-review`, `implementer`, `research-reuse`, `research-patterns`, `research-risks`, `research-libraries`, `research-history`, `pr-context`, `pr-security`, `pr-tests`
- **Rules:** `commenting`, `github-tool-preference`, `typescript-tips`
- **References:** `beads.md`, `diff-scope.md`, `review-agent-contract.md`, `testing-patterns.md`, `accessibility-checklist.md`, `performance-checklist.md`, `security-checklist.md`, `code-smells.md`

Descriptions for each, and what `/cmd` marks, are in the [catalog](docs/catalog.md).

---

## Worktree CLIs

### `clwt` — worktree CLI

`claude/scripts/clwt` manages this repository's git worktrees and launches Claude Code
sessions in them. Install, commands, and behavior are in [docs/clwt.md](docs/clwt.md).

### `cwt` — Codex worktree CLI

`codex/scripts/cwt` is an independent Codex port of `clwt` with the same ten commands and
managed worktree root. Run it from your shell, not from inside a Codex session. See the
[Codex cwt guide](codex/README.md#cwt--worktree-cli) and [docs/harnesses.md](docs/harnesses.md).

### `pwt` — Pi worktree CLI

`pi/scripts/pwt` is the developer-facing Pi launcher for the same ten-command worktree
lifecycle. Run it from your shell, not from inside a Pi session. See the
[Pi pwt guide](pi/README.md#pwt--worktree-cli) and [docs/harnesses.md](docs/harnesses.md).

---

## Harnesses

- **[`claude/`](claude/)** — the Claude Code workflow library, linked globally; `claude/` is
  canonical for this repo's own work. Details in [docs/harnesses.md](docs/harnesses.md).
- **[`agents/`](agents/)** — portable Agent Skills shared by Codex and Pi. Details in
  [docs/harnesses.md](docs/harnesses.md).
- **[`codex/`](codex/)** — Codex-specific guidance and tooling. Details in
  [docs/harnesses.md](docs/harnesses.md).
- **[`pi/`](pi/)** — Pi-specific guidance and tooling. Details in
  [docs/harnesses.md](docs/harnesses.md).

---

## Repo layout

```text
link.sh            # human-run: symlink the library into the harness homes (ADR 0013)
tests/             # link-test.sh, the self-contained suite for link.sh
claude/
├── CLAUDE.md              # personal user file, linked as ~/.claude/CLAUDE.md
├── skills/                # the skills above (one folder each, SKILL.md + optional files)
├── agents/                # the review/implementer agents above (one .md each)
├── rules/                 # always-on conventions
├── references/            # shared knowledge skills point to
├── hooks/                 # PreToolUse and SessionStart hooks
├── scripts/               # clwt, worktree-status.sh, wt-status.sh, and their tests
├── settings.json          # settings TEMPLATE: hook lines to register by hand (not live config)
└── statusline-command.sh  # statusline script, linked into ~/.claude
agents/
├── AGENTS.md              # portable personal user file, linked as ~/.codex/AGENTS.md
└── skills/                # shared portable skills, linked into ~/.agents/skills
codex/             # Codex guidance and rules plus cwt, completion, and tests
pi/                # Pi personal global context plus pwt, completion, tests, and guide
docs/              # topic detail: workflow, catalog, install, clwt, harnesses, decisions
archive/           # the previous automated pipeline, kept for reference
AGENTS.md          # how to work IN this repo (read natively by all three harnesses)
```

The `archive/` directory holds the previous fully-automated pipeline (the `/feature` orchestrator, `context.yaml`, step agents) — preserved for reference while the workflow is rebuilt manually.

---

## Docs

- [docs/workflow.md](docs/workflow.md) — the workflow in detail, autorun, a CLAUDE.md snippet
- [docs/catalog.md](docs/catalog.md) — descriptions for every skill, agent, rule, and reference
- [docs/install.md](docs/install.md) — installing the library, the private directory, hooks, MCP servers
- [docs/clwt.md](docs/clwt.md) — the `clwt` worktree CLI
- [docs/harnesses.md](docs/harnesses.md) — Claude, Codex, Pi, and the shared `agents/` skills
- [docs/decisions/](docs/decisions/) — architectural decisions and their rationale
