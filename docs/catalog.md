# Catalog

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

Always-on conventions in [`claude/rules/`](../claude/rules) — auto-applied, no invocation needed.

| Rule | |
|------|--|
| `commenting` | Comment the why, never the what; one home per fact; no narration or speculative tails |
| `github-tool-preference` | Prefer the `gh`/`git` CLI over the GitHub MCP |
| `typescript-tips` | Practical TypeScript patterns (applies to `.ts` files) |

---

## References

Shared knowledge in [`claude/references/`](../claude/references) that skills point to (kept in one place so it doesn't drift across skills):

| Reference | Used by |
|-----------|---------|
| `beads.md` | every workflow skill (the beads-required tracking contract, including the canonical label registry — `security-sensitive`, `risk:review-per-task`, `finding:<lens>`, `gap`, `wayfinder:*`) |
| `diff-scope.md` | the review agents + `validate`/`autorun` (how a spawner pins the change-under-review and passes it to reviewers) |
| `review-agent-contract.md` | the six review agents (`security-scan`, `senior-review`, `efficiency-review`, `qa-review`, `design-review`, `plan-review`) — the shared read-only/return-status contract; return shape stays agent-specific |
| `testing-patterns.md` | `writing-tests` |
| `accessibility-checklist.md`, `performance-checklist.md` | `frontend-ui-engineering` |
| `security-checklist.md` | `security-and-hardening` (quick-ref; the canonical preventive inventory lives in the `security-and-hardening` skill, detective signals in `security-scan`) |
| `code-smells.md` | `efficiency-review` + `senior-review` (the Fowler smell baseline — judgment-call heuristics; repo standards override, tooling-enforced concerns skipped) |
