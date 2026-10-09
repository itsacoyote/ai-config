# AI Config

A portable library of [Claude Code](https://docs.claude.com/en/docs/claude-code) **skills, agents, rules, and references**. It gives Claude a structured, manual feature-development workflow — **Define → Research → Plan → Implement → Validate → Document** — plus a deep bench of engineering-quality skills (testing, security, API design, frontend, git, docs).

Run `link.sh` once and every project on the machine gets the workflow; after that,
`git pull` is the update (see [Installing the library](docs/install.md#installing-the-library)).

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

## `clwt` — worktree CLI

`claude/scripts/clwt` manages this repository's git worktrees and launches Claude Code
sessions in them. Install, commands, and behavior are in [docs/clwt.md](docs/clwt.md).

---

## `cwt` — Codex worktree CLI

`codex/scripts/cwt` is an independent Codex port of `clwt`. It preserves the same ten
commands and the shared `~/github/.worktrees/<owner>/<repo>/` managed root, but launches
Codex, exports `CWT_REPO_ROOT`, and passes Codex's native `--yolo` flag. Run its launching
commands from your shell, not from inside an active Codex session. Unlike `clwt` and `pwt`,
`cwt` does not name sessions: Codex has no launch-time session-name option.

```bash
codex/scripts/cwt install
```

Installation, Bash/zsh completion, command behavior, safety boundaries, and the manual
test command are documented in the [Codex cwt guide](codex/README.md#cwt--worktree-cli).
The independent-port rationale is recorded in
[ADR 0011](docs/decisions/0011-cwt-worktree-cli.md).

## `pwt` — Pi worktree CLI

`pi/scripts/pwt` is the developer-facing Pi launcher for the same ten-command worktree
lifecycle. It shares the managed `~/github/.worktrees/<owner>/<repo>/` root with `clwt`
and `cwt`, physically enters the selected checkout, exports `PWT_REPO_ROOT`, and executes
Pi. Run its launching commands from your shell, not from inside an active Pi session.

Pi has no yolo mode. For pull requests, `pwt` keeps context-file discovery but disables
extensions and restricts the model to the `read`, `grep`, `find`, and `ls` tools without
project approval. This is a Pi tool boundary for trusted PRs, not an OS sandbox.

Every launching subcommand also passes `--name` to `pi`, the same way `clwt` does. An
override must use the two-token form, `--name X` or `-n X` — Pi silently ignores
`--name=X` — and `pwt` adds no name when the first argument after `--` is a Pi command
word (`auth`, `install`, `remove`, `uninstall`, `update`, `list`, `config`), so that
command still runs.

```bash
pi/scripts/pwt install
```

Installation, completion, all ten commands, safety boundaries, and the manual test command
are documented in the [Pi pwt guide](pi/README.md#pwt--worktree-cli). The independent-port
rationale is recorded in [ADR 0012](docs/decisions/0012-pwt-worktree-cli.md).

## Codex command approval rules

The Codex-specific command allowlist lives in codex/rules/ai-config.rules using Codex's
experimental prefix_rule format. `link.sh` symlinks it into ~/.codex/rules/ next to Codex's
own default.rules; it never touches config.toml or the user's other rules. See
[Installing the library](docs/install.md#installing-the-library) and the Codex guide in codex/README.md.

---

## Harness configuration and shared skills

This repo ships harness-specific configuration plus a portable Agent Skills library:

- **[`claude/`](claude/)** — the full workflow library for Claude Code, linked
  **globally** by `link.sh` (see [Installing the library](docs/install.md#installing-the-library)).
- **[`agents/`](agents/)** — portable Open Agent Skills shared by Codex and Pi, authored in
  `agents/skills/` (currently `branch-names`, `create-pr`, `git-commit`, `pr-review`,
  `writing-skills`). Both harnesses auto-discover project `.agents/skills/` and personal
  `~/.agents/skills/`; `link.sh` links the personal location.
- **[`codex/`](codex/)** — Codex-specific `AGENTS.md` guidance, manually merged into a
  project when wanted. Skill installation is documented in [`codex/README.md`](codex/README.md).
- **[`pi/`](pi/)** — Pi-specific guidance and developer tooling. `pi/AGENTS.md` is a
  **personal global context file** (communication rules, conventions, workflow, change
  gate, execution guardrails), linked as `~/.pi/agent/AGENTS.md` and active
  in every repo ([ADR 0008](docs/decisions/0008-pi-global-only-config.md)). The
  [Pi guide](pi/README.md) documents the developer-run `pwt` CLI and its separate install.
  Pi also auto-discovers the shared Agent Skills locations
  ([official Pi skills documentation](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md)).

The shared `agents/skills/` tree is one portable source, not synchronized harness copies.
Harness-specific content still diverges freely ([ADR 0006](docs/decisions/0006-per-harness-config-trees.md),
[ADR 0010](docs/decisions/0010-shared-agent-skills-library.md)). `claude/` remains canonical
for the Claude workflow used by this repo.

### Personal user preferences

- **[`claude/CLAUDE.md`](claude/CLAUDE.md)** — personal preferences for Claude Code, linked
  as `~/.claude/CLAUDE.md`.
- **[`agents/AGENTS.md`](agents/AGENTS.md)** — equivalent personal preferences expressed
  for a generic coding agent, with a self-contained workflow and no required Claude-only
  tools, linked as `~/.codex/AGENTS.md`. See the
  [shared library guide](agents/README.md#personal-user-preferences).
- **[`pi/AGENTS.md`](pi/AGENTS.md)** — the Pi personal global context, linked as
  `~/.pi/agent/AGENTS.md`.

These are standalone, independently maintained files — not generated or synchronized copies —
and because they are linked verbatim into the harness homes, they are the live user
instructions. Keep reusable personal preferences here and put anything work-specific in the
private directory's `work-rules.md`, never in the repo. Follow the
[repository authoring boundary](AGENTS.md#authoring-conventions); do not preserve private
operational details by merely substituting generic names. The personal instructions in these
files are for global use, not for maintaining this repository; the root `AGENTS.md` governs
that.

This repo's own guidance lives in `AGENTS.md`, read natively by Codex, Pi, and Claude Code
2.1.277 or later (which reads `AGENTS.md` whenever no `CLAUDE.md` exists in the working
directory or above it). There is no `CLAUDE.md` in this repo. Claude Code confirms the load
with an `AGENTS.md loaded` line at session start; the file does not appear in `/memory` or
`/context`.

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
archive/           # the previous automated pipeline, kept for reference
AGENTS.md          # how to work IN this repo (read natively by all three harnesses)
```

The `archive/` directory holds the previous fully-automated pipeline (the `/feature` orchestrator, `context.yaml`, step agents) — preserved for reference while the workflow is rebuilt manually.
