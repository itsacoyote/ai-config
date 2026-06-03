# Research: Iterative PR Review Skill

**Spec:** [1_spec.md](1_spec.md)
**Date:** 2026-06-02

## Summary

This feature edits two existing files in place — `.claude/skills/pr-review/SKILL.md` and `.claude/agents/code-reviewer.md` — to add follow-up-mode behavior to `/pr-review <N>` and to give the `code-reviewer` agent an explicit per-finding severity vocabulary. No new files, no new agents, no persistence layer, no new external dependencies. Research covered: the two target files, the existing skill conventions in this repo (looking at `sync/SKILL.md` and `github-tool-preference/SKILL.md`), every other consumer of the `code-reviewer` agent (Implement skill at 300–500 line checkpoints, and indirectly the Validate pipeline through `senior-reviewer`), and the live JSON shape returned by `gh pr view --json comments` against a real PR on `cli/cli`. A sample of that JSON is saved as an artifact so the Planner can reference field names exactly. The most significant correction to the spec surfaced by research: the comment identifier exposed by `gh` is the GraphQL node `id` (e.g. `IC_kwDODKw3uc8AAAABEMYhBw`), not `databaseId` — the spec's hedge "(or equivalent identifier)" applies. The most significant pre-existing constraint to remove: the current pr-review skill has a hard refusal at line 130 that forbids severity tags — this feature deletes/rewrites that refusal.

## Codebase Areas Affected

- `.claude/skills/pr-review/SKILL.md` — the only skill being edited. Every behavioral change (mode detection, dedup, stale surfacing, severity-label display) lands in this single file. The skill is one file with no `references/` subdirectory.
- `.claude/agents/code-reviewer.md` — gets the severity-label requirement added to its "How to respond" section and its standards. No restructuring; one new requirement folded into the existing finding-shape contract.
- `.docs/2026-06-02-pr-review-iterative/` — feature workflow folder. Research outputs land here. No runtime writes from the skill itself (spec is firm on no `.docs/` writes).

## Reusable Code

### Skill scaffolding

- **Existing `pr-review/SKILL.md` Fetch → Delegate → Triage → Post flow** — the entire structure stays. The follow-up logic slots in as an additive branch between "Fetch the PR" and "Delegate to code-reviewer" plus a dedup/stale step between "Delegate" and "Triage". The triage and post sections need only the small severity-label display tweak; their refusal rules and `gh pr comment` posting logic carry over byte-for-byte.
- **`Skill(github-tool-preference)` invocation pattern** — already used in the pr-review skill twice (top-of-file global note at line 13, and again before each `gh pr comment` post at line 111). The new mode-detection step adds `gh api user --jq .login` and `gh pr view --json comments`, both new `gh` calls that should be preceded by an explicit "invoke `Skill(github-tool-preference)`" reminder per the repo's convention. Sync's skill follows the same cadence: re-affirm before each new `gh`/`git` family of calls (sync/SKILL.md lines 95 and 103).

### `gh` commands

- `gh api user --jq .login` — confirmed working in this checkout; returned `itsacoyote`. Single source of truth for "me" as the spec requires.
- `gh pr view <N> --json comments` — already in scope per the JSON-fields docs. Returns top-level PR/issue comments only; review comments (anchored to diff lines) live under `reviews` or `latestReviews`, not under `comments`. The spec's assumption that `comments` means top-level-only is confirmed.
- `gh pr view <N> --json files` — already called by the existing skill (line 29) to get the changed-files list. Reusable as-is for stale detection: each entry has `path`, `additions`, `deletions`, `changeType`.
- `gh pr diff <N>` — already called by the existing skill (line 30). Standard unified diff format; hunks open with `@@ -<old-start>,<old-count> +<new-start>,<new-count> @@` so the line ranges present in the new diff are parseable by reading those headers. Reusable as-is for stale detection's line-range check.
- `gh pr comment <N> --body-file -` — existing post path. Unchanged.

### Comment fields exposed by `--json comments`

Confirmed against a real PR (`cli/cli#13547`). Each comment object exposes:

```
id                  (string — GraphQL node id, e.g. "IC_kwDODKw3uc8AAAABEMYhBw")
author.login        (string)
authorAssociation   (string — e.g. "NONE", "OWNER", "MEMBER")
body                (string — the comment markdown)
createdAt           (ISO 8601 timestamp string)
includesCreatedEdit (bool)
isMinimized         (bool)
minimizedReason     (string — e.g. "spam" when isMinimized true)
reactionGroups      (array)
url                 (string — direct link to the comment)
viewerDidAuthor     (bool — true if the authenticated viewer authored this comment)
```

See `artifacts/gh-pr-view-comments-sample.json` for the full live sample.

## Gaps: What Needs to Be Created

- **Mode-detection step** in `pr-review/SKILL.md` — a new section between "Fetch the PR" and "Delegate to code-reviewer". Runs `gh api user --jq .login`, then filters the `comments` array from the existing `gh pr view` call. Announces detected mode, accepts `fresh` / `follow-up` overrides.
- **Dedup step** in `pr-review/SKILL.md` — a new section that runs after the agent returns findings and before triage. Defines normalization (lowercase, collapse whitespace, strip `**<path>:<line>** — ` location prefix) and the verbatim/near-verbatim match rule. Prints `Filtered N near-duplicates of prior comments.`
- **Stale-thread surfacing** in `pr-review/SKILL.md` — runs in follow-up mode before triage. Parses each prior comment's location prefix and checks the changed-files list and current diff hunks. Prints a labeled section. Read-only.
- **Severity-label display** in `pr-review/SKILL.md` — small format change to the numbered overview and the one-by-one prompt. Applies in both first-review and follow-up modes.
- **Severity-label emission** in `code-reviewer.md` — one new clause in the "How to respond" section that requires one label per finding from `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`, and one update to "Standards" that names the vocabulary as fixed.
- **Refusal rewrite** in `pr-review/SKILL.md` — line 130 currently says "Do not invent severity tags (CRITICAL/HIGH/MEDIUM/LOW). Pass the code-reviewer's findings through as-is." This refusal is now wrong on the "do not invent" half (severity tags exist legitimately) but right on the "pass through as-is" half. Needs rewording to forbid only **invention** of labels and **modification** of agent-emitted labels, while permitting display of agent-emitted labels.

## Patterns and Conventions to Follow

- **Single SKILL.md per skill folder.** This repo's pattern is one file per skill (see `skills/pr-review/SKILL.md`, `skills/sync/SKILL.md`, `skills/feature/SKILL.md`). Only the larger reference-heavy skills like `frontend-ui-engineering` carry a `references/` subdir. The pr-review feature stays a single file; the Planner should not propose splitting it.
- **YAML frontmatter shape.** Existing pr-review frontmatter: `name`, `description`, `argument-hint`, `disable-model-invocation: true`, `allowed-tools: Read Bash(gh *) Bash(git *) Agent`. The follow-up additions need no new tools — `gh` and `git` are already allowed.
- **Section headings as imperative phrases.** Existing skill uses `## Fetch the PR`, `## Delegate to code-reviewer`, `## Triage findings`, `## What this skill will not do`. New sections should mirror that style: `## Detect mode`, `## Dedup against prior comments`, `## Surface stale threads`.
- **`Skill(github-tool-preference)` cadence.** Top-of-file global note + re-invoke before each new family of `gh` calls. The new mode-detection step adds two new families (`gh api user` and the existing `gh pr view --json comments`); a single reminder at the head of the new "Detect mode" section is consistent with the existing pattern.
- **Tables for accepted user inputs.** Both `pr-review/SKILL.md` (triage table at line 70) and `sync/SKILL.md` (dirty-tree table at line 71, ecosystem-install table at line 188) use `| Input | Effect |` two-column tables. The new mode-confirmation prompt should use the same shape.
- **Em-dash separator U+2014.** Used in `**<path>:<line>** — <text>` posting format and throughout the skill prose. The new finding-display lines (`<n>. [<LABEL>] <location> — <summary>`) keep the em-dash. The Planner should not let an editor silently substitute a hyphen-minus.
- **Refusal block prose conventions.** "Do not …" imperatives, no hedging, no enforcement layer disclaimer at the top ("the wording matters because there is no enforcement layer below this prose"). New refusals follow that voice.
- **Error-handling pattern.** On any `gh` non-zero exit: print the exact stderr verbatim and stop. No silent fallback, no retry. The mode-detection error paths in the spec (failed `gh api user`, failed `gh pr view`) follow this convention exactly.
- **No AI attribution anywhere.** CLAUDE.md and `git-commit` skill prohibit `Co-Authored-By`. The pr-review skill restates the same rule for posted PR comment bodies. This carries through unchanged.
- **`code-reviewer` agent finding shape.** Location / Problem / Fix prose. Severity-label addition slots in as a new prefix line on each finding — not a wrapping structure — to preserve readability for the other consumers of the agent (the Implement skill's mid-task review checkpoints).

## Architectural Context

- **`code-reviewer` is shared across two pipelines.** It is invoked by (a) `pr-review/SKILL.md` directly (this feature), and (b) `skills/implement/SKILL.md` every 300–500 lines during the Implement step. The severity-label addition is additive metadata: it does not change the Location/Problem/Fix prose the Implement skill consumes. The Implement skill reads the agent's output as prose and gates progress on the literal string `"Approved — continue implementation."` (code-reviewer.md line 78). Both contracts hold after the change.
- **The pr-review skill is not in the `/feature` pipeline.** It is a developer-invoked utility (sync/SKILL.md line 340 has the matching note for sync). No `context.yaml` interaction, no workflow state. The skill runs entirely on per-session in-memory state.
- **State source of truth is GitHub.** The spec is firm: no `.docs/` write, no cache file, no local sidecar. "What was reviewed before" is re-derived each session by re-querying GitHub for the authenticated user's comments. This keeps the skill stateless across machines and sessions and also means a comment posted manually (not through the skill) is indistinguishable from one posted via the skill — both count as prior reviewer activity. Spec confirms this is intentional.
- **Dedup is text-on-text, not anchor-on-anchor.** The match is "does this new finding's body, normalized, equal a prior comment's body, normalized?" This means two findings at the same `path:line` survive if their text differs. The Planner should not be tempted to add a location-equality early-out as an "optimization" — that breaks the conservative-by-design rule in the spec.
- **Stale detection is location-prefix-based, parse-once.** The location prefix `**<path>:<line>** — ` is well-defined because the existing skill emits exactly that format on every post (pr-review/SKILL.md line 87–96). The Planner can rely on a simple regex like `^\*\*([^*:]+):([0-9]+)\*\* —` (or the function-form variant `^\*\*([^*]+)\*\* \(\`([^`]+)\`\) —`) to extract path + line. Comments without a parseable prefix simply don't get stale-checked — the spec is explicit on that fallback.
- **Override semantics are strict.** The spec restricts override replies to exactly `fresh` / `follow-up`; "anything else" proceeds with the detected mode. Mirrors the triage table's "anything else" pattern.
- **First-review path is byte-identical to today.** When the detected mode is first-review and the user doesn't override, the new code path collapses back into the existing flow with only one new line printed at the top (the mode announcement). The Planner must verify nothing in the dedup or stale-surfacing code runs in first-review mode.

## Key Insights for the Planner

- **The comment identifier is the GraphQL `id` field, not `databaseId`.** The spec says "`databaseId` (or equivalent identifier)" — the equivalent that `gh pr view --json comments` actually returns is `id` (e.g. `IC_kwDODKw3uc8AAAABEMYhBw`). If you need an identifier for any in-memory map keyed per prior comment, use `id`. If you need a stable URL for surfacing stale threads, use `url`. There is no `databaseId` to chase.
- **`viewerDidAuthor` is a usable shortcut for the filter.** Each comment object includes `viewerDidAuthor: true|false`. That's true iff the authenticated viewer authored the comment. You could filter on this and skip resolving the login entirely. The spec mandates the explicit `gh api user --jq .login` resolve plus an `author.login == <login>` filter, so the Planner should stay with the spec's path — but the existence of `viewerDidAuthor` is a useful fact: it lets the Planner add a sanity-check assertion (`viewerDidAuthor` should agree with the login comparison) without writing extra GitHub-API code.
- **Top-level vs review comments.** `--json comments` returns ONLY top-level PR/issue comments (the kind `gh pr comment` posts). Inline review comments anchored to diff lines live under `--json reviews` (which exposes a separate `reviews[].comments` array) or `latestReviews`. The spec's assumption is correct: the dedup pool is top-level-only, matching what the skill actually posts.
- **Hard-refusal at line 130 of pr-review/SKILL.md must be rewritten, not deleted.** The current text "Do not invent severity tags (CRITICAL/HIGH/MEDIUM/LOW). Pass the code-reviewer's findings through as-is." has two halves. The "do not invent" half is now wrong: the agent emits them legitimately. The "pass through as-is" half is still right: the skill must surface labels verbatim, never re-rank or normalize them. The Planner's edit must keep the second half's spirit and replace the first half with the new rule (the skill displays labels but does not invent, re-rank, normalize, or strip them).
- **Severity label is on a prefix line, not part of the body.** Posted PR comment bodies retain the existing `**<path>:<line>** — <text>` format — no `[LABEL]` token in the body. The label appears only in the skill's overview line (`<n>. [<LABEL>] <location> — <summary>`) and on a line above Location/Problem/Fix in the one-by-one prompt. This separation matters because the posted comment is what subsequent follow-up sessions compare against in dedup — if labels leaked into the posted body, the normalization step would have to strip them, and the dedup logic would get more brittle.
- **Skill must not require severity labels.** A finding that arrives without a label is displayed without one and proceeds through triage normally. The spec is explicit (acceptance criterion at line 150). The Planner must handle the missing-label case in both display branches (overview line and one-by-one prompt) without crashing or fabricating a label.
- **Override path complicates the announcement-then-confirm flow.** The mode announcement is "the first line after PR fetch". The override happens "at the next prompt". This implies the flow is: print announcement → reach the next user-input point → on `fresh` or `follow-up`, switch mode there. The Planner needs to be specific about which prompt is "the next prompt" — most naturally, it's the one immediately following the mode line, before any further `gh` work happens (so an override to `fresh` doesn't waste the prior-comment fetch on a session that's going to discard it). Worth confirming in the plan that the prior-comment fetch happens once after override is resolved, not before.
- **The dedup and stale steps must not run in first-review mode.** Even after the user overrides from `follow-up` to `fresh`, the prior-comments list is empty (or treated as empty). The plan should branch on the final resolved mode, not on the detected mode.
- **`code-reviewer` is invoked unchanged in both modes.** The agent is not told whether this is a first or follow-up review. It does not see the prior comments. It always reviews the latest diff fresh. The dedup happens in the skill, downstream. This is important so the Implement skill's mid-pipeline use of the agent (which has no concept of prior PR comments) continues to work without modification.
- **The "no new findings" terminal message bypasses triage entirely.** Spec acceptance criterion at line 141 requires that if dedup filters every finding, the skill prints the specific terminal message and **stops without entering triage or the post prompt**. The Planner must wire this exit so the post-confirmation prompt never fires in that case — otherwise the skill could ask "Post 0 comments now?" which is meaningless.
- **Frontmatter `allowed-tools` already covers the new calls.** `Read Bash(gh *) Bash(git *) Agent` — both `gh api user` and `gh pr view --json comments` fall under `Bash(gh *)`. No frontmatter edit is required.

## Artifacts

- [`artifacts/gh-pr-view-comments-sample.json`](artifacts/gh-pr-view-comments-sample.json) — pretty-printed live sample of `gh pr view 13547 -R cli/cli --json comments` showing the exact field names and types of a real comments array. Captured to give the Planner a concrete reference for the JSON shape the dedup / mode-detection / stale-detection logic consumes. Three comments, including one minimized-as-spam example so the Planner can see the `isMinimized` / `minimizedReason` fields populated.

## Open Questions

None blocking. All discovery-phase open questions were resolved in the spec. Research surfaced one ambiguity worth a one-line plan note (not a blocker):

- **The spec says "`databaseId` (or equivalent identifier exposed by `gh`)" but `gh pr view --json comments` does not expose `databaseId` — only the GraphQL `id` and the comment `url`.** The Planner should pick one (`id` is the natural choice for in-memory keying) and write it down in `3_plan.md` so the implementer doesn't have to make that call mid-task.
