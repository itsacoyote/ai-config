# Validation: Sync Skill

**Date:** 2026-06-02
**Spec:** [1_spec.md](1_spec.md)

## Senior Code Review

**Verdict:** Approved
**Iterations:** 2

### Findings and fixes

- [Seam 1 of `Skill(github-tool-preference)` placed after `git checkout` rather than immediately before `git fetch origin`] → Moved the seam invocation to appear after `git rev-parse <main>` (pre-pull SHA capture) and immediately before `git fetch origin`, matching the plan's exact specification. Committed as `fix(skills): move github-tool-preference seam to immediately before git fetch`.

All other checks passed on first pass:
- Frontmatter field set and order (`name`, `description`, `disable-model-invocation: true`, `allowed-tools`) matches the plan exactly.
- `allowed-tools` uses the enumerated `Bash(<cmd> *)` form — no `Bash(*)` and no `Bash(<cmd>:*)` patterns.
- `disable-model-invocation: true` is present as a bare lowercase boolean.
- Three verbatim blocks (dirty-tree prompt, per-ecosystem install confirmation, eight-section final summary) match the plan's Shared wording exactly — em-dashes (U+2014), `═══` border characters (U+2550), numeric `1.`–`8.` prefixes, and all placeholder wording.
- Section ordering (12 H2 sections) matches the plan's specified sequence.
- `Skill(github-tool-preference)` appears at exactly two seams inside `## Branch switch and pull` after fix.
- README has no stray `### PR review skill` heading; `/sync` row is alphabetically above `/pr-review`.
- `sync/` is inserted in the file-reference block between `spec/` and `analyze-code/`.

## QA Review

**Verdict:** Approved
**Coverage achieved:** 100% (19/19 acceptance criteria)
**Iterations:** 1

### Findings and fixes

No findings. All 19 acceptance criteria from `1_spec.md` verified against SKILL.md prose on first pass:

- AC1: Frontmatter fields present and correct.
- AC2: Documented in README alongside `/feature` and `/pr-review`.
- AC3: `git fetch origin` + `git pull --ff-only` + eight-section summary present.
- AC4: Dirty-tree check shows paths, two options only (stash/handle), no discard.
- AC5: `git stash push -u -m "sync: auto-stash <timestamp>"` command, stash ref surfaced in Branch state.
- AC6: `h` / handle stops immediately with no further commands.
- AC7: Invalid input re-prompts without defaulting.
- AC8: `git rev-parse --is-inside-work-tree` guard with clear error message.
- AC9: `git pull --ff-only` failure prints exact stderr and stops.
- AC10: Per-ecosystem confirmation prompt, independent detection per lockfile.
- AC11: Migration tools surface recommended commands only — never auto-run.
- AC12: Node migration tools use detected JS runner (`bunx`/`pnpm dlx`/`yarn`/`npx`).
- AC13: `.env.example` vs `.env` key-name comparison, values never read or printed.
- AC14: Compose file detection triggers warning; no `docker` command runs.
- AC15: `CLAUDE.md` `Sync` section printed verbatim under Project-specific steps.
- AC16: `git log` capped at 20, `+<N> more` footer when truncated.
- AC17: "main is already up to date" message when no new commits.
- AC18: Hard constraints enumerated — no `.env` writes, no `git reset`, no auto-migrate, no `docker compose` subcommands.
- AC19: Every external command exit checked; non-zero halts and prints failing command + stderr.

Non-goals from spec are fully covered in `## What this skill will not do`.
Constraints section of spec is reflected in frontmatter (`allowed-tools` scope) and the non-do section.

## E2E Test Run

**Command:** none (no test suite configured)
**Result:** not configured
**Fix iterations:** 0

This is a documentation-only feature (one new Markdown skill file, one README edit). There is no runtime code and no test suite to run.

## Evidence

No `output_artifacts` were declared in `context.yaml` (documentation-only feature with no screenshots or recordings). The implementation artifacts are:

- `.claude/skills/sync/SKILL.md` — the new Sync skill; demonstrates all user stories (pre-feature checkout refresh, dirty-tree guard with stash option, git log summary of what landed, polyglot lockfile detection, `.env` key diff, Docker warning).
- `README.md` — updated `### Standalone skills` section with `/sync` row and usage line; `sync/` entry in the file-reference block.
