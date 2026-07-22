# Agent Library Compatibility

This matrix describes behavior, not a security boundary. `roles.json` and harness adapters remain the executable policy sources.

## Compatibility classes

- **Portable** — neutral methodology with no harness-specific execution path.
- **Adapted paths/frontmatter** — methodology preserved with portable resource paths and Agent Skills metadata.
- **Harness orchestration** — neutral methodology plus separate Codex/Pi dispatch adapters.
- **Capability-limited** — behavior depends on browser, web, or other runtime capabilities and degrades explicitly.

## Skills

| Skill | Category | Compatibility |
| --- | --- | --- |
| `analyze-code` | `research` | Adapted paths/frontmatter |
| `api-and-interface-design` | `engineering-specialist` | Adapted paths/frontmatter |
| `autorun` | `workflow` | Harness orchestration |
| `bd-cleanup` | `git-maintenance` | Adapted paths/frontmatter |
| `branch-names` | `git-maintenance` | Adapted paths/frontmatter |
| `browser-testing-with-devtools` | `engineering-specialist` | Capability-limited |
| `ci-cd-and-automation` | `engineering-specialist` | Adapted paths/frontmatter |
| `create-pr` | `git-maintenance` | Adapted paths/frontmatter |
| `debugging-and-error-recovery` | `engineering-specialist` | Adapted paths/frontmatter |
| `define` | `workflow` | Harness orchestration |
| `deprecation-and-migration` | `engineering-specialist` | Adapted paths/frontmatter |
| `design-review` | `review-quality` | Capability-limited |
| `document` | `workflow` | Harness orchestration |
| `documentation-and-adrs` | `engineering-specialist` | Adapted paths/frontmatter |
| `doubt-driven-development` | `review-quality` | Adapted paths/frontmatter |
| `edge-cases-and-risks` | `research` | Adapted paths/frontmatter |
| `efficiency-review` | `review-quality` | Adapted paths/frontmatter |
| `explain-diff` | `git-maintenance` | Adapted paths/frontmatter |
| `feature-workflow` | `workflow` | Harness orchestration |
| `find-patterns` | `research` | Adapted paths/frontmatter |
| `frontend-ui-engineering` | `engineering-specialist` | Adapted paths/frontmatter |
| `git-commit` | `git-maintenance` | Adapted paths/frontmatter |
| `git-workflow-and-versioning` | `git-maintenance` | Adapted paths/frontmatter |
| `impeccable` | `design` | Capability-limited |
| `incremental-implementation` | `workflow` | Adapted paths/frontmatter |
| `onboard` | `git-maintenance` | Adapted paths/frontmatter |
| `plan-review` | `review-quality` | Adapted paths/frontmatter |
| `planning-and-task-breakdown` | `workflow` | Harness orchestration |
| `playwright-expert` | `engineering-specialist` | Capability-limited |
| `postgres-pro` | `engineering-specialist` | Adapted paths/frontmatter |
| `pr-review` | `workflow` | Harness orchestration |
| `project-checks` | `review-quality` | Adapted paths/frontmatter |
| `prototype` | `engineering-specialist` | Adapted paths/frontmatter |
| `qa-review` | `review-quality` | Adapted paths/frontmatter |
| `rails-expert` | `engineering-specialist` | Adapted paths/frontmatter |
| `reground` | `git-maintenance` | Adapted paths/frontmatter |
| `research` | `workflow` | Harness orchestration |
| `security-and-hardening` | `review-quality` | Adapted paths/frontmatter |
| `security-scan` | `review-quality` | Adapted paths/frontmatter |
| `senior-review` | `review-quality` | Adapted paths/frontmatter |
| `setup-beads` | `git-maintenance` | Adapted paths/frontmatter |
| `standup` | `git-maintenance` | Adapted paths/frontmatter |
| `sync` | `git-maintenance` | Adapted paths/frontmatter |
| `typescript-tips` | `engineering-specialist` | Portable |
| `validate` | `workflow` | Harness orchestration |
| `wayfinder` | `workflow` | Harness orchestration |
| `web-search` | `research` | Capability-limited |
| `writing-skills` | `git-maintenance` | Adapted paths/frontmatter |
| `writing-tests` | `review-quality` | Adapted paths/frontmatter |

## Isolated roles

All roles use the neutral `.agents/agents/roles.json` contract. Codex maps them through `.codex/agents/`; Pi maps read-only/verification roles through the generic runner and implementation through the supervised sandbox launcher.

| Role | Neutral mode | Codex adapter | Pi route |
| --- | --- | --- | --- |
| `design-review` | `read-only` | `.codex/agents/design-review.toml` | generic isolated runner |
| `efficiency-review` | `read-only` | `.codex/agents/efficiency-review.toml` | generic isolated runner |
| `implementer` | `implementation` | `.codex/agents/implementer.toml` | supervised sandbox launcher |
| `plan-review` | `read-only` | `.codex/agents/plan-review.toml` | generic isolated runner |
| `pr-context` | `read-only` | `.codex/agents/pr-context.toml` | generic isolated runner |
| `pr-security` | `read-only` | `.codex/agents/pr-security.toml` | generic isolated runner |
| `pr-tests` | `read-only` | `.codex/agents/pr-tests.toml` | generic isolated runner |
| `qa-review` | `verification` | `.codex/agents/qa-review.toml` | generic isolated runner |
| `research-history` | `read-only` | `.codex/agents/research-history.toml` | generic isolated runner |
| `research-libraries` | `read-only` | `.codex/agents/research-libraries.toml` | generic isolated runner |
| `research-patterns` | `read-only` | `.codex/agents/research-patterns.toml` | generic isolated runner |
| `research-reuse` | `read-only` | `.codex/agents/research-reuse.toml` | generic isolated runner |
| `research-risks` | `read-only` | `.codex/agents/research-risks.toml` | generic isolated runner |
| `security-scan` | `read-only` | `.codex/agents/security-scan.toml` | generic isolated runner |
| `senior-review` | `read-only` | `.codex/agents/senior-review.toml` | generic isolated runner |

## Known boundaries

- Pi has no native MCP; browser workflows require an available CLI or extension capability.
- Skill tool metadata is descriptive and is not portable permission enforcement.
- Neither `.claude/` nor `.agents/` is canonical until cross-harness parity has been demonstrated and recorded; intentional differences are declared in `.agents/manifest.json`.
