# AI Config

A side-by-side configuration library for [Claude Code](https://docs.claude.com/en/docs/claude-code), Codex, and Pi. It provides a structured feature workflow — **Define → Research → Plan → Implement → Validate → Document** — plus engineering-quality skills for testing, security, API design, frontend, git, and documentation.

It runs **manual by default**. The optional supervised `autorun` orchestrator runs post-Define phases in order, may parallelize read-only research/review lenses, strictly serializes implementation and source editing, keeps permissions active, and stops at the draft-PR human handoff. The human remains responsible for the Define approval and PR review gates.

- `.claude/` preserves the existing Claude Code implementation, including hooks, rules, and settings.
- `.agents/` is the portable Agent Skills library, shared references/scripts, and neutral role contract.
- `.codex/` adapts neutral roles to Codex custom agents.
- Pi uses dedicated sessions and fresh bash-launched workers; no subagent extension or tmux installation is required.

Neither `.claude/` nor `.agents/` is canonical across harnesses until parity is demonstrated and recorded. See [ADR 0003](docs/decisions/0003-agent-agnostic-library.md).

---

## Portable library quick start

### Install the complete personal library

Install the whole `.agents/` tree; individual skills can depend on its references, scripts, schemas, and role prompts.

```bash
# Preview first
./.agents/scripts/install-library.sh --target "$HOME/.agents" --dry-run

# Install or safely upgrade
./.agents/scripts/install-library.sh --target "$HOME/.agents"
```

The installer preserves unrelated files and refuses collisions or locally modified owned files. Review its report before using `--replace`. A release that removes files from an older release must authenticate that exact prior manifest in the new source manifest. Optional `.codex/` project adapters and root `AGENTS.md` are intentionally outside the personal install.

For project-local use, copy the complete `.agents/` directory into the project, add the root [`AGENTS.md`](AGENTS.md), and optionally add [`.codex/`](.codex) for Codex custom roles. Claude projects continue to copy `.claude/` as before.

### Invoke by harness

| Harness | Skills | Isolated roles | Important limitation |
| --- | --- | --- | --- |
| Claude Code | Existing slash commands such as `/define` and `/validate`; other skills load when relevant | Thin `.claude/agents/*.md` subagents | `.claude/` remains unchanged during parity work |
| Codex | Discover under `.agents/skills/`; explicitly invoke with `$skill-name` when required | `.codex/agents/*.toml`, validated against neutral `roles.json` | `agents/openai.yaml` supplies Codex's explicit-only policy |
| Pi | Discover portable skills in interactive sessions; invoke explicitly with `/skill:name` | Fresh `.agents/scripts/run-pi-role.sh` workers or a dedicated Research session | No native MCP; use available browser CLI/extension capability or record a static/skip limitation |

`define`, `research`, `wayfinder`, `validate`, `pr-review`, `autorun`, `document`, and maintenance commands are intentional user actions. Do not treat `allowed-tools` or skill metadata as portable security enforcement.

### Permissions and orchestration

- `.agents/agents/roles.json` is machine-readable policy input interpreted by adapters; it is not itself a security boundary. Prompts and filenames do not grant permissions.
- Codex read-only roles use a read-only sandbox. `qa-review` may write generated evidence only. The implementer inherits the supervised parent policy.
- The generic Pi runner rejects implementation, but its read-only/verification boundaries are behavioral—not an OS-enforced filesystem sandbox. Do not use generic workers against untrusted repositories or PR content without an external sandbox/container. Pi source editing must always go through `autorun`'s external sandbox launcher; without that launcher, it blocks.
- Research on Pi defaults to a dedicated session and persists its synthesis to beads. Saved sessions are optional; tmux is only an optional operator convenience.
- Browser workflows use available Chrome DevTools, Playwright, CLI, or extension capabilities and explicitly degrade when none exists.

### Validate and maintain

```bash
python3 .agents/scripts/generate-catalog.py --check
python3 .agents/scripts/validate-library.py
bash .agents/scripts/tests/install-library-test.sh
```

The generated [skill catalog](.agents/catalog.md) groups all 49 flat skills by `metadata.category`. The [compatibility matrix](.agents/compatibility.md) records portable, adapted, harness-orchestrated, and capability-limited behavior.

---

## The Claude workflow

The workflow is shared across harnesses, but the invocation syntax in this section is the preserved Claude Code syntax. Codex and Pi users should follow the [harness table](#invoke-by-harness). Six steps run in order; `feature-workflow` is the in-repo map.

```text
Define ──▶ Research ──▶ Plan ──▶ Implement ──▶ Validate ──▶ Document
(spec +    (study the   (file    (build it    (senior +    (docs +
 approval)  codebase)    map +    task by      QA review)   PR handoff)
                         tasks)   task)
```

| Step | Invoke | What it produces |
|------|--------|------------------|
| **Define** | `/define` | An approved spec and the feature branch |
| **Research** | `/research` | Findings: reuse, patterns, risks — fan-out across parallel lens agents, synthesized |
| **Plan** | `planning-and-task-breakdown` | A file map + dependency-ordered tasks with named tests |
| **Implement** | `incremental-implementation` | The change, built task by task, tests passing, committed |
| **Validate** | `/validate` | Reviews passed (spawns the `senior-review` + `security-scan` + `design-review` (conditional, frontend) + `qa-review` agents), findings fixed |
| **Document** | `/document` | Docs updated, PR description prepared, human PR handoff |

Run the steps in order; advance only when the previous step's output is in hand. **Every step ends by recommending the next move — the default next step, plus situational skills its output signals (e.g. `prototype` after a Define that left UI behavior fuzzy) — and waits for your explicit go before starting it** (`autorun` is the opt-out). Skip the whole thing for trivial changes — it earns its keep on real features where a missed requirement or skipped review is expensive. Start with `feature-workflow` if you want the full map.

### Tracking: requires beads

State and tasks flow through **[beads](https://github.com/gastownhall/beads)** (the `bd` CLI) — it is required. Workflow skills hard-stop and redirect to `setup-beads` when beads is absent. A feature becomes an epic, plan tasks become child issues, review findings become issues. There is no `.docs/` folder or `context.yaml` — beads is the system of record.

Run the **`setup-beads`** skill to install `bd` and initialize an isolated local database (nothing committed by default). The committed session-start gate hook (`.claude/hooks/beads-gate.sh`) warns when beads is missing and injects current task context when it's present.

---

## Claude skills

This catalog describes the preserved `.claude/` library. Skills marked **`/cmd`** are invoked explicitly in Claude Code (`/name`); the rest load automatically when relevant (and can still be invoked with `/`). For portable inventory and cross-harness invocation, use [`.agents/catalog.md`](.agents/catalog.md) and the [harness table](#invoke-by-harness).

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
| `autorun` `/cmd` | Supervised orchestrator: runs Research→Document phases in order, may parallelize read-only lenses, serializes implementers/source editing, and stops at the human PR handoff |
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
| `impeccable` `/cmd` | Deep design-system workflow (shape, craft, critique, audit, polish) |
| `documentation-and-adrs` | Record decisions and keep documentation current |
| `deprecation-and-migration` | Remove and migrate old systems safely |
| `ci-cd-and-automation` | Build/deploy pipelines and quality gates |
| `browser-testing-with-devtools` | Verify UI against a real browser using an available DevTools, Playwright, CLI, MCP, or extension capability |

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
| `beads.md` | every workflow skill (the beads-required tracking contract, including the canonical label registry — `security-sensitive`, `risk:review-per-task`, `finding:<lens>`, `gap`, `wayfinder:*`) |
| `diff-scope.md` | the review agents + `validate`/`autorun` (how a spawner pins the change-under-review and passes it to reviewers) |
| `review-agent-contract.md` | the six review agents (`security-scan`, `senior-review`, `efficiency-review`, `qa-review`, `design-review`, `plan-review`) — the shared read-only/return-status contract; return shape stays agent-specific |
| `testing-patterns.md` | `writing-tests` |
| `accessibility-checklist.md`, `performance-checklist.md` | `frontend-ui-engineering` |
| `security-checklist.md` | `security-and-hardening` (quick-ref; the canonical preventive inventory lives in the `security-and-hardening` skill, detective signals in `security-scan`) |
| `code-smells.md` | `efficiency-review` + `senior-review` (the Fowler smell baseline — judgment-call heuristics; repo standards override, tooling-enforced concerns skipped) |

---

## Using the Claude library in another project

The portable/Codex setup is covered in [Portable library quick start](#portable-library-quick-start). For the preserved Claude Code setup:

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
- `/validate` spawns the `senior-review`, `security-scan`, and `qa-review` agents for independent review.
- Match rigor to the change — skip the workflow for trivial fixes.

## Task tracking

[beads](https://github.com/gastownhall/beads) is required — the workflow records
features/tasks/findings as beads issues and hard-stops when beads is absent. Run
the `setup-beads` skill to install and initialize it. See
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
.agents/
├── skills/        # 49 flat portable Agent Skills
├── agents/        # neutral role prompts, roles.json, and QA schema
├── references/    # shared portable knowledge
├── scripts/       # validators, Pi runner, and safe installer
├── catalog.md     # generated category catalog
└── manifest.json  # versioned ownership/checksum contract
.codex/agents/     # thin project custom-agent adapters
.claude/           # preserved Claude skills, agents, rules, hooks, and references
AGENTS.md          # portable project guidance loaded by Codex and Pi
archive/           # previous automated pipeline, kept for reference
CLAUDE.md          # maintainer guidance for this repository only
```

The `archive/` directory holds the previous fully-automated pipeline (the `/feature` orchestrator, `context.yaml`, step agents) — preserved for reference while the workflow is rebuilt manually.
