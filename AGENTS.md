# Agent configuration library

This repository is a portable library of development workflows, engineering guidance, and isolated-role contracts for Claude Code, Codex, and Pi. Preserve the existing `.claude/` setup while building and validating the parallel `.agents/` library. Do not make either tree canonical until cross-harness parity has been demonstrated and recorded.

See [README.md](README.md) for the public catalog and installation guidance.

## Artifact placement

Choose the artifact by intent:

- `.agents/skills/<name>/SKILL.md` — portable Agent Skills; keep skill directories flat. Skill-owned scripts, references, and assets stay inside that skill directory.
- `.agents/references/` — shared portable knowledge used by multiple skills.
- `.agents/scripts/` — shared executable helpers used by multiple skills.
- `.agents/agents/` — harness-neutral role prompts and machine-readable role contracts. Methodology belongs in skills, not role wrappers.
- `.codex/agents/` — thin Codex adapters for neutral roles.
- `.claude/` — the existing Claude Code library and Claude-specific agents, rules, hooks, and settings. Keep it functional during migration.
- `docs/decisions/` — architectural decisions and their rationale.
- `archive/` — historical material only; never wire active workflows to it.

A discoverable technique is a skill. An always-on portable convention belongs here. Isolated execution is a neutral role plus a harness adapter. Shared facts belong in one reference rather than repeated across skills.

## Authoring conventions

When creating or editing skills, use the `writing-skills` skill and follow these rules:

- Start descriptions with **“Use when…”** and describe triggering conditions, not a summary that lets an agent skip the body.
- Keep one source of truth for shared facts. Cross-link at boundaries instead of copying checklists or workflow contracts.
- Include a **When NOT to use** section so skills are not over-applied.
- Keep every referenced skill, role, script, and document resolvable. No dead links.
- Avoid names that collide with built-in commands such as `code-review`, `security-review`, `review`, `verify`, `init`, and `run`.
- Add `metadata.category` for catalog grouping while keeping physical skill directories flat.
- Treat `allowed-tools` and similar metadata as capability documentation, not a cross-harness security boundary.

## Portability and drift

- Install or copy the complete `.agents/` tree. Skills may depend on shared references, role contracts, and scripts outside their own directory.
- Resolve skill-owned paths from the loaded skill directory. Resolve shared helpers by walking from that skill to `.agents/scripts/`; never assume the repository working directory.
- Keep provider model aliases and harness-specific dispatch syntax out of portable skills and neutral roles.
- Put Codex behavior in `.codex/`; use Pi's documented bash-spawned `pi --print` workflow rather than requiring a subagent extension.
- Do not claim MCP parity for Pi. Describe required capabilities and documented CLI or extension fallbacks.
- Run the library validation and drift checks before committing portable-library changes once those checks are available.

## Workflow state: beads is required

The feature workflow is **Define → Research → Plan → Implement → Validate → Document**. Beads (`bd`) is its required system of record; there is no `.docs/` step folder or `context.yaml` fallback.

Before workflow work, run the preflight described in [`.agents/references/beads.md`](.agents/references/beads.md). Worktrees share the main repository's single beads database through Git's common directory. Never initialize or copy a second `.beads/` database into a worktree.

## GitHub, commits, and pull requests

- Prefer `git` and `gh` for Git and GitHub operations. Do not introduce a GitHub MCP dependency when the CLI supports the operation.
- Use Conventional Commits and Conventional Commit PR titles: `<type>(optional-scope): <imperative lowercase description>`.
- Never add AI attribution, generated-by text, robot markers, or AI co-author trailers.
- Follow the host repository's signing and push policy. Never bypass signing requirements to push or update a pull request.
- New pull requests are drafts unless the repository explicitly says otherwise. Never merge or mark a PR ready on the user's behalf.

## Archive boundary

The old automated `/feature` pipeline, personas, `.docs/` step files, and `context.yaml` material under `archive/` are historical references. Do not import or reconnect them to current skills, roles, scripts, or documentation.
