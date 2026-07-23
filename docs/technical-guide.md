# Technical guide

This guide covers installation, repository structure, harness-specific behavior, permissions, invocation, and maintenance for AI Config. For the project's purpose and design intentions, start with the [README](../README.md).

## Architecture

The repository currently maintains two side-by-side libraries:

- `.claude/` preserves the Claude Code implementation, including skills, agents, hooks, rules, references, and settings.
- `.agents/` contains portable Agent Skills, shared references and scripts, neutral role contracts, the generated catalog, and the installation manifest.
- `.codex/` adapts neutral roles to Codex custom agents.
- Pi uses the portable library through interactive sessions, dedicated Research sessions, and fresh `pi --print` workers.

Root [`AGENTS.md`](../AGENTS.md) provides portable project guidance. Root [`CLAUDE.md`](../CLAUDE.md) contains maintainer guidance for this repository and is not copied into target projects.

Neither `.claude/` nor `.agents/` is canonical across harnesses. See [ADR 0003](decisions/0003-agent-agnostic-library.md) for the decision and trade-offs.

## Repository layout

```text
.agents/
├── skills/        # flat portable Agent Skills
├── agents/        # neutral role prompts, roles.json, and QA schema
├── references/    # shared portable knowledge
├── scripts/       # validators, Pi runner, and installer
├── catalog.md     # generated category catalog
└── manifest.json  # versioned ownership/checksum contract
.codex/agents/     # project-local Codex custom-agent adapters
.claude/           # preserved Claude implementation
AGENTS.md          # portable project guidance
CLAUDE.md          # repository maintainer guidance
archive/           # inactive historical workflow
```

The [`archive/`](../archive/) directory is reference material only. Its `/feature` orchestrator, `.docs/`, `context.yaml`, and historical agents are not part of the active workflow.

## Install the portable library

Install the complete `.agents/` tree. Individual skills may depend on shared references, scripts, schemas, and role prompts elsewhere in the tree.

```bash
# Preview
./.agents/scripts/install-library.sh --target "$HOME/.agents" --dry-run

# Install or safely upgrade
./.agents/scripts/install-library.sh --target "$HOME/.agents"
```

The installer:

- preserves unrelated target files;
- verifies source checksums before writing;
- refuses collisions and locally modified owned files by default;
- authenticates prior manifests before removing files from an older release; and
- excludes project-specific `.codex/` adapters and root `AGENTS.md`.

Review the dry-run report before using `--replace`.

For project-local use, copy the complete `.agents/` directory and root `AGENTS.md` into the project. Add `.codex/` if the project should expose Codex custom roles. Claude projects continue to copy `.claude/` as a complete unit.

## Invoke skills by harness

| Harness | Skill invocation | Isolated roles |
| --- | --- | --- |
| Claude Code | Explicit slash commands such as `/define`; other skills load when relevant | Thin `.claude/agents/*.md` wrappers |
| Codex | Discover under `.agents/skills/`; explicitly invoke required skills with `$skill-name` | `.codex/agents/*.toml` adapters |
| Pi | Discover under `.agents/skills/`; explicitly invoke with `/skill:name` | Fresh generic workers or a dedicated Research session |

`define`, `research`, `wayfinder`, `validate`, `pr-review`, `autorun`, `document`, and maintenance commands require an intentional user action. Codex explicit-only policy lives in each applicable `agents/openai.yaml` file. Do not treat skill metadata or `allowed-tools` as portable security enforcement.

See the generated [skill catalog](../.agents/catalog.md) for the complete inventory and the [compatibility matrix](../.agents/compatibility.md) for per-skill behavior.

## Feature workflow

The workflow runs in this order:

```text
Define ──▶ Research ──▶ Plan ──▶ Plan review ──▶ Implement ──▶ Validate ──▶ Document
(spec +    (study the   (file      (pre-build     (build task  (independent  (docs +
 approval)  codebase)    map +      gate)          by task)      review)       PR handoff)
                         tasks)
```

| Step | Skill | Primary output |
| --- | --- | --- |
| Define | `define` | Approved specification and feature branch |
| Research | `research` | Reuse opportunities, patterns, risks, and optionally approved history |
| Plan | `planning-and-task-breakdown` | File map and dependency-ordered tasks with named tests |
| Plan review gate | `plan-review` | An independently reviewed, approved plan |
| Implement | `incremental-implementation` | Incremental, tested, committed changes |
| Validate | `validate` | Engineering, security, conditional frontend design, and QA findings resolved |
| Document | `document` | Current documentation and a draft-PR human handoff |

Use the invocation syntax from the harness table above: for example, Claude starts with `/define`, Codex with `$define`, and Pi with `/skill:define`. The underlying skill names stay the same across harnesses.

The workflow is manual by default. Each phase recommends the next move and waits for explicit advancement. Implementation begins only after `plan-review` passes. `autorun` can supervise the post-Define phases, parallelize bounded read-only lenses, and serialize implementation, but it still stops at human gates. Skip the full workflow for trivial changes.

### Beads is required

[Beads](https://github.com/gastownhall/beads) (`bd`) is the workflow's system of record. Features become epics, plans become child issues, and review findings become tracked issues. Workflow skills stop and redirect to `setup-beads` when beads is absent; there is no `.docs/` or `context.yaml` fallback.

## Neutral roles and permissions

[`.agents/agents/roles.json`](../.agents/agents/roles.json) is versioned policy input for adapters and runners. It defines role mode, required methodology, and capabilities. It is not itself a security boundary, and consumers must not infer permissions from Markdown prompts, frontmatter, filenames, or Claude agent files.

The role modes are:

- **read-only** — inspect and return findings; no source, test, artifact, beads, commit, or remote mutation;
- **verification** — run checks and write generated evidence only; no source or test-definition edits; and
- **implementation** — edit source and named tests within one task scope and commit, but never push.

Only `implementer` has the implementation mode. Review and QA roles return findings rather than silently becoming implementers. The complete contract and QA state machine are documented in the [neutral role guide](../.agents/agents/README.md).

### Codex

Codex non-executing roles use read-only sandboxing. `qa-review` receives artifact-limited writes, while `implementer` inherits the supervised parent policy. Adapters are validated against `roles.json`.

### Pi

The generic Pi runner:

- starts fresh workers with ambient project context, skills, and extensions disabled;
- supplies runner-owned prompts and complete declared skill content;
- rejects every implementation role; and
- forwards cancellation and worker status to the parent.

Its read-only and verification boundaries are behavioral, not an OS-enforced filesystem sandbox. Do not process untrusted repositories or PR content with generic workers unless an external sandbox or container provides the boundary.

Pi implementation must use `autorun`'s supervised implementation wrapper with a verified external sandbox, scope-bound writer lease, and writable-path digest. It blocks if those controls are unavailable.

Pi has no native MCP. Browser workflows require an available browser CLI or extension capability and must report a static-review or skip limitation when neither exists. Saved sessions and tmux are optional; no Pi subagent extension is required.

## QA fix routing

`qa-review` returns versioned JSON validated by `.agents/scripts/validate-qa-result.py`:

- `APPROVED` passes;
- actionable `FIX_REQUIRED` on attempts 1–2 dispatches exactly one serialized implementer, then reruns fresh QA;
- attempt-3 fixes and `BLOCKED` results stop; and
- malformed, unknown-version, or non-actionable results stop without widening permissions.

## Validate and maintain the library

Run the portable checks from the repository root:

```bash
python3 .agents/scripts/generate-catalog.py --check
python3 .agents/scripts/validate-library.py
bash .agents/scripts/tests/install-library-test.sh
```

The validator checks skill structure, resource links, portable paths, explicit-only policy, neutral roles, Codex adapters, source-parity declarations, manifest checksums, repository Markdown links, and generated catalog freshness.

When changing portable library files:

1. Follow the `writing-skills` skill for skill changes.
2. Keep shared facts in `.agents/references/` instead of duplicating them.
3. Keep neutral policy in `roles.json` and harness syntax in adapters.
4. Regenerate `.agents/catalog.md` after skill inventory/category changes.
5. Refresh `.agents/manifest.json` after owned payload changes.
6. Validate the complete library and installer before committing.
7. Do not update `.claude/` merely to make it match; intentional parity work requires explicit review.

## Claude-specific project setup

To use the preserved Claude implementation in another project:

1. Copy the complete `.claude/` directory into the target root.
2. Add project-specific workflow guidance to that project's own `CLAUDE.md`; do not copy this repository's maintainer file unchanged.
3. Optionally copy `.mcp.json` for Playwright and GitHub integrations.
4. Start with `/define`, or load `feature-workflow` for the full map.

A minimal target-project instruction block is:

```markdown
## Development workflow

Use Define → Research → Plan → Plan Review → Implement → Validate → Document
for meaningful features. Begin implementation only after `plan-review` passes.
Run each phase deliberately and keep beads as the system of record. Start with
`/define`; use the `feature-workflow` skill for the complete map.

Use Conventional Commits without AI-attribution trailers. Prefer `gh` and `git`
for GitHub operations.
```

## Optional MCP servers

`.mcp.json` configures optional Playwright and GitHub servers for Claude-compatible clients. Skills degrade explicitly when those capabilities are unavailable. Git and GitHub operations prefer the `git` and `gh` CLIs regardless.

## Further reference

- [Portable skill catalog](../.agents/catalog.md)
- [Compatibility matrix](../.agents/compatibility.md)
- [Neutral role contract](../.agents/agents/README.md)
- [Agent-agnostic architecture decision](decisions/0003-agent-agnostic-library.md)
- [Research lens decision](decisions/0002-research-lens-subagents.md)
- [Beads-required decision](decisions/0001-beads-required.md)
