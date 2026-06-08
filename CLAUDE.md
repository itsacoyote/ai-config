# CLAUDE.md

Guidance for working **in this repository**. This repo is a **portable library** of Claude Code skills, agents, rules, and references that get copied into other projects. This file documents how to maintain that library — it does **not** travel to target projects (see the README for what to paste into a project's own `CLAUDE.md`).

For the catalog of skills/agents and the feature workflow they implement, see [README.md](README.md).

## What lives where

- `.claude/skills/<name>/SKILL.md` — a skill (methodology/reference Claude loads when relevant). Supporting files live alongside it.
- `.claude/agents/<name>.md` — a subagent: a **thin** wrapper that runs a skill in an isolated context. Methodology stays in the skill, not the agent.
- `.claude/rules/<name>.md` — an always-on convention (auto-applied), for rules that should apply without being invoked.
- `.claude/references/<name>.md` — shared knowledge multiple skills point to (kept in one place so it doesn't drift).

Decide by intent: a discoverable technique → **skill**; an always-on convention → **rule**; isolated/independent execution → **agent**; shared reference data → **reference**.

## Authoring conventions

When creating or editing skills, follow the `writing-skills` skill, and:

- **Descriptions are triggers-led.** Start with "Use when…"; describe *when* to reach for the skill, not *what it does*. A workflow summary in the description makes Claude shortcut reading the body.
- **Single source of truth.** Don't restate shared facts across skills — put them in one place and link. The conventional-commit type list is canonical in `git-commit`; the beads model is canonical in `.claude/references/beads.md`; shared checklists live in `.claude/references/`.
- **Cross-link at boundaries** rather than duplicating. Skills that meet (e.g. design vs. implementation, discover vs. prescribe) point to each other instead of overlapping.
- **Scope down.** Include a "When NOT to use" so a skill isn't over-applied to trivial work.
- **No dead links.** Every referenced skill/agent/file must exist. Verify before committing.
- **Avoid name collisions with built-in commands.** Built-ins include `code-review`, `security-review`, `review`, `verify`, `init`, `run`. (That's why this repo uses `senior-review` and `security-scan`.)

## Portability

Everything must be self-contained in `.claude/` so it works after a copy-paste into another project. This repo's `CLAUDE.md` is **not** copied — so don't put workflow guidance only here; it belongs in the skills/agents/rules/references that travel. When a skill depends on a `.claude/references/` file, that file must be copied alongside it.

## Workflow state: beads, not files

This project uses **beads** as the system of record when available, and conversational tracking otherwise — there is **no `.docs/` folder and no `context.yaml`**. Workflow skills must stay dual-mode (fully usable standalone, enhanced when `.beads/` exists) by following `.claude/references/beads.md`. Don't reintroduce step-doc files.

## Commits and PRs

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages and PR titles: `type(scope): description`. No `Co-Authored-By` trailers. After committing, surface the exact message back (see the `git-commit` skill).

## Archive

The previous automated pipeline (the `/feature` orchestrator, step agents, `context.yaml`) is preserved in [`archive/`](archive/) for reference. It is **not** active — don't wire current skills to it. Treat references to `context.yaml`, `.docs/`, the `/feature` orchestrator, or personas in archived material as historical.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
