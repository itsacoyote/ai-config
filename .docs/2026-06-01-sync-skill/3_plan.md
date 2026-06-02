# Plan: Sync Skill

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-06-01

## Overview

This is a documentation-shaped feature. The deliverable is one new skill file and one set of edits to the project `README.md`. Two tasks, two commits. No tests, no code, no settings registration — Claude Code discovers skills by directory presence.

The plan resolves the three decisions Research flagged for Plan:

1. **`allowed-tools` shape** — use the enumerated form (~20 `Bash(<cmd> *)` entries) plus `Read`. Rejected the broad `Bash(*)` shape: Sync is a developer-invoked utility against the local environment and the spec's non-destructive contract is best matched by narrow permissions. Adding a new ecosystem later is a one-line edit; that churn cost is acceptable.
2. **README heading** — rename the existing `### PR review skill` section to `### Standalone skills` so `/sync` and `/pr-review` sit in the same table. Lower-overhead future-proofing than adding a second one-row section. This is a single deliberate edit in Task 2.
3. **`Skill(github-tool-preference)` invocation seams** — invoked twice in the SKILL.md prose: once immediately before `git fetch origin`, once immediately before `git pull --ff-only origin <main>`. Both seams sit inside the `## Branch switch and pull` section. The prose wording mirrors `pr-review`'s "Before any `gh` shell-out in this skill, invoke `Skill(github-tool-preference)` …" pattern but is scoped to the git remote operations Sync performs.

The Shared wording section at the bottom of this plan is the Implement agent's source of truth for the dirty-tree prompt, the eight-section final-summary template, and the per-ecosystem install confirmation. Copy-paste, do not paraphrase.

---

## File Map

### New Files

| File | Responsibility | Public Interface |
|------|----------------|------------------|
| `.claude/skills/sync/SKILL.md` | The Sync skill. Frontmatter declares `name`, `description`, `disable-model-invocation: true`, and the enumerated `allowed-tools` list. Prose body describes the workflow: preflight cleanliness check → branch switch and pull → change summary → environment refresh (packages → migrations → `.env` diff → Docker) → project-specific instructions → eight-section final summary → "What this skill will not do" enumeration. | Invoked as `/sync` by the developer. Reads `git status`, `git log`, `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`, `.env.example`, `.env`, and lockfile presence. Runs `git fetch`, `git pull --ff-only`, optionally `git stash push -u`, and per-ecosystem install commands after explicit developer confirmation. Surfaces migration commands and Docker warnings without running them. |

### Modified Files

| File | What Changes | Why |
|------|--------------|-----|
| `README.md` | (1) Rename `### PR review skill` heading (line ~235) to `### Standalone skills` and update the lead-in sentence so both skills are covered. (2) Add a `/sync` row to that table immediately above the existing `/pr-review` row (alphabetical). (3) Add a `Usage:` line for `/sync` matching the `/pr-review` usage-line style. (4) Add `sync/` to the file-reference block at the bottom (line ~322) between `spec/` and `validate/`. | Acceptance criterion: "The skill is documented in `README.md` alongside the other top-level skills". The file-reference block lists every skill directory; omitting `sync/` would leave it incorrect. |

### Deleted Files

None.

---

## Implementation Tasks

Tasks are ordered to land the skill file first (the substantive deliverable), then surface it through the README. Each task ends in exactly one Conventional Commit.

---

### Task 1: Create `.claude/skills/sync/SKILL.md`

**Files:** `.claude/skills/sync/SKILL.md` (new)

**Tests:**

No automated tests. The skill is a Markdown document. Manual verification (deferred to Validate step):

```
- The file exists at the exact path .claude/skills/sync/SKILL.md
- YAML frontmatter parses (no tab characters, no missing colons)
- Frontmatter contains: name, description, disable-model-invocation: true, allowed-tools
- allowed-tools is a single-line space-separated list using the Bash(<cmd> *) glob form (not Bash(<cmd>:*), not bare Bash)
- The eight-section final-summary template appears verbatim in the SKILL.md (see Shared wording below)
- The dirty-tree prompt appears verbatim in the SKILL.md (see Shared wording below)
- The per-ecosystem install confirmation prompt appears verbatim in the SKILL.md (see Shared wording below)
- Skill(github-tool-preference) is invoked at two seams: before `git fetch origin` and before `git pull --ff-only origin <main>`
- A closing "What this skill will not do" section enumerates every non-goal from 1_spec.md
```

**Implementation:**

1. Create the directory `.claude/skills/sync/` (no subdirectories — no `references/`, no `scripts/`, no `template.md`).

2. Write the frontmatter block at the top of `SKILL.md`. Exact field set and order:

   ```yaml
   ---
   name: sync
   description: Bring the local checkout up to date with main before starting feature work — clean-tree check with optional stash, fetch and fast-forward pull, change summary, and detection-driven refresh of dependencies, migrations, .env keys, and Docker. Developer-invoked; never runs destructive git or auto-applies migrations.
   disable-model-invocation: true
   allowed-tools: Read Bash(git *) Bash(gh *) Bash(npm *) Bash(yarn *) Bash(pnpm *) Bash(bun *) Bash(bundle *) Bash(uv *) Bash(poetry *) Bash(pipenv *) Bash(go *) Bash(cargo *) Bash(composer *) Bash(mix *) Bash(docker *) Bash(diff *) Bash(cat *) Bash(ls *) Bash(find *) Bash(grep *)
   ---
   ```

   - `name` is lowercase, matches the directory.
   - `description` starts with a verb, fits the lead-line convention used by `define`, `research`, `pr-review`.
   - `disable-model-invocation: true` is set as a bare lowercase boolean (matches the eight existing skills that use it).
   - `allowed-tools` is one line. The asterisk in `Bash(<cmd> *)` is a literal space + asterisk (matches every existing skill); do not write `Bash(<cmd>:*)` and do not write bare `Bash`.
   - `Read` is the first entry because the skill reads `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`, `.env.example`, `.env`. (Existing skills that touch files declare `Read` explicitly.)

3. Write the body using the section ordering below. Each `##` heading is exact; the prose under each follows `pr-review`'s style — short imperative sentences, fenced exact-text blocks for prompts and commands, accepted-input tables for prompts that take user input.

   **Section ordering:**
   1. `# Sync` (H1)
   2. `## What this does` — single paragraph stating the workflow arc: Preflight → Pull → Change summary → Refresh → Final summary. Mirrors `pr-review`'s opening paragraph.
   3. `## Preflight` — covers `git rev-parse --is-inside-work-tree`, main-branch detection (`init.defaultBranch` → `origin/HEAD` → fallback `main`), `git status --porcelain`, the dirty-tree prompt (use the exact text from Shared wording below), and the recorded "current branch" for the final summary.
   4. `## Branch switch and pull` — checkout the detected main, then **before `git fetch origin`** the prose says: "Before this `git` operation, invoke `Skill(github-tool-preference)` to confirm `git` is the right tool." Then capture `git rev-parse <main>` as the pre-pull SHA, then **before `git pull --ff-only origin <main>`** invoke `Skill(github-tool-preference)` again with the same wording. Document the failure path: print exact stderr, do not retry with `--rebase` or `--no-ff`.
   5. `## Change summary` — `git log --oneline --no-merges <pre-pull-sha>..HEAD`, capped at 20 with `+N more` footer; "no new commits" fallback verbatim.
   6. `## Environment refresh: package managers` — port the lockfile table and the JS-runner precedence table from `1_spec.md` verbatim. Document the per-ecosystem confirmation prompt (use the exact text from Shared wording below). Note pip is surfaced only.
   7. `## Environment refresh: migrations` — port the migration-tool table from `1_spec.md` verbatim, including the `<js-runner>` substitution rules. Migrations are never auto-run.
   8. `## Environment refresh: .env diff` — keys only, never values; `.env.example` → `.env.sample` → `.env.template` fallback; "no local `.env`" message when only the example is present.
   9. `## Environment refresh: Docker` — compose detection list, the warning text, never run any `docker compose` subcommand.
   10. `## Project-specific instructions` — read `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`; look for `Sync` / `Post-pull` / `After pulling` / `Bootstrap` sections (case-insensitive); print verbatim.
   11. `## Final summary` — render the eight-section template as a fenced exact-text block (use the exact text from Shared wording below).
   12. `## Errors and exits` — every external command's exit is checked; non-zero halts and prints the failing command and stderr verbatim.
   13. `## What this skill will not do` — bullet enumeration of every non-goal from `1_spec.md` § Non-Goals plus the explicit "Do not" forms (no `git reset --hard`, no `git clean`, no `git checkout -- <path>`, no auto-migrate, no `.env` writes, no `docker compose pull`/`build`, no merge-conflict handling, no non-`origin` remotes, no non-git VCS, never invoked from a pipeline agent, never persists state).

4. For every interactive prompt (dirty-tree and per-ecosystem install), follow the `pr-review` shape exactly:
   - The exact prompt text inside a fenced code block.
   - An "Accepted inputs" table with one row per accepted token and one final row `anything else → re-prompt the current question without advancing`.
   - A sentence under the table confirming the skill never defaults to a destructive action.

5. For every command Sync runs (`git fetch`, `git pull --ff-only`, `git stash push -u -m "sync: auto-stash <timestamp>"`, the install commands), put the command in a fenced code block. For surfaced-only commands (migrations, `docker compose pull`, pip), wrap them in single backticks within prose — never put them in a fenced block that could be mistaken for "the skill runs this".

6. Verify before commit:
   - `head -1 .claude/skills/sync/SKILL.md` returns `---` (frontmatter open).
   - The Shared wording section's three exact-text blocks appear verbatim in the file.
   - `Skill(github-tool-preference)` appears at least twice in the prose.
   - No `Bash(*)` and no `Bash(<cmd>:*)` patterns.

**Commit:** `feat(skills): add sync skill for pre-feature local refresh`

---

### Task 2: Document the Sync skill in `README.md`

**Files:** `README.md`

**Tests:**

No automated tests. Manual verification:

```
- The heading `### PR review skill` is replaced with `### Standalone skills`.
- The lead-in sentence under the renamed heading covers both /sync and /pr-review (e.g. "Invoke directly — not part of the `/feature` pipeline.").
- The table under the renamed heading has two rows: /sync (above) and /pr-review (below), alphabetical.
- A "Usage:" line follows the table covering both skills, or each skill gets its own short usage line.
- The file-reference block at the bottom of README.md lists `sync/` between `spec/` and `validate/`.
- The "How it works" pipeline diagram and the "What each step does" section are unchanged — /sync is not in the pipeline.
```

**Implementation:**

1. Rename the heading `### PR review skill` (currently around line 235) to `### Standalone skills`. Update the lead-in sentence to read: `Invoke directly — not part of the `/feature` pipeline.` (This sentence already exists and applies equally to both skills; confirm it's still the single line under the new heading.)

2. Add a `/sync` row to the table under the renamed heading, immediately above the existing `/pr-review` row (alphabetical by skill name). Use the same column shape (`| Skill | What it does |`). One-line description:

   ```
   | `/sync`      | Bring your local checkout up to date with `main` before starting feature work — clean-tree check (optional stash), fetch + fast-forward pull, change summary, and detection-driven refresh of dependencies, migrations, `.env` keys, and Docker. Never runs destructive git, never auto-applies migrations, never writes `.env`. |
   ```

3. After the table, keep the existing `Usage:` line for `/pr-review` and add a parallel one-liner for `/sync` above it (or merge both into one paragraph). The simplest form:

   ```
   Usage: `/sync` (takes no arguments) and `/pr-review <pr-number>` (e.g. `/pr-review 1250`; invoke without an argument to be prompted for a PR number).
   ```

   If two separate lines reads more clearly when implementing, use two lines. The constraint is that both skills get a usage note.

4. In the file-reference block (around line 322), insert `sync/` between `spec/` and `validate/`. Match the existing column-aligned comment style:

   ```
       ├── sync/              # /sync — pre-feature local refresh
   ```

   Keep the tree-drawing characters (`├──` / `└──`) consistent — the last entry uses `└──`, all earlier entries use `├──`. Confirm `validate/` and `pr-review/` and `agent-context/` still have correct prefix characters after the insertion.

5. Verify before commit:
   - `grep -n "### Standalone skills" README.md` finds exactly one match.
   - `grep -n "### PR review skill" README.md` finds zero matches.
   - `grep -n "/sync" README.md` finds at least two matches (table row + usage line).
   - `grep -n "sync/" README.md` finds at least one match (file-reference block).
   - The pipeline diagram and "What each step does" sections are unchanged (no incidental edits).

**Commit:** `docs(readme): document /sync skill alongside /pr-review`

---

## Out of Scope

Anything not in the two files above is excluded.

- **No `.claude/settings.json` edit.** Skills are discovered by directory presence; settings.json contains only hooks. Research confirmed (lines 147–152 of `2_research.md`).
- **No `.claude/settings.local.json` edit.** Bash permissions for `git`, `gh`, package managers, and `docker` are either already allowed for the user's session or will be granted on first run; the skill itself declares its needs via `allowed-tools`.
- **No new agent file.** Sync is a skill, not a pipeline agent. There is no `define`/`research`-style agent for it.
- **No subdirectories under `.claude/skills/sync/`.** No `references/`, no `scripts/`, no `template.md` — the skill's output is printed to the user, never written to disk.
- **No `.docs/` writes at runtime.** The skill is stateless; the spec is explicit (line 184) and `pr-review` sets the precedent (line 102 of `pr-review/SKILL.md`).
- **No changes to existing skills.** `github-tool-preference`, `pr-review`, `feature`, and all pipeline skills are unaffected.
- **No CLAUDE.md edit.** The project CLAUDE.md does not enumerate skills — it points to `/feature` as the entry point and lets the README handle skill discovery.

---

## Shared wording

This is the source of truth for the Implement agent. Copy these blocks verbatim into `SKILL.md` — do not paraphrase, do not reorder, do not change punctuation. Em-dashes (`—`, U+2014) are intentional and match the punctuation style used in `pr-review/SKILL.md`.

### Dirty-tree two-option prompt

Render this inside `## Preflight` as a fenced code block, then the accepted-inputs table immediately below.

````
Your working tree has uncommitted changes:

<list of dirty paths from `git status --porcelain`>

How do you want to proceed?

  s  Stash and continue — run `git stash push -u -m "sync: auto-stash <timestamp>"`,
     then proceed with the rest of the sync. The stash ref will be shown in the
     final summary so you can `git stash pop` to recover it.

  h  Let me handle it — stop now without running any further command. Commit
     or discard the changes yourself, then rerun `/sync`.
````

**Accepted inputs:**

| Input | Effect |
|-------|--------|
| `s` / `stash` | Run `git stash push -u -m "sync: auto-stash <timestamp>"`. Capture the stash ref from stdout. Proceed to ## Branch switch and pull. Surface the stash ref and the `git stash pop` recovery command in the final summary's **Branch state** section. |
| `h` / `handle` | Stop immediately. Do not run `git checkout`, `git stash`, install, migration, or any further command. Leave the working tree exactly as it was. |
| anything else | Re-prompt the current question without advancing. Do not default to either option. Never run a destructive recovery (no `git reset --hard`, no `git clean`, no `git checkout -- <path>`) regardless of input. |

If `git stash` itself exits non-zero (e.g. partial-merge state, unmerged paths), print the `git` stderr verbatim and stop. Do not retry. Do not attempt any other recovery.

### Per-ecosystem install confirmation prompt

Render this inside `## Environment refresh: package managers` as a fenced code block, then the accepted-inputs table immediately below. Replace `<ecosystem>` and `<command>` per detected lockfile.

````
Detected <ecosystem> lockfile. Run `<command>` now?

  yes   Run the install for this ecosystem and continue.
  no    Skip this ecosystem. Continue to the next one.
  all   Run the install for this ecosystem and every remaining detected ecosystem
        without further prompts.
````

**Accepted inputs:**

| Input | Effect |
|-------|--------|
| `yes` / `y` | Run `<command>`. Check the exit code. On non-zero, print the stderr and stop. On zero, mark this ecosystem as **ran** in the final summary's **Dependencies refreshed** section. |
| `no` / `n` | Skip without running. Mark this ecosystem as **skipped** in the final summary. Continue to the next detected ecosystem. |
| `all` / `a` | Run `<command>` for this ecosystem and every remaining detected ecosystem in turn without re-prompting. Each install's exit is still checked; a non-zero exit stops the skill at that command. |
| anything else | Re-prompt the current question without advancing. |

If the binary implied by `<command>` is not on `PATH`, do not show this prompt for that ecosystem. Mark it as **not installed** in the final summary and continue to the next.

### Eight-section final summary template

Render this inside `## Final summary` as a fenced code block. Headers are exact. Placeholder text shows what each section contains. Section ordering is contractual — do not reorder.

````
═══════════════════════════════════════════════════════════════════
  Sync summary
═══════════════════════════════════════════════════════════════════

1. Branch state
   <previous-branch> → <main-branch>
   <pre-pull-sha> → <post-pull-sha>
   <N> new commits on <main-branch>.
   [If stashed:] Stashed uncommitted changes as <stash-ref>.
                 Recover with: git stash pop

2. Recent commits
   <git log --oneline --no-merges output, capped at 20 lines>
   [If truncated:] +<N> more
   [If no new commits:] main is already up to date — no new commits since last sync.

3. Dependencies refreshed
   <ecosystem>: ran | skipped | not installed
   <ecosystem>: ran | skipped | not installed
   [Repeat per detected ecosystem. pip is always shown as "surfaced only".]

4. Migrations to consider
   <tool>: <recommended command using detected <js-runner> where applicable>
   <tool>: <recommended command>
   [Repeat per detected migration tool. None of these were executed.]

5. Environment variables
   <list of keys defined in .env.example but missing from .env, by name only>
   [If .env is missing entirely:] No local .env found — copy .env.example to .env and fill in values.
   [If all keys present:] All keys present.

6. Docker
   [If compose file detected:] Compose detected — local images may be stale.
   Run `docker compose pull` and `docker compose build` if your stack expects
   current upstream images.
   [If no compose file:] No compose file detected.

7. Project-specific steps
   [Verbatim content of the matching section from CLAUDE.md / AGENTS.md /
    .cursorrules / .windsurfrules, if any. If none, "No project-specific
    sync steps found in CLAUDE.md, AGENTS.md, .cursorrules, or .windsurfrules."]

8. Next step
   Ready to start. Run `/feature` to begin a new feature, or
   `git checkout <previous-branch>` to return to your prior work.

═══════════════════════════════════════════════════════════════════
````

Use the same box-drawing characters (`═`) at the top and bottom. The numeric prefixes `1.` through `8.` are required — they match the spec's "fixed order" wording in § Final summary. The em-dash (`—`) in section 5's no-.env message is U+2014, matching the punctuation style used in `pr-review/SKILL.md`.
