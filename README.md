# AI Config

A portable, copy-paste library of [Claude Code](https://docs.claude.com/en/docs/claude-code) **skills, agents, rules, and references**. It gives Claude a structured, manual feature-development workflow — **Define → Research → Plan → Implement → Validate → Document** — plus a deep bench of engineering-quality skills (testing, security, API design, frontend, git, docs).

It runs **manual by default** — you drive each step — with an optional **supervised orchestrator** (`autorun`) that runs the post-Define steps for you, implementing one task at a time in fresh subagents while keeping permissions on and stopping at a ready-for-review PR. There's deliberately no *unattended* runner yet — the human stays in the loop at two gates (Define and the PR) and approves actions as they happen.

Drop `.claude/` into any project and the workflow and skills come with it.

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
| **Research** | `/research` | Findings: reusable code, gaps, patterns, constraints |
| **Plan** | `planning-and-task-breakdown` | A file map + dependency-ordered tasks with named tests |
| **Implement** | `incremental-implementation` | The change, built task by task, tests passing, committed |
| **Validate** | `/validate` | Both reviews passed (spawns the `senior-review` + `qa-review` agents), findings fixed |
| **Document** | `/document` | Docs updated, PR description written, PR readied |

Run the steps in order; advance only when the previous step's output is in hand. Skip the whole thing for trivial changes — it earns its keep on real features where a missed requirement or skipped review is expensive. Start with `feature-workflow` if you want the full map.

### Tracking: works with or without beads

State and tasks flow through **[beads](https://github.com/gastownhall/beads)** (the `bd` CLI) when it's set up, and **conversationally** when it isn't. Every workflow skill follows the dual-mode contract in [`.claude/references/beads.md`](.claude/references/beads.md): fully usable standalone, and better when beads exists (a feature becomes an epic, plan tasks become child issues, review findings become issues). There is no `.docs/` folder or `context.yaml` — beads (or the conversation) is the system of record.

To turn beads on for a project, run the **`setup-beads`** skill — it installs `bd`, initializes an isolated local database, and keeps it out of git by default.

---

## Skills

Skills marked **`/cmd`** are invoked explicitly by you (`/name`); the rest load automatically when relevant (and can still be invoked with `/`).

### Workflow steps

| Skill | |
|-------|--|
| `define` `/cmd` | Collaborative spec dialogue — scope, goals, constraints, acceptance criteria; creates the branch; approval checkpoint |
| `research` `/cmd` | Study the codebase for a feature — reuse, gaps, patterns, constraints |
| `planning-and-task-breakdown` | File map + dependency-ordered tasks with explicit test names |
| `incremental-implementation` | Build in thin vertical slices, test-and-commit per increment |
| `validate` `/cmd` | Sequence senior + QA review with bounded fix loops |
| `document` `/cmd` | Pre-PR documentation audit + PR description |
| `feature-workflow` | The map of the six steps and which skill/agent owns each |
| `autorun` `/cmd` | Supervised-autonomous orchestrator: after Define, runs Research→Document one task at a time in fresh subagents, permissions on, stopping at a ready-for-review PR |

### Research support

| Skill | |
|-------|--|
| `analyze-code` | Survey a file/module — responsibility, interface, dependencies, reuse |
| `find-patterns` | Identify conventions and architectural decisions to stay consistent with |
| `web-search` | Verify external library/API behavior against versioned official docs |

### Review & quality

| Skill | |
|-------|--|
| `senior-review` | Brutal engineering review — completeness, correctness, coherence, YAGNI, security |
| `qa-review` | Test coverage, test quality, spec-to-test mapping, e2e (graceful), evidence |
| `security-scan` | Vulnerability audit — injection, auth/access control, secrets, crypto, deps (JS/TS/Ruby) |
| `security-and-hardening` | Build secure code in the first place (preventive counterpart to `security-scan`) |
| `writing-tests` | What/how-much to test, at what level — the judgment behind good tests |
| `project-checks` | Discover + run the project's own mechanical gates (typecheck, lint, format, spell, tests) before each commit and as a Validate pre-flight — auto-fix, then block on failure |
| `debugging-and-error-recovery` | Systematic root-cause debugging when something breaks |

### Engineering craft

| Skill | |
|-------|--|
| `api-and-interface-design` | Stable, hard-to-misuse APIs and module boundaries |
| `frontend-ui-engineering` | Production-quality UIs; honors `DESIGN.md`/`PRODUCT.md` |
| `impeccable` `/cmd` | Deep design-system workflow (shape, craft, critique, audit, polish) |
| `documentation-and-adrs` | Record decisions and keep documentation current |
| `deprecation-and-migration` | Remove and migrate old systems safely |
| `ci-cd-and-automation` | Build/deploy pipelines and quality gates |
| `browser-testing-with-devtools` | Verify UI against a real browser (needs the chrome-devtools MCP) |

### Git, PRs & meta

| Skill | |
|-------|--|
| `branch-names` | `<type>/<slug>` branch naming |
| `git-commit` | Conventional commits, no AI attribution; surfaces the committed message |
| `git-workflow-and-versioning` | Commit/branch/merge discipline, conflicts, debugging with git |
| `create-pr` | PR titles and bodies — honors the host project's PR process and GitHub template first |
| `sync` `/cmd` | Bring the local checkout up to date with `main` before new work |
| `standup` `/cmd` | Read-only recap of recent work (done / in progress / next) for catching up after a break — beads-first, else git + PRs |
| `setup-beads` `/cmd` | Install and initialize beads (`bd`) for a project — isolated local use, nothing committed by default |
| `bd-cleanup` `/cmd` | Maintain the beads database — reclaim space (Dolt GC, compaction) and prune old closed issues, dry-run first |
| `writing-skills` | How to author and verify skills (use this when adding to this repo) |
| `doubt-driven-development` | Fresh-context adversarial review of non-trivial decisions |

---

## Agents

Thin wrappers that run a review skill in an **isolated context** — the value is independent review that didn't write the code (so it won't rubber-stamp it). Spawned by the `validate` skill from the main session, or invoked directly.

| Agent | |
|-------|--|
| `senior-review` | Runs the `senior-review` skill; returns findings, doesn't change code |
| `qa-review` | Runs the `qa-review` skill; owns the e2e run and optional evidence capture |
| `implementer` | Implements one planned task in isolation (spawned by `autorun`); commits and returns a status — doesn't review or push |

---

## Rules

Always-on conventions in [`.claude/rules/`](.claude/rules) — auto-applied, no invocation needed.

| Rule | |
|------|--|
| `github-tool-preference` | Prefer the `gh`/`git` CLI over the GitHub MCP |
| `typescript-tips` | Practical TypeScript patterns (applies to `.ts` files) |

---

## References

Shared knowledge in [`.claude/references/`](.claude/references) that skills point to (kept in one place so it doesn't drift across skills):

| Reference | Used by |
|-----------|---------|
| `beads.md` | every workflow skill (the dual-mode tracking contract) |
| `testing-patterns.md` | `writing-tests` |
| `accessibility-checklist.md`, `performance-checklist.md` | `frontend-ui-engineering` |
| `security-checklist.md` | `security-and-hardening` |

---

## Using this in another project

1. **Copy `.claude/` into the target project's root** — skills, agents, rules, and references all live there and travel together. (When copying an individual skill, bring any `.claude/references/` file it points to as well.)
2. **The project's own `CLAUDE.md` does not come from here** — this repo's `CLAUDE.md` documents *this* repo. To orient Claude to the workflow in the target project, paste the snippet below into that project's `CLAUDE.md` and adapt it.
3. **Optionally copy `.mcp.json`** (see [MCP servers](#mcp-servers)).
4. Open Claude Code in the project and start with `/define` (or read `feature-workflow` first).

### Example: paste into your project's `CLAUDE.md`

```markdown
## Development workflow

This project uses a manual feature workflow: **Define → Research → Plan →
Implement → Validate → Document**. Run each step deliberately — there is no
orchestrator. See the `feature-workflow` skill for the map.

- Start a feature with `/define` (it writes the spec and creates the branch).
- Then: `/research` → `planning-and-task-breakdown` → `incremental-implementation`
  → `/validate` → `/document`.
- `/validate` spawns the `senior-review` and `qa-review` agents for independent review.
- Match rigor to the change — skip the workflow for trivial fixes.

## Task tracking

If [beads](https://github.com/gastownhall/beads) is set up (`.beads/` exists),
the workflow records features/tasks/findings as beads issues. If not, it runs
conversationally — both work. Run the `setup-beads` skill to enable it. See
`.claude/references/beads.md`.

## Conventions

- Conventional Commits for all commits and PR titles; no AI-attribution trailers
  (the `git-commit` skill enforces this).
- Prefer the `gh`/`git` CLI for git and GitHub operations.
```

---

## MCP servers

`.mcp.json` configures two optional servers:

| Server | Purpose |
|--------|---------|
| `playwright` | Browser automation for `qa-review` evidence capture and e2e |
| `github` | GitHub API for interactive use (needs `GITHUB_PERSONAL_ACCESS_TOKEN`) |

Both are optional — skills degrade gracefully when a server isn't present (e.g. `qa-review` skips evidence capture). Git/GitHub operations prefer the `gh` CLI regardless (`github-tool-preference` rule).

---

## Repo layout

```text
.claude/
├── skills/        # the skills above (one folder each, SKILL.md + optional files)
├── agents/        # senior-review, qa-review
├── rules/         # always-on conventions
└── references/    # shared knowledge skills point to
archive/           # the previous automated pipeline, kept for reference
CLAUDE.md          # how to work IN this repo (does not travel to other projects)
```

The `archive/` directory holds the previous fully-automated pipeline (the `/feature` orchestrator, `context.yaml`, step agents) — preserved for reference while the workflow is rebuilt manually.
