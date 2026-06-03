# Research: Sync Skill

**Spec:** [1_spec.md](1_spec.md)
**Date:** 2026-06-01

## Summary

The `sync` skill is a single-file addition under `.claude/skills/sync/SKILL.md` plus one README entry. There is no library code to study, no test scaffolding to mimic, and no registration step — Claude Code discovers skills by directory presence. Research therefore concentrated on the conventions of the 21 existing skills in `.claude/skills/`: frontmatter fields, the exact `allowed-tools` mini-language, prose voice, how confirmation prompts are specified, and how the repo's `README.md` documents existing skills. The closest analog is `pr-review/SKILL.md` — a developer-invoked, multi-step skill with `disable-model-invocation: true`, shell-heavy `allowed-tools`, and interactive yes/no prompts. The lightweight end (`git-commit`, `find-patterns`) confirms that frontmatter has no required fields beyond `name` and `description`. One spec assumption could not be confirmed from the codebase alone and is flagged below for Plan.

## Codebase Areas Affected

- `.claude/skills/sync/SKILL.md` — the new skill file; this is the only file the skill itself contributes.
- `README.md` — needs one new row in the appropriate skills table so `/sync` is discoverable alongside `/feature` and `/pr-review`.

No other files are touched. There is no central registry, no `index.json`, no `settings.json` skill list — Claude Code discovers `.claude/skills/<name>/SKILL.md` purely by directory presence (confirmed in the Architectural Context section below).

## Reusable Code

There is no library code or shared utility module to reuse. Skills in this repo are self-contained Markdown prose files; they delegate to other skills via `Skill(...)` and to agents via the `Agent` tool, but they do not import or share code. The reuse here is prose-shaped, not code-shaped:

### Closest analog skills (read as templates, not imports)

- **`pr-review/SKILL.md`** — strongest pattern match. Developer-invoked (`disable-model-invocation: true`), shell-heavy (`Bash(gh *) Bash(git *)`), multi-step workflow with explicit confirmation prompts, and a "What this skill will not do" section that hard-codes non-destructive guarantees. The Sync skill should mirror this structure exactly: a top-level "What this does" paragraph, ordered sections per phase (Preflight → Pull → Change summary → Refresh steps → Final summary), and a closing "What this skill will not do" block enumerating the destructive operations the spec forbids.
- **`git-commit/SKILL.md`** — minimal frontmatter (only `name` and `description`). Shows the lower bound: no `allowed-tools`, no `argument-hint`, no `disable-model-invocation`. Confirms those fields are all optional. Sync needs more than this minimum, but it's a useful reference for what's required vs. additive.
- **`find-patterns/SKILL.md`** — single-paragraph intent followed by bulleted "what to look for" / "what to report" sections. Shows the lightweight prose voice used across the repo.
- **`research/SKILL.md`** and **`define/SKILL.md`** — examples of `disable-model-invocation: true` paired with a narrow `allowed-tools` whitelist. Confirms the pairing pattern Sync needs.

### Skill-delegation primitives the Sync skill must use

- **`Skill(github-tool-preference)`** — must be invoked before each `gh` (and per the project's CLAUDE.md and the spec's Constraints section, before each `git`-related GitHub action). `pr-review/SKILL.md` does this explicitly ("Before any `gh` shell-out in this skill, invoke `Skill(github-tool-preference)` to confirm `gh` is the correct tool."). Sync will invoke it before `git fetch`, `git pull`, and any other remote-touching git operation.
- **`Skill(git-commit)`** — not needed by Sync. The spec is explicit that Sync never commits. The skill-check hook in `.claude/hooks/skill-check.sh` injects a reminder when `git commit` is about to run; Sync never triggers it because it never runs `git commit`.

## Gaps: What Needs to Be Created

- **`.claude/skills/sync/SKILL.md`** — the skill itself. Frontmatter + the eight-section prose workflow described in `1_spec.md`. No subdirectories, no `references/`, no `scripts/`.
- **README.md entry** — one new row in the appropriate skills table (see "README documentation pattern" below for the exact pattern).

Nothing else is created. No artifacts directory contents, no settings changes, no agent files.

## Patterns and Conventions to Follow

### Skill file structure

Every skill in `.claude/skills/` follows the same shape:

```text
.claude/skills/<name>/
└── SKILL.md
```

A handful of skills add subdirectories (`impeccable/scripts/`, `impeccable/references/`, `plan/template.md`, `research/template.md`, `security-review/references/`, `spec/template.md`, `validate/references/`), but Sync needs none of these — its output is printed to the user, not written to disk, and there is no companion template.

The Markdown file itself is a YAML frontmatter block followed by prose with `##` section headers. No skill in this repo embeds executable code outside fenced code blocks meant for the user to read.

### Frontmatter fields used across the repo

Fields actually seen in the 21 existing `SKILL.md` files:

| Field                       | Used by                                              | Notes                                                                                                |
| --------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `name`                      | all skills                                           | Lowercase, hyphenated, matches the directory name.                                                   |
| `description`               | all skills                                           | One or two sentences. Starts with a verb or "Use when ...".                                          |
| `allowed-tools`             | 14 of 21 skills                                      | Space-separated single-line list, or YAML array form (only `impeccable` uses the array form).        |
| `disable-model-invocation`  | 8 skills (`agent-context`, `define`, `feature`, `implement`, `plan`, `pr-review`, `research`, `validate`) | Boolean. When `true`, the skill runs only on explicit `/<name>` invocation, never via auto-trigger. |
| `argument-hint`             | 5 skills (`analyze-code`, `feature`, `find-patterns`, `impeccable`, `pr-review`, `web-search`) | A quoted string hint shown next to the slash command.                                                |
| `user-invocable`            | 4 skills (`impeccable: true`, three `verify-*: false`) | Distinct from `disable-model-invocation`. The three `verify-*` skills set `false` to mark them as internal-only. |
| `version`, `license`        | only `impeccable`                                    | Used because that skill is a vendored upstream package.                                              |

The Sync skill needs: `name`, `description`, `disable-model-invocation: true` (per spec), and `allowed-tools`. It does not need `argument-hint` (no positional argument), `user-invocable`, `version`, or `license`.

### `allowed-tools` syntax

The repo uses a single mini-language for `allowed-tools`, on one line, space-separated. Bash sub-patterns use the `Bash(<pattern>)` form where `<pattern>` is a glob:

| Form                          | Used by                                         | Meaning                                                |
| ----------------------------- | ----------------------------------------------- | ------------------------------------------------------ |
| `Bash(*)`                     | `implement`, `validate`                         | Unrestricted Bash.                                     |
| `Bash(find *)`                | `analyze-code`, `find-patterns`, others         | Only `find` invocations.                               |
| `Bash(grep *)`                | `analyze-code`, `find-patterns`, others         | Only `grep` invocations.                               |
| `Bash(git log *)`             | `define`, `research`, `verify-completeness`     | Only `git log` (read-only) invocations.                |
| `Bash(git show *)`            | `research`                                      | Only `git show`.                                       |
| `Bash(git blame *)`           | `research`                                      | Only `git blame`.                                      |
| `Bash(git diff *)`            | `verify-coherence`, `verify-completeness`, `verify-correctness` | Only `git diff`.                                       |
| `Bash(git *)`                 | `pr-review`                                     | All `git` subcommands.                                 |
| `Bash(gh *)`                  | `pr-review`                                     | All `gh` subcommands.                                  |

Observations relevant to Sync:

- The pattern is `Bash(<command> *)` with a literal space and asterisk — not `Bash(<command>:*)` (that colon syntax does not appear anywhere in this repo's skills) and not bare `Bash`.
- Multiple `Bash(...)` entries are stacked on the same line (e.g. `Bash(find *) Bash(grep *) Bash(git log *)`).
- When a tool needs broad shell access (`implement`, `validate`), `Bash(*)` is used rather than enumerating dozens of binaries.
- Only `impeccable` uses the YAML array form (with leading `-`), and only because it shells out to `npx impeccable *`. Single-line form is the strong convention.

For Sync's needs (git read + git write to local working tree + git fetch/pull + lockfile detection + package-manager installs + `.env` diff + `docker compose` for detection only + reading `CLAUDE.md` and adjacent files), the spec lists: `git`, `gh`, package-manager binaries, `docker compose`, `diff`, `cat`, `ls`, `find`, `grep`. The repo convention says either enumerate each (`Bash(git *) Bash(gh *) Bash(npm *) Bash(yarn *) Bash(pnpm *) Bash(bun *) Bash(bundle *) Bash(uv *) Bash(poetry *) Bash(pipenv *) Bash(go *) Bash(cargo *) Bash(composer *) Bash(mix *) Bash(diff *) Bash(cat *) Bash(ls *) Bash(find *) Bash(grep *)`) — long, but precise — or use `Bash(*)` as `implement` and `validate` do. Plan will need to pick one; the spec doesn't dictate. The narrower enumeration is the safer default for a skill the developer runs against their local environment, but it has practical churn cost (adding a new ecosystem later requires editing the skill). Plan should recommend the trade-off explicitly.

`Read` should also appear in `allowed-tools` (the skill reads `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.windsurfrules`, `.env.example`, `.env`). All but two of the existing skills that touch files declare `Read` explicitly.

### `disable-model-invocation`

The spec calls for `disable-model-invocation: true`. This field **is** used in this codebase — eight existing skills set it (`agent-context`, `define`, `feature`, `implement`, `plan`, `pr-review`, `research`, `validate`). The field is set as a bare lowercase boolean: `disable-model-invocation: true`. The convention is well established; no flag for Plan to verify against external docs.

### Prose voice and structure

Every multi-step skill follows the same prose pattern:

1. `# <Skill Name>` H1 (sometimes preceded by a brief overview, sometimes not).
2. A short "What this does" paragraph (`pr-review`, `validate`) or a single-paragraph intent (`find-patterns`, `analyze-code`).
3. Ordered `##` sections per phase. `pr-review` uses: Input validation → Fetch the PR → Delegate → Triage findings → Post step → What this skill will not do → Refusal.
4. Tables for enumerations (input/effect, signal/tool/command). `pr-review`'s triage input table is a strong reference for Sync's dirty-tree prompt table (stash/handle/anything-else mapping).
5. Fenced code blocks for exact commands the skill will run, exact prompt text the developer will see, and exact error messages.
6. A closing "What this skill will not do" section that hard-codes the non-goals from the spec. `pr-review` does this explicitly — every spec non-goal becomes a "Do not …" bullet so the prose itself enforces the contract.

Sync should follow this exact arc. The "What this skill will not do" section is especially important here because the spec is strict about non-destructive behavior (no `git reset`, no `git clean`, no `git checkout -- <path>`, no auto-migrate, no `.env` writes, no `docker compose pull`).

### Confirmation prompts

`pr-review` shows the canonical pattern: print the exact prompt text inside a fenced code block, list accepted inputs in a table, and specify what each input does. The spec's dirty-tree prompt (`s` / `h`) and per-ecosystem install prompts (`yes` / `no` / `all`) should be specified in the same shape — exact wording, exact accepted tokens, and explicit "any other input re-asks" handling.

### README documentation pattern

The repo's `README.md` documents skills in tables under "Pipeline skills", "Reviewer agents", "Utility skills", and "PR review skill" headings (README.md lines 198–243). The PR review skill's section is the relevant precedent because `/sync` is also "Invoke directly — not part of the `/feature` pipeline."

The PR review section in README.md is:

```markdown
### PR review skill

Invoke directly — not part of the `/feature` pipeline.

| Skill        | What it does                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------ |
| `/pr-review` | AI-assisted review of a GitHub PR — fetches diff, ... [continues].  |

Usage: `/pr-review <pr-number>` (e.g. `/pr-review 1250`). Invoke without an argument to be prompted for a PR number.
```

For `/sync`, Plan will either (a) add a new heading "Sync skill" with its own one-row table immediately after the PR review skill section, or (b) rename the PR review section to a broader "Developer-invoked skills" / "Standalone skills" heading and add `/sync` as a second row of the same table. The spec doesn't constrain which — pick the option that reads cleanly when there are two such skills (option (b) is the lower-overhead future-proofing).

Wherever it lands, the entry should follow the column shape of the existing tables: `| /sync | <one-line description> |`. No "Usage:" footer is required because `/sync` takes no arguments, but a one-line note matching the PR review section's style would keep parity.

Note: the bottom of README.md has a `File reference` block (lines 293–324) that lists every skill directory under `.claude/skills/`. Plan should add `sync/` to that list as well in alphabetical order between `spec/` and `validate/`.

## Architectural Context

### Skill discovery

Claude Code discovers skills purely by directory presence: any `<name>/SKILL.md` under `.claude/skills/` is registered automatically. There is no `index.json`, no entry in `settings.json`, no agent file, no central registry. Confirmed by:

- `.claude/settings.json` contains only a `hooks` block (a `PreToolUse` hook on `Bash` that runs `.claude/hooks/skill-check.sh`). No skills are enumerated.
- `.claude/settings.local.json` contains only a `permissions.allow` array for specific Bash commands. No skills are enumerated.
- The `feature` skill, `pr-review` skill, and all the verifier skills were added by simply dropping a directory + `SKILL.md` into `.claude/skills/` — there is no PR or commit that adds a registration entry for any of them.

This means the Sync skill is fully self-contained: drop `.claude/skills/sync/SKILL.md` into place, update `README.md`, commit. Nothing else.

### Skill-check hook

`.claude/hooks/skill-check.sh` runs before every Bash tool call and injects a reminder when the Bash command starts with `git ... commit ...` or `gh pr create|edit`. It does not block — it adds a `systemMessage` and an `additionalContext` directive asking Claude to invoke `Skill(git-commit)` or `Skill(create-pr)` first. The Sync skill never runs `git commit` and never creates/edits PRs, so this hook will not fire during a `/sync` run. Plan does not need to coordinate with the hook.

### Project constraint: `Skill(github-tool-preference)` before `gh`

`CLAUDE.md` (the project root one, lines under "GitHub tool preference") says: "Invoke `Skill(github-tool-preference)` before any `gh` or `mcp__github__*` call to confirm the right tool is chosen." `pr-review` follows this literally. Sync should follow the same convention before `git fetch` / `git pull` from `origin` — those touch the GitHub remote and the project's tool-preference rule is intended to cover them too. Plan should call this out so the SKILL.md prose includes the invocation at the right step boundaries.

### Conventional Commits + no AI attribution

`CLAUDE.md` and `git-commit/SKILL.md` require Conventional Commits format and forbid `Co-Authored-By` trailers and AI attribution. Sync itself never commits, so this doesn't affect the skill's runtime behavior — but it does affect the commit that introduces the skill. The commit message for the Implement step will be conventional (e.g. `feat(skills): add sync skill for pre-feature local refresh`), with no co-author trailer.

## Key Insights for the Planner

1. **One file plus a README edit.** The deliverable is exactly `.claude/skills/sync/SKILL.md` and one or two updates to `README.md`. No subdirectories, no template files, no settings changes, no hooks.

2. **`pr-review/SKILL.md` is the structural template.** Mirror its section ordering, table-driven prompts, fenced exact-command blocks, and closing "What this skill will not do" enumeration. The spec's eight-section final summary maps cleanly onto the same structural shape.

3. **`allowed-tools` trade-off needs an explicit Plan decision.** Two viable shapes:
   - **Enumerated**: `Read Bash(git *) Bash(gh *) Bash(npm *) Bash(yarn *) Bash(pnpm *) Bash(bun *) Bash(bundle *) Bash(uv *) Bash(poetry *) Bash(pipenv *) Bash(go *) Bash(cargo *) Bash(composer *) Bash(mix *) Bash(docker *) Bash(diff *) Bash(cat *) Bash(ls *) Bash(find *) Bash(grep *)`. Safer, but every new ecosystem requires editing the skill.
   - **Broad**: `Read Bash(*)`. Simpler, matches `implement` and `validate`, but gives the skill unrestricted shell access — which is overbroad for a read-mostly utility.
   Recommend the enumerated form because Sync is developer-invoked against the local environment and the narrower scope better matches the spec's non-destructive contract. Plan should make this the default and note that the list grows when new ecosystems are added.

4. **`Skill(github-tool-preference)` invocation points.** Two natural seams: before `git fetch origin` and before `git pull --ff-only origin <main>`. The SKILL.md prose should include "Before this `git` operation, invoke `Skill(github-tool-preference)` to confirm `gh`/`git` is the right tool." at both seams, mirroring the `pr-review` pattern.

5. **README.md gets two edits, not one.** The skills table (current PR review section) and the file-reference block at the bottom of the README both need a row for `sync/`. Easy to miss the second.

6. **Confirmation-prompt prose pattern is fixed.** Specify the exact prompt text the developer will see in a fenced block, then specify the accepted tokens in a table with an "anything else re-prompts" row — exactly as `pr-review` does for its keep/drop/edit triage. Use this shape for both the dirty-tree `s`/`h` prompt and the per-ecosystem `yes`/`no`/`all` prompts.

7. **Final-summary section ordering is contractual.** The spec fixes the eight-section order; the SKILL.md should render that as either a numbered list (matching the spec) or a literal printable template inside a fenced block so the implementer has zero room to drift on the wording or sequence.

8. **No state, no persistence.** The spec is clear, and the codebase has no precedent for skills persisting state (the closest is `pr-review`'s explicit "Never persist it to disk. Never write to `.docs/` for this skill" line, which Sync should adopt verbatim with `.docs/` and any other persistence target struck out).

## Artifacts

None. No reference files, schemas, or external diagrams were needed. The spec is fully self-contained and the existing skills in `.claude/skills/` are the only references.

## Open Questions

None blocking. One trade-off (broad vs. enumerated `allowed-tools`) is flagged in **Key Insights** #3 for Plan to resolve explicitly — both options are valid per the repo's conventions; the recommendation is the enumerated form.
