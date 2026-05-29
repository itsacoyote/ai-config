# Plan: PR Review Skill

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-05-29

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

### New Files

| File | Responsibility | Public Interface |
|------|---------------|-----------------|
| `.claude/skills/pr-review/SKILL.md` | The entire skill — frontmatter that registers `/pr-review <pr-number>` as a slash command, plus the prose body that drives Fetch → Delegate → Triage → Post and hard-bounds the forbidden actions. | Registered as a slash command via its frontmatter (`name: pr-review`, `argument-hint: "[pr-number]"`). The body's `$ARGUMENTS` reference receives the PR number. No code exports — the file *is* the contract the model executes. |

### Modified Files

None.

### Deleted Files

None.

**Decomposition rationale.** Research is explicit: "the skill is a single `SKILL.md` file. No `template.md`, no `scripts/`, no `references/` directory." There is no production code to test, no template document to render under `.docs/`, no helper script to call. Splitting the SKILL.md into multiple files would violate YAGNI — every section the spec requires (Fetch, Delegate, Triage, Post, Non-Goals) is part of the same single prose contract the model reads top-to-bottom. The decomposition therefore happens *within* the file via H2 sections, not across files. Tasks below correspond to those sections so each commit lands one coherent slice of the skill's contract.

---

## Implementation Tasks

Tasks are ordered so the file is born valid (frontmatter + skeleton) and each subsequent commit adds one self-contained section. No task leaves the file in a syntactically broken state. There are no automated tests — verification is by reading the file and confirming against the spec's acceptance criteria. Each task names the manual checks that must pass before its commit.

---

### Task 1: Create `pr-review/` directory and SKILL.md with frontmatter + skeleton

**Files:** `.claude/skills/pr-review/SKILL.md` (new)

**Tests:**

No automated tests. Manual verification only:

```
manual-checks:
  - File `.claude/skills/pr-review/SKILL.md` exists.
  - Frontmatter parses as valid YAML between `---` fences at the top of the file.
  - Frontmatter contains exactly these keys: name, description, argument-hint, disable-model-invocation, allowed-tools.
  - name is `pr-review` (matches the folder name).
  - argument-hint is `"[pr-number]"`.
  - disable-model-invocation is `true`.
  - allowed-tools is the literal string `Read Bash(gh *) Bash(git *) Agent` (space-separated, in that order).
  - description is one sentence and references "GitHub pull request" so the model can route /pr-review correctly.
  - Body has an H1 `# PR Review` immediately after the closing `---` of frontmatter.
  - Skeleton contains H2 placeholders for all five required sections (in order): "What this does", "Fetch the PR", "Delegate to code-reviewer", "Triage findings", "What this skill will not do". Empty body under each H2 is acceptable for this task; later tasks fill them in.
```

**Implementation:**

1. Create directory `.claude/skills/pr-review/`.
2. Create `.claude/skills/pr-review/SKILL.md`. Write the YAML frontmatter block with exactly these five keys in this order: `name: pr-review`; `description: <one sentence — see below>`; `argument-hint: "[pr-number]"`; `disable-model-invocation: true`; `allowed-tools: Read Bash(gh *) Bash(git *) Agent`.
3. Set the `description` value to a single sentence that names the skill's purpose and the GitHub PR domain — e.g. "Run an AI-assisted review of a specific GitHub pull request, then triage the findings interactively before posting them as PR comments." (Final wording is the implementer's; constraint is: one sentence, mentions GitHub PR, mentions interactive triage.)
4. After the closing `---`, add H1 `# PR Review`.
5. Add the five H2 skeleton headers in this exact order with no body yet: `## What this does`, `## Fetch the PR`, `## Delegate to code-reviewer`, `## Triage findings`, `## What this skill will not do`.
6. Save the file. Confirm `head -1 .claude/skills/pr-review/SKILL.md` returns `---`.

**Commit:** `feat(skills): scaffold pr-review skill with frontmatter and section skeleton`

---

### Task 2: Fill in the "What this does" section + `$ARGUMENTS` handling

**Files:** `.claude/skills/pr-review/SKILL.md`

**Tests:**

```
manual-checks:
  - The section "## What this does" contains a one-paragraph statement of the skill's purpose using `$ARGUMENTS` as the PR number reference (matching the pattern from analyze-code, find-patterns, web-search).
  - The paragraph explicitly states the skill is invoked as `/pr-review <pr-number>` and walks Fetch → Delegate → Triage → Post.
  - A short input-validation block follows the paragraph and covers all four branches from Research §"Key Insights for the Planner" point 4:
      (a) `$ARGUMENTS` is empty/missing — ask the user for a PR number and wait.
      (b) `$ARGUMENTS` is non-numeric — stop with a clear error, do not call `gh`, do not invoke the agent.
      (c) `$ARGUMENTS` is numeric but the PR does not exist / is closed/merged / user lacks access — report the `gh` error verbatim and stop without invoking the agent.
      (d) `$ARGUMENTS` is numeric and the PR is accessible — continue to Fetch.
  - The validation block names the regex or rule used to detect non-numeric input (positive integer match) so the model is not left to interpret "non-numeric" loosely.
  - Skill(github-tool-preference) is invoked by name once in this section as the first thing before any `gh` call is described.
```

**Implementation:**

1. Under `## What this does`, write one paragraph stating: the skill is invoked as `/pr-review $ARGUMENTS`; it fetches PR `$ARGUMENTS` via `gh`, delegates engineering review to the `code-reviewer` agent, walks the user through each finding with keep/drop/edit, and posts only the kept findings on explicit user approval.
2. Immediately after that paragraph, add a subsection (H3 or labeled block) titled "Input validation" or "If `$ARGUMENTS` is missing or invalid".
3. List the four branches as a numbered list:
   - "If `$ARGUMENTS` is empty: ask the user 'Which PR number do you want to review?' and wait for a positive integer reply. Do not proceed until you have one."
   - "If `$ARGUMENTS` is not a positive integer (regex `^[1-9][0-9]*$`): stop and reply 'PR number must be a positive integer. Got: <value>.' Do not call `gh`. Do not invoke the agent."
   - "If `$ARGUMENTS` is a positive integer but `gh pr view <pr-number>` returns non-zero (PR not found, closed, merged, or access denied): print the exact `gh` stderr and stop. Do not invoke the agent."
   - "If `$ARGUMENTS` is a positive integer and `gh pr view` succeeds: continue to ## Fetch the PR."
4. At the top of this section, before the validation block, add the line: "Before any `gh` shell-out in this skill, invoke `Skill(github-tool-preference)` to confirm `gh` is the correct tool."
5. Save and re-verify the skeleton remains intact (other H2 sections still present and empty).

**Commit:** `feat(skills): document pr-review purpose and input validation`

---

### Task 3: Fill in the "Fetch the PR" section

**Files:** `.claude/skills/pr-review/SKILL.md`

**Tests:**

```
manual-checks:
  - The section "## Fetch the PR" lists the exact gh commands the skill must run, in this order:
      1. `gh repo view --json nameWithOwner -q .nameWithOwner` — confirm the current directory is inside a GitHub repo.
      2. `gh pr view <pr-number> --json number,title,body,author,state,baseRefName,headRefName,isDraft,url,files` — fetch metadata and changed-file list.
      3. `gh pr diff <pr-number>` — fetch the unified diff.
  - The section states that if `gh repo view` fails (not a GitHub repo), the skill stops with the gh error.
  - The section states that if `state` is not `OPEN` (i.e. CLOSED or MERGED), the skill reports the state and stops without invoking the agent. (Per spec Requirements / Fetching the PR.)
  - The section states the four data points the skill carries forward to the Delegate step: PR title, PR body, changed-file list (from `files`), and full diff (from `gh pr diff`).
  - No `gh pr review` invocation appears anywhere in this section (defense-in-depth — that command is reserved for the Non-Goals section).
```

**Implementation:**

1. Under `## Fetch the PR`, write a short intro line stating the skill must confirm it is inside a GitHub repo, fetch PR metadata, and fetch the diff — all via `gh`.
2. Add an ordered list of three steps. Step 1: run `gh repo view --json nameWithOwner -q .nameWithOwner`; if it fails, print the stderr and stop. Step 2: run `gh pr view $ARGUMENTS --json number,title,body,author,state,baseRefName,headRefName,isDraft,url,files`; if it fails, print stderr and stop; if `state` is not `OPEN`, print "PR #$ARGUMENTS is <state>. Only OPEN PRs can be reviewed." and stop. Step 3: run `gh pr diff $ARGUMENTS`; if it fails, print stderr and stop.
3. After the three steps, add a sentence: "Carry forward to the Delegate step: PR title, PR body, changed-file list (the `files` array from step 2), and the unified diff text from step 3."
4. Re-read the section and confirm no `gh pr review` form appears.

**Commit:** `feat(skills): document pr-review fetch workflow`

---

### Task 4: Fill in the "Delegate to code-reviewer" section

**Files:** `.claude/skills/pr-review/SKILL.md`

**Tests:**

```
manual-checks:
  - The section "## Delegate to code-reviewer" instructs the model to invoke the `code-reviewer` agent by name (no JSON/YAML protocol — prose only, matching the validate and implement skills).
  - The section contains, verbatim or substantially identical, the no-plan handoff text from Research §"Key Insights for the Planner" point 3:
      "This is an external PR review, not a pipeline feature. No `3_plan.md` exists. Skip plan alignment entirely and review against engineering quality only (correctness, security, code quality, test quality). Here is the PR title, body, changed-file list, and full diff. Return findings in your standard Location / Problem / Fix shape."
  - The section names the four context items passed to the agent: PR title, PR body, changed-file list, full diff.
  - The section describes what to do when the agent returns the approval string "Approved — continue implementation." (or its variants): tell the user "No findings — nothing to triage." and exit the skill without posting anything. (From Research §code-reviewer / Approval string.)
  - The section does NOT invent a severity tagging scheme. Findings are presented exactly as the agent returned them. (From Research §code-reviewer / Severity language.)
```

**Implementation:**

1. Under `## Delegate to code-reviewer`, write the intro sentence: "Invoke the `code-reviewer` agent. Pass the PR title, PR body, changed-file list, and full diff as context."
2. Add a fenced block (regular markdown code fence, no language tag — it is prose the model relays, not code) containing the no-plan handoff text exactly as specified in Research point 3.
3. After the fenced block, add: "The agent returns a list of findings. Each finding has a Location (file + line or function), a Problem statement, and a Fix suggestion. Do not modify, summarize, or re-rank the findings — they pass through verbatim to the Triage step."
4. Add a one-paragraph "No findings" branch: "If the agent's response is the approval string (e.g. 'Approved — continue implementation.') or otherwise reports no findings, tell the user 'PR #$ARGUMENTS has no findings — nothing to triage.' and stop. Do not post anything."

**Commit:** `feat(skills): document pr-review delegation to code-reviewer`

---

### Task 5: Fill in the "Triage findings" section with accepted-input table

**Files:** `.claude/skills/pr-review/SKILL.md`

**Tests:**

```
manual-checks:
  - The section "## Triage findings" opens with a numbered overview of all findings (one-line summary each) before per-finding triage begins.
  - The section specifies one-by-one triage as the default, with an explicit batch opt-in: at the first triage prompt, if the user replies `batch` or `review all`, switch to batch mode. (From Research Open Question 1 / recommendation.)
  - One-by-one mode prompts per finding with the full finding text and accepted inputs: `keep`, `drop`, `edit`.
  - A literal accepted-inputs table appears in the section. The table has at least these rows: `keep` → mark this finding as kept; `drop` → mark this finding as dropped; `edit` → enter inline rewrite for this finding; `show checklist` → print kept/dropped/remaining; `go to N` / `back to N` → re-open finding N for re-decision; anything else → re-prompt without advancing.
  - The edit branch is inline rewrite (not conversational): skill prints the current finding in a fenced block, asks "Paste the revised version.", stores the pasted text verbatim, then prompts keep/drop on the revised text. (From Research Open Question 3 / recommendation.)
  - Comment formatting: when a kept finding is staged for posting, the body is constructed as `**<path>:<line>** — <finding text>` using the em-dash. If the agent gave a function name instead of a line, the body is `**<path>** (\`<function>\`) — <finding text>`. (From Research Open Question 2 / recommendation.)
  - Batch mode is described: skill prints all findings numbered; user replies with a single multi-line list like `1 keep, 2 drop, 3 edit, 4 keep`; `edit` entries drop back into per-finding mode for just those.
  - The section explicitly states the running checklist lives only in the conversation — it is never persisted to disk. (From spec / Session integrity.)
  - A "Post step" subsection at the end states: after every finding is triaged, summarize the final checklist and ask the literal question "Post these N comments to PR #<pr-number> now? (yes/no)".
  - The Post step lists the unambiguous affirmatives: `yes`, `post`, `ship it`. Any other reply (including silence, "looks good", "let me think", ambiguous responses) is treated as "no" and nothing is posted.
  - The Post step specifies the posting command form: `printf '%s' "<finding-body>" | gh pr comment <pr-number> --body-file -` (one invocation per kept finding). It explicitly forbids the `--body "<text>"` form because of shell-escaping bugs on findings containing backticks, dollar signs, or newlines.
  - The Post step states: after each gh call, capture the comment URL from stdout on success or the stderr on failure; do not retry silently; if any post fails, surface the error and ask the user how to proceed.
  - The Post step states: if the user abandons the session before giving an affirmative, nothing is posted. (Defense-in-depth — same statement appears in Non-Goals.)
```

**Implementation:**

1. Under `## Triage findings`, write the intro: "When the code-reviewer returns findings, present them to the user and walk through each one before anything is posted to GitHub."
2. Add H3 `### Overview`: "Before per-finding triage, print a numbered list of all findings with a one-line summary each. Example: `1. src/foo.ts:42 — useAuthToken does not handle expired tokens.`"
3. Add H3 `### Triage mode`: "Default to one-by-one. At the very first triage prompt, if the user replies `batch` or `review all`, switch to batch mode (described below). Otherwise stay one-by-one."
4. Add H3 `### One-by-one mode`: describe per-finding prompt format (print finding number, location, problem, fix; then ask for input).
5. Add an accepted-inputs table under one-by-one mode:

   | Input | Effect |
   |-------|--------|
   | `keep` | Mark finding as kept. Advance to next finding. |
   | `drop` | Mark finding as dropped. Advance to next finding. |
   | `edit` | Print the current finding in a fenced block. Ask "Paste the revised version." Store the user's reply verbatim as the new finding body. Re-prompt keep/drop on the revised text. Do not interpret or paraphrase the revised text. |
   | `show checklist` | Print the current state: kept findings (with numbers), dropped findings (with numbers), remaining findings (with numbers). Do not advance. |
   | `go to N` / `back to N` | Re-open finding N for re-decision. The previous decision on N is cleared. After N is re-decided, resume from where you left off. |
   | anything else | Re-prompt the current finding without advancing. Do not interpret as `keep` or `drop`. |

6. Add H3 `### Batch mode`: "Print all findings numbered with full text. Ask the user to reply with one line per finding in the form `<n> keep`, `<n> drop`, or `<n> edit`, separated by commas or newlines. Apply the keep/drop decisions in one pass. For each `edit`, drop back into per-finding one-by-one mode just for those findings. Then resume to the Post step."
7. Add H3 `### Comment formatting`: "Every kept finding is posted with the location as a bold prefix. If the agent gave a file and line, the body is: `**<path>:<line>** — <finding text>`. If the agent gave a file and a function name instead, the body is: `**<path>** (\`<function>\`) — <finding text>`. The separator is the em-dash `—` (not a hyphen-minus). The finding text is the agent's wording, or the user's revised wording if the finding was edited."
8. Add H3 `### State`: "The running checklist exists only in this conversation. Never persist it to disk. Never write to `.docs/` for this skill. If the user closes the session, the checklist is lost and nothing is posted."
9. Add H3 `### Post step`: write the post-confirmation flow:
   - Summarize the final checklist.
   - Ask verbatim: "Post these N comments to PR #$ARGUMENTS now? (yes/no)"
   - Accept only `yes`, `post`, `ship it` as affirmatives. Anything else — including silence, "looks good", "let me think", "later", emoji, ambiguous responses — is a no. Tell the user "Nothing was posted." and stop.
   - On affirmative: for each kept finding, invoke `Skill(github-tool-preference)`, then run `printf '%s' "<finding-body>" | gh pr comment $ARGUMENTS --body-file -`. Capture the comment URL from stdout. If any call exits non-zero, print the gh stderr and ask "Finding N failed to post. Continue posting the rest, retry, or stop?" — do not retry silently.
   - After all posts, print a per-finding result list: each kept finding's number, location prefix, and either the resulting comment URL or the error from gh.
10. Confirm no `gh pr review --approve` or `gh pr review --request-changes` appears anywhere in the Triage section (those belong only in the Non-Goals section, named once and only once).

**Commit:** `feat(skills): document pr-review triage and posting flow`

---

### Task 6: Fill in the "What this skill will not do" section with named negative constraints

**Files:** `.claude/skills/pr-review/SKILL.md`

**Tests:**

```
manual-checks:
  - The section "## What this skill will not do" contains a bullet list of hard negative constraints.
  - The list explicitly names the forbidden commands by exact flag, not abstract behavior. At minimum:
      - "Do not call `gh pr review --approve` under any circumstance, even if the user asks you to."
      - "Do not call `gh pr review --request-changes` under any circumstance, even if the user asks you to."
  - The list includes:
      - "Do not call `gh pr merge`, `gh pr close`, `gh pr edit`, or any other PR-modifying command beyond `gh pr comment`."
      - "Do not add inline review comments anchored to specific diff lines. Only top-level PR comments via `gh pr comment`."
      - "Do not post anything to GitHub before the explicit `yes` / `post` / `ship it` affirmation at the end of triage."
      - "Do not persist the triage checklist to disk. The session lives only in this conversation."
      - "Do not add `Co-Authored-By`, 'Generated by', '🤖', or any AI attribution to posted comment bodies. The comment must read as the user would have written it."
      - "Do not invent severity tags (CRITICAL/HIGH/MEDIUM/LOW). Pass the code-reviewer's findings through as-is."
      - "Do not run lint, type-check, e2e tests, or any local build against the PR branch. Review is based on the diff and changed files only."
      - "Do not wire this skill into the `/feature` pipeline or invoke it from any pipeline agent. It is invoked directly by the user."
  - The section includes a "Refusal" subsection or paragraph: if the user says "approve this PR", "go ahead and approve", "submit a request changes review", or anything semantically equivalent, the skill refuses with a one-sentence explanation that approve and request-changes are human-only verdicts, and offers to post the comments instead. The refusal does not call any gh subcommand.
```

**Implementation:**

1. Under `## What this skill will not do`, add a short intro line: "These are hard constraints. The wording matters because there is no enforcement layer below this prose."
2. Add the bulleted list of negatives. Use the exact wording from the test block above for the two `gh pr review` lines — those are load-bearing per Research §"Key Insights" point 2.
3. Add a final paragraph titled "Refusal" (H3 or bold inline label): "If the user asks the skill to approve the PR, request changes, merge, close, or otherwise change the PR's state beyond posting a comment, reply with: 'Approve / request-changes / merge are human-only actions for this skill. I can post the kept comments to PR #$ARGUMENTS as ordinary review comments if you want — but I will not submit a formal review verdict.' Then wait for the user's next instruction. Do not call any `gh` subcommand in response to the refused request."
4. Re-read the entire SKILL.md top to bottom. Confirm:
   - Frontmatter is intact and unmodified since Task 1.
   - The five H2 sections appear in the order specified in Task 1.
   - No section contains TODO markers, placeholder text, or unresolved questions.
   - `gh pr review --approve` and `gh pr review --request-changes` each appear at most twice in the whole file (once optionally inside an "even the model might be tempted" note, once in this Non-Goals list) and never as an instruction *to run* them.

**Commit:** `feat(skills): document pr-review non-goals and refusal behavior`

---

### Task 7: Verify the skill against the spec's acceptance criteria

**Files:** `.claude/skills/pr-review/SKILL.md` (read-only verification — no edits expected unless a gap is found)

**Tests:**

```
manual-checks (each line maps to a spec acceptance criterion):
  - AC1: `.claude/skills/pr-review/SKILL.md` exists with valid frontmatter (name pr-review, description, argument-hint, allowed-tools).
  - AC2: The "What this does" + "Fetch the PR" + "Delegate" sections together describe the `/pr-review 1250` happy path end-to-end.
  - AC3: The "What this does" / Input validation block covers the missing-argument branch (ask and wait).
  - AC4: The Input validation block covers the non-numeric branch (stop with a clear error, no gh call, no agent invocation).
  - AC5: The Fetch section covers the nonexistent-PR branch (report gh error, stop without invoking agent).
  - AC6: The Triage section covers keep / drop / edit per finding with checklist tracking.
  - AC7: The Triage section's accepted-inputs table covers "show checklist" at any time.
  - AC8: The Post step requires explicit "yes" / "post" / "ship it" before any gh pr comment call.
  - AC9: The Post step uses `gh pr comment --body-file -` (one call per kept finding).
  - AC10: The Non-Goals section names `gh pr review --approve` by flag and forbids it.
  - AC11: The Non-Goals section names `gh pr review --request-changes` by flag and forbids it.
  - AC12: The State / Session integrity language confirms abandoned sessions post nothing.
  - AC13: The Non-Goals section forbids Co-Authored-By / "Generated by" / AI attribution in posted comment bodies.
```

**Implementation:**

1. Re-read `.claude/skills/pr-review/SKILL.md` end-to-end.
2. Walk down each row of the manual-checks list above. For each row, identify the section and quote (mentally or in the verification report) the sentence that satisfies it.
3. If any row has no matching sentence, identify which prior task's section it belongs in, edit the file to add the missing wording in that section, and verify the rest of the file is still consistent.
4. If edits are required, this task's commit covers them. If no edits are required, skip the commit — the prior six commits are sufficient. (Plan does not require an empty commit.)

**Commit:** `docs(skills): tighten pr-review wording for acceptance criteria` *(only if Task 7 required edits)*

---

## Out of Scope

Each item below was explicitly excluded by the spec, the research findings, or by YAGNI. None of these may creep into implementation.

- **Unit tests, lint, type-check, coverage tasks.** The only deliverable is a markdown file with YAML frontmatter. There is no code to unit-test. The skill's correctness is verified by reading it and confirming the manual-checks in each task. (From Research §"Key Insights" point 7.)
- **A `template.md`, `scripts/`, or `references/` directory under `pr-review/`.** Research is explicit: the skill is a single `SKILL.md` file. Anything else is YAGNI. (From Research §"Gaps" and §"Key Insights" point 1.)
- **Modifying the `code-reviewer` agent.** The spec is explicit that `code-reviewer` is consumed as-is. Any improvement to the agent is a separate feature. (From spec Constraints.)
- **Wiring `pr-review` into `/feature` or any pipeline agent.** The skill is user-invoked only. (From spec Non-Goals.)
- **Inline review threads anchored to diff lines.** Only top-level PR comments via `gh pr comment`. Inline threads can be reconsidered as a follow-up feature. (From spec Non-Goals.)
- **Local build, lint, type-check, or e2e tests against the PR branch.** Review is based on the diff and changed files only — no checkout, no install. (From spec Non-Goals.)
- **Severity tags (CRITICAL/HIGH/MEDIUM/LOW) on findings.** That is the `security-review` skill's responsibility. `pr-review` passes the code-reviewer's findings through verbatim. (From Research §code-reviewer / Severity language.)
- **Persisting the triage checklist to disk.** Session state lives only in the conversation. (From spec / Session integrity and Research §Architectural Context.)
- **Submitting a formal "Approve" or "Request changes" review** via `gh pr review --approve` or `gh pr review --request-changes`. The skill must refuse with an explanation. (From spec Non-Goals and Acceptance Criteria.)
- **Auto-invocation by the model.** Frontmatter sets `disable-model-invocation: true`. The skill runs only when the user types `/pr-review`. (From Research §Frontmatter pattern.)
