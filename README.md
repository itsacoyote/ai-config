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

## Skills

Skills marked **`/cmd`** are invoked explicitly by you (`/name`); the rest load automatically when relevant (and can still be invoked with `/`).

### Workflow steps

| Skill | |
|-------|--|
| `define` `/cmd` | Collaborative spec dialogue — scope, goals, constraints, acceptance criteria; creates the branch; approval checkpoint |
| `research` `/cmd` | Fan-out orchestrator: spawns parallel lens agents (`research-reuse`, `research-patterns`, `research-risks`, and conditional lenses) and synthesizes their findings |
| `planning-and-task-breakdown` | File map + dependency-ordered tasks with explicit test names |
| `incremental-implementation` | Build in thin vertical slices, test-and-commit per increment |
| `validate` `/cmd` | Sequence senior + security + QA review with bounded fix loops |
| `document` `/cmd` | Pre-PR documentation audit + PR description |
| `feature-workflow` | The map of the six steps and which skill/agent owns each |
| `autorun` `/cmd` | Supervised-autonomous orchestrator: after Define, runs Research→Document one task at a time in fresh subagents, permissions on, stopping at a ready-for-review PR |
| `wayfinder` `/cmd` | Situational on-ramp *before* Define for ideas too big and foggy for one session — charts a shared map of investigation tickets in beads (a `wayfinder:map` epic; `bd ready --parent` is the frontier), resolves one ticket per session until the way is clear |

### Research support

| Skill | |
|-------|--|
| `analyze-code` | Survey a file/module — responsibility, interface, dependencies, reuse |
| `edge-cases-and-risks` | Surface security-sensitive paths, domain rules, gotchas, and "this bites you if missed" hazards before implementation; advisory awareness notes, not tracked tasks |
| `find-patterns` | Identify conventions and architectural decisions to stay consistent with |
| `onboard` | ADR-aware whole-codebase orientation for joining/returning to a project — stack, setup/run/test, architecture, conventions, decisions; in-session plus an opt-in `ONBOARDING.md` |
| `web-search` | Verify external library/API behavior against versioned official docs |

### Review & quality

| Skill | |
|-------|--|
| `pr-review` `/cmd` | Comprehensive, multi-lens, comment-only review of *someone else's* PR (context + security + senior + tests); curate findings, then post as one COMMENT review — never approves, requests changes, merges, or edits. Re-runs (`/cmd <pr-number> [deep\|light]`) auto-detect as follow-ups: skip already-raised findings, report each prior thread's fate (outdated / replied / still-stands); every Nth run or `deep` forces a full deep re-check |
| `plan-review` | Staff-engineer design review of the spec + plan *before* implementation (Plan → Implement gate) — approach, decomposition, interfaces, reuse, risk, spec-alignment, sequencing; the pre-build mirror of `validate` |
| `senior-review` | Brutal engineering review — completeness, correctness, coherence, YAGNI (security is a separate `security-scan` pass) |
| `efficiency-review` | Cheap read-only per-task review — YAGNI, simplification, clarity/naming only (not correctness/security/coverage); canonical home for the simplification criteria `senior-review` links to |
| `design-review` | Frontend/UX/a11y review — component reuse, design-system correctness, architecture, state/data flow, UX, accessibility; conditional (frontend diffs only), used in both `validate` and `pr-review` |
| `qa-review` | Test coverage, test quality, spec-to-test mapping, e2e (graceful), evidence |
| `security-scan` | Vulnerability audit — injection, auth/access control, secrets, crypto, deps (JS/TS/Ruby); run as its own `validate` round via the `security-scan` agent |
| `security-and-hardening` | Build secure code in the first place (preventive counterpart to `security-scan`) |
| `writing-tests` | What/how-much to test, at what level — the judgment behind good tests |
| `project-checks` | Discover + run the project's own mechanical gates (typecheck, lint, format, spell, tests) before each commit and as a Validate pre-flight — auto-fix, then block on failure |
| `debugging-and-error-recovery` | Systematic root-cause debugging when something breaks |

### Engineering craft

| Skill | |
|-------|--|
| `api-and-interface-design` | Stable, hard-to-misuse APIs and module boundaries |
| `prototype` | Throwaway code that answers a design question — an interactive logic/state TUI, or radically different UI variants switchable on one route; capture the answer, delete the prototype |
| `frontend-ui-engineering` | Production-quality UIs; honors `DESIGN.md`/`PRODUCT.md` |
| `impeccable` `/cmd` | Deep design-system workflow (shape, craft, critique, audit, polish) — third-party, adopted into the library |
| `documentation-and-adrs` | Record decisions and keep documentation current |
| `deprecation-and-migration` | Remove and migrate old systems safely |
| `ci-cd-and-automation` | Build/deploy pipelines and quality gates |
| `browser-testing-with-devtools` | Verify UI against a real browser (needs the chrome-devtools MCP) |

### Technology specialists

Stack-specific skills, deliberately scoped to **durable judgment** — decision guides, debugging/migration playbooks, slow-rotting fundamentals — rather than current-API syntax (which the model already knows and `web-search` keeps live). Fast-rotting framework skills (React/Next/Vue) were intentionally cut to avoid silent staleness. Each cross-links the general skills above (`writing-tests`, `security-and-hardening`, `api-and-interface-design`) rather than restating them.

| Skill | |
|-------|--|
| `postgres-pro` | PostgreSQL — EXPLAIN tuning, index strategy, JSONB, replication, VACUUM, extensions (Postgres internals rot in years, not months) |
| `playwright-expert` | Playwright E2E — a11y-first selector priority, Page Object Model, flaky-test debugging workflow |
| `rails-expert` | Rails 7+ — Active Record N+1 prevention, Hotwire/Turbo, Sidekiq job design |

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
| `wait-what` `/cmd` | Re-pitch the last reply when it didn't land — context first, Simplified Technical English, the project's own vocabulary |
| `writing-skills` | How to author and verify skills (use this when adding to this repo) |
| `doubt-driven-development` | Fresh-context adversarial review of non-trivial decisions |

---

## Agents

Thin wrappers that run a review skill in an **isolated context** — the value is independent review that didn't write the code (so it won't rubber-stamp it). Spawned by the `validate` or `pr-review` skill from the main session, or invoked directly.

| Agent | |
|-------|--|
| `plan-review` | Runs the `plan-review` skill; staff-engineer design review of the spec + plan before implementation — returns a severity-gated verdict, never writes code or edits the plan |
| `senior-review` | Runs the `senior-review` skill; returns findings, doesn't change code |
| `efficiency-review` | Runs the `efficiency-review` skill (Sonnet); cheap read-only per-task YAGNI/simplification pass — returns a verdict, never edits code |
| `security-scan` | Runs the `security-scan` skill (Opus); read-only Validate-context security pass over the branch diff — returns findings with suggested patches, never edits or commits (sibling of `pr-security`, which is PR-diff-scoped) |
| `design-review` | Runs the `design-review` skill; the conditional frontend/UX/a11y pass for `validate` and `pr-review` — returns findings, never edits code |
| `qa-review` | Runs the `qa-review` skill; owns the e2e run and optional evidence capture |
| `implementer` | Implements one planned task in isolation (spawned by `autorun`); commits and returns a status — doesn't review or push |
| `research-reuse` | Read-only Research lens: surveys the codebase for reuse opportunities and gaps — existing utilities, patterns, and abstractions the implementation should leverage |
| `research-patterns` | Read-only Research lens: surfaces structural and naming conventions, and architecture the implementation must follow |
| `research-risks` | Read-only Research lens: identifies edge cases, failure modes, and gotchas the implementation plan must address |
| `research-libraries` | Read-only Research lens: surveys the external library and API landscape (conditional — run only when the feature involves a third-party tool or API) |
| `research-history` | Read-only Research lens: surfaces prior art, past attempts, and historical decisions from git history (ask-first — run only when the orchestrator requests it) |
| `pr-context` | Read-only PR-review orientation pass (spawned by `pr-review`); surveys the touched code area and returns a brief the other passes build on — never edits |
| `pr-security` | Read-only PR-review security pass (spawned by `pr-review`); audits the diff for vulnerabilities and returns findings with suggested comment text — never patches or posts |
| `pr-tests` | Read-only PR-review test-quality pass (spawned by `pr-review`); checks whether changed behavior is meaningfully covered and returns findings — never runs, edits, or commits tests |

---

## Rules

Always-on conventions in [`claude/rules/`](claude/rules) — auto-applied, no invocation needed.

| Rule | |
|------|--|
| `commenting` | Comment the why, never the what; one home per fact; no narration or speculative tails |
| `github-tool-preference` | Prefer the `gh`/`git` CLI over the GitHub MCP |
| `typescript-tips` | Practical TypeScript patterns (applies to `.ts` files) |

---

## References

Shared knowledge in [`claude/references/`](claude/references) that skills point to (kept in one place so it doesn't drift across skills):

| Reference | Used by |
|-----------|---------|
| `beads.md` | every workflow skill (the beads-required tracking contract, including the canonical label registry — `security-sensitive`, `risk:review-per-task`, `finding:<lens>`, `gap`, `wayfinder:*`) |
| `diff-scope.md` | the review agents + `validate`/`autorun` (how a spawner pins the change-under-review and passes it to reviewers) |
| `review-agent-contract.md` | the six review agents (`security-scan`, `senior-review`, `efficiency-review`, `qa-review`, `design-review`, `plan-review`) — the shared read-only/return-status contract; return shape stays agent-specific |
| `testing-patterns.md` | `writing-tests` |
| `accessibility-checklist.md`, `performance-checklist.md` | `frontend-ui-engineering` |
| `security-checklist.md` | `security-and-hardening` (quick-ref; the canonical preventive inventory lives in the `security-and-hardening` skill, detective signals in `security-scan`) |
| `code-smells.md` | `efficiency-review` + `senior-review` (the Fowler smell baseline — judgment-call heuristics; repo standards override, tooling-enforced concerns skipped) |

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
