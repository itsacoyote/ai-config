# CLAUDE.md

Guidance for working **in this repository**. This repo is a **portable library** of Claude Code skills, agents, rules, and references that get copied into other projects. This file documents how to maintain that library — it does **not** travel to target projects (see the README for what to paste into a project's own `CLAUDE.md`).

For the catalog of skills/agents and the feature workflow they implement, see [README.md](README.md).

## What lives where

- `.claude/skills/<name>/SKILL.md` — a skill (methodology/reference Claude loads when relevant). Supporting files live alongside it.
- `.claude/agents/<name>.md` — a subagent: a **thin** wrapper that runs a skill in an isolated context. Methodology stays in the skill, not the agent.
- `.claude/rules/<name>.md` — an always-on convention (auto-applied), for rules that should apply without being invoked.
- `.claude/references/<name>.md` — shared knowledge multiple skills point to (kept in one place so it doesn't drift).

Decide by intent: a discoverable technique → **skill**; an always-on convention → **rule**; isolated/independent execution → **agent**; shared reference data → **reference**.

## Side-by-side portable library

The repository also ships an agent-agnostic library without replacing Claude:

- `.agents/skills/<name>/SKILL.md` — 49 flat Agent Skills. Use `metadata.category`; do not add category subdirectories.
- `.agents/references/` and `.agents/scripts/` — portable shared dependencies. Install the complete `.agents/` tree, not isolated skill folders.
- `.agents/agents/roles.json` — canonical machine-readable neutral role policy input. Adapters interpret it; the JSON and adjacent prompts are not themselves security boundaries.
- `.codex/agents/*.toml` — thin Codex adapters. Provider aliases and Codex dispatch/sandbox syntax stay here.
- `.agents/scripts/run-pi-role.sh` — generic read-only/verification Pi workers. Those boundaries are behavioral because the generic runner is not an OS sandbox; untrusted repository/PR content requires an external sandbox or container. The runner must reject implementation; supervised Pi implementation uses `autorun`'s sandbox launcher.
- `AGENTS.md` — portable project guidance for Codex and Pi.

Neither `.claude/` nor `.agents/` is canonical across harnesses yet. Preserve `.claude/` behavior. When methodology changes, assess both trees explicitly and declare intentional differences in `.agents/manifest.json`; do not mechanically overwrite one from the other. See [ADR 0003](docs/decisions/0003-agent-agnostic-library.md).

### Portable maintenance checks

After changing portable payloads:

1. Regenerate `.agents/catalog.md` when skill metadata or inventory changes: `python3 .agents/scripts/generate-catalog.py`.
2. Refresh checksums with `python3 .agents/scripts/validate-library.py --refresh-manifest`. Add `--accept-inventory-changes` only after reviewing reported additions/removals.
3. Run `python3 .agents/scripts/validate-library.py` and the relevant tests under `.agents/scripts/tests/`.
4. Run the existing Claude skill checker and confirm `git diff -- .claude` contains only separately intended Claude changes.

For a release that upgrades/removes files from an earlier installed version, add the exact released prior manifest SHA-256 to `installation.upgrade_from_manifest_sha256` before refreshing the new manifest. This source-authenticated allowlist is what permits safe prior-only removals. Never hand-edit ownership checksums to bypass validation.

## Authoring conventions

When creating or editing skills, follow the `writing-skills` skill, and:

- **Descriptions are triggers-led.** Start with "Use when…"; describe *when* to reach for the skill, not *what it does*. A workflow summary in the description makes Claude shortcut reading the body.
- **Single source of truth.** Don't restate shared facts across skills — put them in one place and link. The conventional-commit type list is canonical in `git-commit`; the beads model is canonical in `.claude/references/beads.md`; shared checklists live in `.claude/references/`.
- **Cross-link at boundaries** rather than duplicating. Skills that meet (e.g. design vs. implementation, discover vs. prescribe) point to each other instead of overlapping.
- **Scope down.** Include a "When NOT to use" so a skill isn't over-applied to trivial work.
- **No dead links.** Every referenced skill/agent/file must exist. Verify before committing.
- **Avoid name collisions with built-in commands.** Built-ins include `code-review`, `security-review`, `review`, `verify`, `init`, `run`. (That's why this repo uses `senior-review` and `security-scan`.)

## Portability

The Claude implementation must remain self-contained in `.claude/`; the portable implementation must remain self-contained in the complete `.agents/` tree plus optional project adapters. This repo's `CLAUDE.md` is **not** copied — so don't put workflow guidance only here; it belongs in resources that travel. When a Claude skill depends on a `.claude/references/` file, copy that reference with it. Portable consumers install `.agents/` as one unit rather than resolving dependencies piecemeal.

## Workflow state: beads is required

This project uses **beads** as the system of record — there is **no `.docs/` folder and no `context.yaml`**. Workflow skills hard-stop and redirect to `setup-beads` when beads is absent; there is no standalone/conversational fallback. See [docs/decisions/0001-beads-required.md](docs/decisions/0001-beads-required.md) for the rationale. Don't reintroduce step-doc files.

## Commits and PRs

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages and PR titles: `type(scope): description`. No `Co-Authored-By` trailers. After committing, surface the exact message back (see the `git-commit` skill).

## Archive

The previous automated pipeline (the `/feature` orchestrator, step agents, `context.yaml`) is preserved in [`archive/`](archive/) for reference. It is **not** active — don't wire current skills to it. Treat references to `context.yaml`, `.docs/`, the `/feature` orchestrator, or personas in archived material as historical.
