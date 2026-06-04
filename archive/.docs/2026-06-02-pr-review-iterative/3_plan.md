# Plan: Iterative PR Review Skill

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-06-02

## Decomposition decisions

This plan touches only Markdown contract files (a skill prose contract and an agent prose contract). There is no executable code, no test harness, and no build system in scope. Where the standard TDD template would call for `describe`/`it` tests, this plan substitutes **acceptance walk-throughs** — concrete, ordered prompts and expected verbatim responses derived from the spec's Acceptance Criteria. These walk-throughs are the verification artifact for each task and are written before the edit, matching the spirit of TDD: define the observable behavior first, then make the document produce it.

A few cross-cutting decisions, locked here so the implementer does not re-litigate them mid-task:

- **Identifier choice for prior comments.** Per research §Key Insights and §Open Questions, `gh pr view --json comments` does not expose `databaseId`. The skill uses `id` (GraphQL node id, e.g. `IC_kwDODKw3uc8AAAABEMYhBw`) for any in-memory keying of prior comments, and `url` for surfacing stale threads to the reviewer. The spec's `databaseId` hedge ("or equivalent identifier") resolves to `id`.
- **Author filter path.** The skill resolves the authenticated login with `gh api user --jq .login` once per session and filters `comments[].author.login == <login>`, exactly as the spec mandates. `viewerDidAuthor` is **not** used as the filter — but the implementer may add a one-line sanity-check sentence noting it should agree with the login comparison. It is not a substitute.
- **Single file per skill.** Research §Patterns confirms the repo convention is one `SKILL.md` per skill folder. The pr-review skill stays a single file. Do not split it into a `references/` directory.
- **No frontmatter change.** Research §Key Insights confirms `allowed-tools: Read Bash(gh *) Bash(git *) Agent` already covers `gh api user` and `gh pr view --json comments`. Do not edit frontmatter.
- **Em-dash discipline.** Every new finding-display line, every refusal sentence, and every prefix uses U+2014 (`—`), never a hyphen-minus. Section headings stay in imperative form to match existing convention (`## Detect mode`, `## Dedup against prior comments`, `## Surface stale threads`).
- **First-review path is byte-identical to today plus one announcement line.** The dedup and stale steps must branch on the **final resolved mode** (after any `fresh`/`follow-up` override), not on the detected mode. The Detect mode section enforces this explicitly so the implementer cannot accidentally wire follow-up logic to fire in a session the user overrode to `fresh`.

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

### New Files

None. This feature adds no new files. Per spec Constraints and research §Codebase Areas Affected, all changes are in-place edits to two existing files.

### Modified Files

| File | What Changes | Why |
|------|--------------|-----|
| `.claude/agents/code-reviewer.md` | Add one clause to "How to respond → If there are issues" requiring exactly one severity label per finding from the fixed vocabulary `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`. Add a matching bullet to "Standards" naming the vocabulary as fixed and stating no other values (including `nit`) are valid. | Spec Requirements §`code-reviewer` agent update; Acceptance Criterion line 146. Producer-side of the severity-label contract that the skill consumes. |
| `.claude/skills/pr-review/SKILL.md` | (1) Rewrite the refusal at current line 130 to permit display of agent-emitted labels while forbidding invention, re-ranking, normalization, and stripping. (2) Update the Triage Overview numbered-list format and the one-by-one finding prompt to display the agent's severity label, with a graceful missing-label fallback. (3) Insert a new `## Detect mode` section between `## Fetch the PR` and `## Delegate to code-reviewer` that resolves the authenticated login, filters prior comments, announces the detected mode, and accepts `fresh` / `follow-up` overrides. (4) Insert `## Dedup against prior comments` and `## Surface stale threads` sections between `## Delegate to code-reviewer` and `## Triage findings`, gated on the **final resolved mode** being follow-up. (5) Wire the "no new findings" terminal exit so triage and the post prompt are bypassed when dedup filters every finding. | Spec Requirements §Mode auto-detection, §Triage display, §Follow-up mode (fetching, delegating, deduplication, stale detection, triage, posting); Acceptance Criteria lines 131–150; Research §Gaps. |

### Deleted Files

None. The refusal at line 130 is **rewritten in place**, not deleted — research §Gaps and the spec's preservation-of-existing-behavior constraint require keeping the "pass through as-is" half of the original refusal.

---

## Implementation Tasks

Tasks are ordered by dependency. The producer of the severity-label contract (`code-reviewer.md`) is updated before the consumer (`pr-review/SKILL.md`). Inside the skill file, the refusal-rewrite lands first because it removes a contradiction that blocks every subsequent edit; the severity-label display lands next because it is mode-independent; the mode-detection branch lands next because dedup and stale-surfacing depend on a resolved mode existing; dedup and stale-surfacing land in that order; the terminal-exit integration lands last and verifies the whole follow-up path end-to-end.

Each task ends with a single commit using Conventional Commits format and the `git-commit` skill conventions (no `Co-Authored-By`, no AI attribution).

---

### Task 1: Add severity-label requirement to `code-reviewer` agent

**Files:** `.claude/agents/code-reviewer.md`

**Acceptance walk-through (write before editing):**

```
describe('code-reviewer.md severity-label clause', () => {
  it('requires exactly one label per finding from CRITICAL | HIGH | MEDIUM | LOW | INFO when listing issues')
  it('forbids any label outside the fixed vocabulary, including "nit"')
  it('places the label requirement inside "How to respond → If there are issues", not under "Approved" output')
  it('adds a matching bullet under "Standards" naming the vocabulary as fixed')
  it('leaves the Location / Problem / Fix shape, the "Approved — continue implementation." gate string, and all other agent contracts unchanged')
})
```

Verification: re-read the edited file end-to-end. Confirm (a) the issue-listing section now requires a label, (b) the standards section names the vocabulary, (c) the literal string `Approved — continue implementation.` is untouched (Implement-skill gate at line 78 still works), (d) the agent frontmatter is unchanged.

**Implementation:**

1. Open `.claude/agents/code-reviewer.md`.
2. In the section `## How to respond` → `**If there are issues:**`, add a new bullet immediately above the existing `- **Location:**` bullet. The new bullet reads:
   - `**Severity:** one of `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO` — the agent's rating of the issue. Exactly one label per finding. No other values are valid; there is no `nit` label (use `LOW` or `INFO` instead).`
3. In the section `## Standards`, append a new bullet at the end of the list:
   - `Use the fixed severity vocabulary `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO` for every finding. Do not coin new labels, alias them, or omit the label.`
4. Leave the `Approved — continue implementation.` line, the frontmatter, and every other section unchanged.
5. Re-read the file and confirm each item in the acceptance walk-through above.

**Commit:** `feat(code-reviewer): require severity label per finding from fixed vocabulary`

---

### Task 2: Rewrite the pr-review skill's "do not invent severity tags" refusal

**Files:** `.claude/skills/pr-review/SKILL.md`

**Acceptance walk-through (write before editing):**

```
describe('pr-review refusal rewrite (current line 130)', () => {
  it('no longer forbids displaying severity labels emitted by code-reviewer')
  it('still forbids the skill from inventing labels')
  it('still forbids the skill from re-ranking, normalizing, translating, or stripping labels')
  it('explicitly permits surfacing labels verbatim in the Triage overview and one-by-one prompts')
  it('explicitly forbids appending labels to the body of posted PR comments')
  it('matches the voice of the surrounding refusal block — "Do not …", no hedging, no enforcement-layer disclaimer')
})
```

Verification: re-read the `## What this skill will not do` block. Confirm the bullet at current line 130 has been replaced with the new wording, that the surrounding refusal bullets are untouched, and that nothing in the rest of the skill contradicts the new bullet.

**Implementation:**

1. Open `.claude/skills/pr-review/SKILL.md`.
2. Locate the bullet at line 130:
   - `Do not invent severity tags (CRITICAL/HIGH/MEDIUM/LOW). Pass the code-reviewer's findings through as-is.`
3. Replace it in place with two bullets (keeping the bullet's slot in the existing list):
   - `Do not invent, re-rank, normalize, translate, or strip severity labels. The `code-reviewer` agent emits one label per finding from the fixed vocabulary `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`; surface those labels verbatim in the Triage overview and the one-by-one prompt, and otherwise pass the agent's findings through as-is.`
   - `Do not append severity labels to the body of posted PR comments. Posted bodies keep the existing `**<path>:<line>** — <text>` format with no `[LABEL]` prefix.`
4. Do not touch any other refusal bullet in the block.
5. Re-read the block and confirm each item in the acceptance walk-through above.

**Commit:** `refactor(pr-review): rewrite severity-label refusal to permit verbatim display`

---

### Task 3: Display severity labels in Triage overview and one-by-one prompt

**Files:** `.claude/skills/pr-review/SKILL.md`

**Acceptance walk-through (write before editing):**

```
describe('Triage severity-label display', () => {
  it('renders the numbered overview as `<n>. [<LABEL>] <location> — <one-line summary>` when the agent emitted a label')
  it('renders the numbered overview as `<n>. <location> — <one-line summary>` (no [LABEL] token) when the agent did not emit a label')
  it('shows the severity label on a dedicated line above Location / Problem / Fix in one-by-one mode when present')
  it('omits the dedicated severity line entirely in one-by-one mode when no label was emitted')
  it('applies to both first-review mode and follow-up mode')
  it('does not append the label to posted comment bodies — `gh pr comment` body remains `**<path>:<line>** — <text>`')
  it('uses em-dash U+2014 in the new overview format, not a hyphen-minus')
})
```

Verification: re-read the `## Triage findings → ### Overview` and `### One-by-one mode` subsections. Confirm both new formats are present, the missing-label fallback is named explicitly, and `### Comment formatting` and `### Post step` are unchanged.

**Implementation:**

1. In `## Triage findings → ### Overview`, replace the existing example block:
   - From: ` 1. src/foo.ts:42 — useAuthToken does not handle expired tokens.` and ` 2. src/bar.ts:17 — Missing null check on response.data.`
   - To a labeled-and-unlabeled example pair, e.g.:
     ```
     1. [HIGH] src/foo.ts:42 — useAuthToken does not handle expired tokens.
     2. [LOW] src/bar.ts:17 — Missing null check on response.data.
     3. src/baz.ts:91 — Helper duplicates logic in `formatBytes`.
     ```
2. Immediately below the example, add a one-sentence rule: `If the agent emitted a severity label for the finding, show it in square brackets between the number and the location, using the em-dash separator U+2014. If the agent did not emit a label, omit the `[LABEL]` token entirely — never invent a placeholder.`
3. In `## Triage findings → ### One-by-one mode`, just below the existing sentence "For each finding, print the finding number, location, problem, and fix in full.", add a rule sentence: `If the agent emitted a severity label, print `Severity: <LABEL>` on its own line immediately above the Location / Problem / Fix block. If no label was emitted, omit the Severity line; do not print `Severity: (none)` or any placeholder.`
4. Do not change the `### Comment formatting` subsection. Confirm posted-body format `**<path>:<line>** — <text>` is unchanged.
5. Do not change the `### Post step` subsection.
6. Re-read both subsections and confirm each item in the acceptance walk-through above.

**Commit:** `feat(pr-review): show code-reviewer severity labels in triage overview and one-by-one prompt`

---

### Task 4: Insert `## Detect mode` section between Fetch and Delegate

**Files:** `.claude/skills/pr-review/SKILL.md`

**Acceptance walk-through (write before editing):**

```
describe('Detect mode section', () => {
  it('runs immediately after `## Fetch the PR` and before `## Delegate to code-reviewer`')
  it('opens with a `Skill(github-tool-preference)` reminder before the first new `gh` call')
  it('resolves the authenticated login via `gh api user --jq .login` exactly once per session')
  it('stops with `gh` stderr on non-zero exit from `gh api user` — no silent fallback to first-review mode')
  it('filters the `comments` array already fetched by step 2 of Fetch (or re-fetches via `gh pr view <N> --json comments` if not yet carried forward) by `author.login == <authenticated login>`')
  it('stops with `gh` stderr on non-zero exit from `gh pr view --json comments` — no silent fallback to first-review mode')
  it('announces detected mode as the first line after PR fetch: `Detected follow-up review — you have N prior comments on PR #<N>.` or `Detected first review — no prior comments by you on PR #<N>.`')
  it('accepts `fresh` / `follow-up` overrides at the very next prompt')
  it('treats any other reply as confirmation of the detected mode (does not interpret as override)')
  it('resolves to a single value: `final mode ∈ {first-review, follow-up}`, which downstream sections branch on')
  it('records that the prior-comments list (id, body, createdAt, url) is carried forward only when the final mode is follow-up')
  it('notes that comment identifier is the GraphQL `id` (e.g. IC_kwDODKw3uc8AAAABEMYhBw), not `databaseId`')
  it('notes that `viewerDidAuthor` should agree with the login comparison and acts only as a sanity check, not as the filter')
})
```

Verification: re-read the new section end-to-end. Confirm the order is announce → override → resolve → (in follow-up only) carry-forward, that both error paths print stderr and stop, and that nothing in the section runs in first-review mode beyond the announcement line.

**Implementation:**

1. Insert a new top-level section `## Detect mode` immediately after the existing `## Fetch the PR` section and immediately before the existing `## Delegate to code-reviewer` section.
2. Open the section with one sentence: `Before delegating to the agent, decide whether this is a first-review session or a follow-up session by checking GitHub for prior comments authored by you. Invoke `Skill(github-tool-preference)` before the `gh api user` and `gh pr view --json comments` calls below.`
3. Add numbered steps:
   1. `Resolve the authenticated user once per session: run `gh api user --jq .login`. If it exits non-zero, print the exact `gh` stderr and stop. Do not invoke the agent. Do not fall back silently to first-review mode.`
   2. `Re-use the `comments` data when available, or run `gh pr view $ARGUMENTS --json comments` if you do not already have it in this session. If the call exits non-zero, print the exact `gh` stderr and stop.`
   3. `Filter the `comments` array to entries where `author.login == <authenticated login>`. The identifier on each entry is the GraphQL node `id` (e.g. `IC_kwDODKw3uc8AAAABEMYhBw`); use it for any in-memory keying. Each entry also includes `body`, `createdAt`, and `url`. (Sanity check: `viewerDidAuthor` should agree with the login comparison; if it disagrees, trust the explicit login comparison and continue.)`
   4. `If the filtered list is non-empty, the **detected mode** is follow-up. Announce: `Detected follow-up review — you have N prior comments on PR #<N>.` where N is the filtered count.`
   5. `If the filtered list is empty, the **detected mode** is first-review. Announce: `Detected first review — no prior comments by you on PR #<N>.``
   6. `Prompt the reviewer once: `Reply `fresh` to force first-review mode, `follow-up` to force follow-up mode, or anything else to continue with the detected mode.``
4. Add a sub-section `### Resolving the final mode` with a two-column input table mirroring the triage table style:

   ```
   | Reply | Effect |
   |-------|--------|
   | `fresh` | Final mode is first-review. Discard the prior-comments list. |
   | `follow-up` | Final mode is follow-up. Keep the prior-comments list in memory. |
   | anything else | Final mode equals the detected mode. |
   ```
5. Add a closing sentence: `Carry the prior-comments list (id, body, createdAt, url) forward to the dedup and stale-detection steps only when the final mode is follow-up. In first-review mode, the list is discarded and no follow-up logic runs.`
6. Re-read the new section and confirm each item in the acceptance walk-through above.

**Commit:** `feat(pr-review): add mode detection with fresh/follow-up override`

---

### Task 5: Insert `## Dedup against prior comments` section

**Files:** `.claude/skills/pr-review/SKILL.md`

**Acceptance walk-through (write before editing):**

```
describe('Dedup against prior comments section', () => {
  it('runs only when the final resolved mode is follow-up (not the detected mode)')
  it('runs after `## Delegate to code-reviewer` returns findings and before `## Triage findings`')
  it('defines normalization explicitly: lowercase, collapse whitespace, strip the `**<path>:<line>** — ` location prefix')
  it('matches new findings against prior-comment bodies on text only — same `path:line` with different text is NOT a duplicate')
  it('filters near-duplicates silently from the triage list (not surfaced as kept items)')
  it('prints `Filtered N near-duplicates of prior comments.` exactly, where N includes zero')
  it('does not run in first-review mode at all (gated on final resolved mode)')
  it('emits the terminal `No new findings — all of code-reviewer\'s output matched comments you already posted. Stale thread review above is still relevant.` and stops without triage or post when every finding is filtered')
})
```

Verification: re-read the new section. Confirm the gating sentence names the **final resolved mode**, the normalization rule is explicit, the "two distinct issues at the same line both survive" rule is named, and the terminal-message exit is wired and bypasses both triage and the post prompt.

**Implementation:**

1. Insert a new top-level section `## Dedup against prior comments` immediately after `## Delegate to code-reviewer` and immediately before `## Surface stale threads` (added in Task 6).
2. Open with a gating sentence: `This section runs only when the final resolved mode is follow-up. In first-review mode, skip this section entirely and pass the agent's findings unchanged to `## Triage findings`.`
3. Add a subsection `### Normalization`:
   - `Before comparison, normalize both the new finding body and each prior comment body by: (a) lowercasing, (b) collapsing all runs of whitespace (including newlines) to a single space, (c) stripping the standard location prefix `**<path>:<line>** — ` (or its function-form variant `**<path>** (\`<function>\`) — `) from the start. Strip leading and trailing whitespace after step (c).`
4. Add a subsection `### Match rule`:
   - `A new finding is a near-duplicate if its normalized body equals a prior comment's normalized body verbatim or near-verbatim. The match is on issue text only; two findings at the same `path:line` whose normalized bodies differ are both kept. Be conservative: when in doubt, keep the finding.`
5. Add a subsection `### Output`:
   - `Drop near-duplicates silently from the triage list — they are not surfaced as kept items, not shown to the reviewer, not posted. Print exactly one summary line: `Filtered N near-duplicates of prior comments.` where N is the count actually filtered (use `0` when nothing was filtered).`
6. Add a subsection `### Terminal exit when everything was a duplicate`:
   - `If every finding was filtered (and the surviving-findings list is empty), print exactly: `No new findings — all of code-reviewer's output matched comments you already posted. Stale thread review above is still relevant.` Then stop. Do not enter `## Triage findings`. Do not enter the Post step. Do not ask `Post 0 comments now?`.`
7. Re-read the section and confirm each item in the acceptance walk-through above.

**Commit:** `feat(pr-review): dedup new findings against authenticated user's prior PR comments`

---

### Task 6: Insert `## Surface stale threads` section

**Files:** `.claude/skills/pr-review/SKILL.md`

**Acceptance walk-through (write before editing):**

```
describe('Surface stale threads section', () => {
  it('runs only when the final resolved mode is follow-up')
  it('runs after `## Dedup against prior comments` and before `## Triage findings`')
  it('parses each prior comment\'s location prefix with a regex matching the line form `^\\*\\*([^*:]+):([0-9]+)\\*\\* —` and the function form `^\\*\\*([^*]+)\\*\\* \\(`([^`]+)`\\) —`')
  it('marks a comment stale when the parsed file path is not in the current PR changed-files list, or the parsed line is not in any current diff hunk for that file')
  it('does NOT mark a comment stale when its body has no parseable location prefix')
  it('surfaces stale prior comments in a dedicated section printed before triage begins, headed `Prior comments where the code is gone (consider resolving on GitHub):`')
  it('lists each stale comment as a numbered entry with the comment URL, the original location prefix, and the first line of the body')
  it('is read-only: makes no `gh` write calls, does not resolve threads, does not edit anything on GitHub')
  it('still prints the heading (with an empty list or a single `(none)` line) only when there are stale comments — emit nothing if the list is empty')
  it('runs after dedup so the stale section is the last thing the reviewer sees before triage begins')
})
```

Verification: re-read the new section. Confirm the gating sentence names the **final resolved mode**, the regex shapes match the existing posted-body format byte-for-byte, the no-prefix fallback is named explicitly, and the section is read-only (no `gh` write commands).

**Implementation:**

1. Insert a new top-level section `## Surface stale threads` immediately after `## Dedup against prior comments` and immediately before `## Triage findings`.
2. Open with a gating sentence: `This section runs only when the final resolved mode is follow-up. It is read-only — the skill does not edit, reply to, or resolve GitHub threads here.`
3. Add a subsection `### Parsing the location prefix`:
   - Show both regex forms and what they extract:
     - Line form: `^\*\*([^*:]+):([0-9]+)\*\* —` → captures `path` and `line`.
     - Function form: `^\*\*([^*]+)\*\* \(`([^`]+)`\) —` → captures `path` and `function`.
   - State: `If the prior comment body matches neither pattern, the comment has no parseable anchor. Do not mark it stale; do not surface it in this section.`
4. Add a subsection `### Staleness rule`:
   - `For each prior comment with a parseable location prefix:`
     - `Line form: mark stale if `path` is not in the changed-files list from `gh pr view --json files`, OR if `line` is not within any `@@ -<old-start>,<old-count> +<new-start>,<new-count> @@` hunk range for that file in the current `gh pr diff` output.`
     - `Function form: mark stale if `path` is not in the changed-files list. Function-name presence in the new diff is not required — the function form intentionally has the weaker check, because verifying function existence requires parsing the diff body rather than the hunk headers.`
5. Add a subsection `### Output`:
   - `If the stale list is empty, emit nothing — do not print an empty heading.`
   - `If the stale list is non-empty, print the heading: `Prior comments where the code is gone (consider resolving on GitHub):` and then a numbered list. Each entry: ``<n>. <url> — <original location prefix> — <first line of body>``.`
   - `This section is the last thing printed before `## Triage findings` begins.`
6. Re-read the section and confirm each item in the acceptance walk-through above.

**Commit:** `feat(pr-review): surface stale prior comments whose anchor code is gone`

---

### Task 7: Integration pass — gate, ordering, and end-to-end consistency

**Files:** `.claude/skills/pr-review/SKILL.md`

**Acceptance walk-through (write before editing):**

```
describe('end-to-end consistency of the rewritten skill', () => {
  it('first-review path: announces mode, skips Detect mode\'s prior-fetch when override is `fresh`, skips Dedup, skips Stale, enters Triage, posts via `gh pr comment` — identical to today aside from the announcement line and the severity-label display')
  it('follow-up path: announces mode, fetches prior comments, runs Dedup (prints `Filtered N`), runs Stale (prints heading only if non-empty), enters Triage, posts')
  it('follow-up path with everything-was-a-duplicate: announces mode, prints `Filtered N`, prints stale section if non-empty, prints terminal `No new findings — …` message, stops — does not enter Triage, does not ask `Post N comments?`')
  it('every new `gh` call is preceded by a `Skill(github-tool-preference)` reminder consistent with the existing skill\'s cadence')
  it('frontmatter is unchanged — `allowed-tools: Read Bash(gh *) Bash(git *) Agent` is still correct')
  it('all hard refusals from the existing `## What this skill will not do` block carry over: no approve, no request-changes, no merge, no inline anchored comments, no AI attribution, no `.docs/` writes')
  it('the rewritten severity-label refusal from Task 2 is present and the original "do not invent severity tags" bullet is gone')
  it('no section runs follow-up logic when the final resolved mode is first-review, even if the detected mode was follow-up')
  it('every em-dash in new content is U+2014, not hyphen-minus')
})
```

Verification: re-read the whole file end-to-end as a single document and trace both modes against the spec's Acceptance Criteria (lines 131–150). Confirm the Detect → (Dedup → Stale)? → Triage → Post order is unambiguous and that follow-up logic is gated on the final resolved mode at every entry point.

**Implementation:**

1. Re-read the entire `.claude/skills/pr-review/SKILL.md` end-to-end.
2. Confirm section order top-to-bottom:
   - `# PR Review` → `## What this does` → `### Input validation` → `## Fetch the PR` → `## Detect mode` → `## Delegate to code-reviewer` → `## Dedup against prior comments` → `## Surface stale threads` → `## Triage findings` (with its existing subsections) → `## What this skill will not do` → `### Refusal`.
3. Confirm the gating sentence at the top of both `## Dedup against prior comments` and `## Surface stale threads` reads: `This section runs only when the final resolved mode is follow-up.` (or wording equivalent) — and that no other branch in the skill performs follow-up work without that gate.
4. Confirm the terminal exit message from Task 5 is wired so it bypasses both `## Triage findings` and the `### Post step`. Add a one-sentence cross-reference in `## Triage findings` if needed: `If the Dedup step printed the "No new findings —" terminal message, this section is not entered.`
5. Confirm every new `gh` call (`gh api user --jq .login`, `gh pr view --json comments` if newly placed) is preceded by `Skill(github-tool-preference)` per repo convention.
6. Confirm the frontmatter block is unchanged.
7. Confirm every em-dash in new content is U+2014. Spot-check by searching the file for hyphen-minus in any new prose; convert any stragglers.
8. Re-read the file end-to-end one more time and confirm each item in the acceptance walk-through above.

**Commit:** `chore(pr-review): finalize iterative review flow ordering and gates`

---

## Out of Scope

These items were considered and explicitly excluded — they are not part of this plan and should not be added during implementation.

- **New skill or new agent.** The spec mandates editing the two existing files in place. No `pr-review-iterative/`, no `pr-followup` agent.
- **Persistence of prior reviews to disk.** Spec is firm: no `.docs/` writes, no cache, no sidecar. State is re-derived from GitHub on every session.
- **Cross-session learning of drop decisions.** Out of scope per spec Non-Goals.
- **Inline / line-anchored comments.** Out of scope per spec Non-Goals; all posts remain top-level via `gh pr comment`.
- **Approve / request-changes / merge / close / edit / resolve thread.** Out of scope per spec Non-Goals and per the existing skill's refusal block.
- **Differentiating skill-posted from manually-posted comments.** Out of scope per spec Non-Goals — any comment authored by the authenticated `gh` user counts as prior reviewer activity.
- **Telling `code-reviewer` about prior comments.** The agent is unchanged in its inputs — it reviews the latest diff fresh in both modes. Dedup happens in the skill, downstream. This preserves the Implement skill's mid-pipeline use of the agent.
- **Using `viewerDidAuthor` as the filter.** Spec mandates the explicit `gh api user --jq .login` resolve + `author.login == <login>` filter. `viewerDidAuthor` appears in the plan only as a sanity-check sentence.
- **Using `databaseId` as the prior-comment identifier.** `gh pr view --json comments` does not expose `databaseId`; the plan uses the GraphQL node `id` instead.
- **Splitting `pr-review/SKILL.md` into a `references/` subdir.** Repo convention is one `SKILL.md` per skill folder; the file stays single.
- **Editing the skill's YAML frontmatter.** `allowed-tools` already covers all new calls.
- **Adding severity labels to posted comment bodies.** Labels are display-only in the skill; the posted body keeps `**<path>:<line>** — <text>` with no `[LABEL]` prefix. This is enforced by the Task 2 refusal rewrite.
- **A `nit` severity label.** Vocabulary is fixed at `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`. What is colloquially called a "nit" is emitted as `LOW` or `INFO`.
- **Touching `senior-reviewer` or `skills/implement/SKILL.md`.** The severity-label addition is additive metadata; both consumers continue to work. Research confirms the Implement skill gates on the literal string `Approved — continue implementation.` which is not changed.
