# Spec: Iterative PR Review

**Date:** 2026-06-02
**Status:** Approved

## Summary

Extend the existing `pr-review` skill so that `/pr-review <pr-number>` does the right thing when invoked a second (or third, or fourth) time on the same PR after the author has pushed fixes. Today the skill always runs a fresh review and treats every finding as new, which means the reviewer sees the same comments they already posted the first time around, has to manually re-triage them, and risks double-posting. The iterative behavior auto-detects whether this is the first review or a follow-up by querying the PR for comments authored by the authenticated `gh` user. If prior comments exist, the skill fetches them, fetches the latest diff, runs `code-reviewer` against the new diff, filters out near-duplicates of comments the user has already posted, surfaces any prior comment threads whose anchor code no longer exists in the new diff as "stale", and only puts genuinely new findings into the triage flow. As part of this feature, the `code-reviewer` agent is also updated to emit an explicit severity label per finding from the fixed `CRITICAL / HIGH / MEDIUM / LOW / INFO` vocabulary so the skill can show how the agent rated each finding during triage.

## Problem Statement

The current `pr-review` skill is single-shot. It assumes every invocation is a fresh review of an untouched PR. Reviewers who use it on PRs that go through revision cycles hit three concrete pains:

- **Duplicate findings.** The reviewer posts five comments on round one. The author addresses three of them and pushes. Re-running `/pr-review` produces the same agent output as before — the two un-addressed issues are still in the diff, plus whatever new issues the fix introduced. The reviewer has to mentally diff the new finding list against what they already posted, finding by finding, to spot which two are still relevant. This is exactly the tedium the original skill was meant to remove.
- **Stale comment threads.** When the author rewrites a file and the line the reviewer commented on no longer exists, the GitHub thread is orphaned. Nothing in the skill flags this, so the reviewer doesn't learn about resolved threads unless they manually scroll the PR.
- **Implicit mode confusion.** The reviewer has no signal in the skill telling them "this is a follow-up review, here's what's new." Every session looks identical, which makes the workflow feel mechanical rather than iterative.

These pains show up every time someone uses `pr-review` on a non-trivial PR. The fix is to make the skill aware of its own prior output on the same PR and behave differently on subsequent invocations.

## Goals

- A reviewer running `/pr-review <pr-number>` on a PR they have previously reviewed sees only findings that are genuinely new or different from what they already posted.
- The skill auto-detects "first review" vs. "follow-up review" by inspecting the PR's comments for ones authored by the authenticated `gh` user. The reviewer never has to pass a flag or pick a mode.
- The chosen mode is announced at the top of the session so the reviewer can correct the skill if the auto-detect is wrong for their situation.
- Prior comment threads whose anchored code is gone from the latest diff are surfaced to the reviewer as "code no longer exists" so they can decide whether to resolve them.
- The deduplication logic is conservative: only verbatim or near-verbatim restatements of a prior comment are filtered. Two distinct issues at the same file and line are both shown.
- The triage, edit, refusal, and posting behavior of the existing first-review flow is preserved unchanged for the findings that do reach triage.
- Each finding shown during triage (in both the numbered overview and the one-by-one flow, in both first-review and follow-up modes) displays the severity label the `code-reviewer` agent assigned to that finding, so the reviewer can see how the agent rated it before deciding `keep` / `drop` / `edit`.

## Non-Goals

- The skill does not edit, reply to, or resolve existing PR comment threads on GitHub. "Stale thread" detection is a read-only surfacing — it is up to the reviewer to act on it manually in the GitHub UI.
- The skill does not post inline review comments anchored to diff lines. All posts remain top-level PR comments via `gh pr comment`, identical to the existing skill.
- The skill does not approve, request changes, merge, close, or otherwise mutate the PR beyond posting top-level comments. The hard refusal rules from the existing skill carry over unchanged.
- The skill does not persist any state to disk between invocations. The "what was reviewed before" signal comes entirely from re-querying GitHub for the user's prior comments each time the skill runs. There is no `.docs/` write, no cache file, no local sidecar.
- The skill does not learn from drop decisions across sessions. If the reviewer dropped a finding in round one, the agent may surface it again in round two; the reviewer drops it again. Cross-session "remember my drops" is out of scope.
- The skill does not differentiate between comments the user posted via `pr-review` and comments the user posted manually on the PR. Any comment authored by the authenticated `gh` user counts as "the user has reviewed this PR before."
- The skill does not check out the PR branch, run tests, lint, or any local build. The review remains diff-based.

## User Stories

- As a reviewer who already posted five comments on PR #1250 last week, I want to run `/pr-review 1250` after the author pushed fixes and only see the findings that are genuinely new this round, so I don't waste time re-triaging the same issues.
- As a reviewer, I want the skill to tell me upfront "this looks like a follow-up review — you have 5 prior comments on this PR," so I can correct it if I want a fresh review instead.
- As a reviewer running `/pr-review` on a PR for the first time, I want the skill to behave exactly as it does today — no follow-up logic, no comparison step, no extra prompts.
- As a reviewer doing a follow-up review, I want to know when a comment I posted last round is no longer anchored to code in the current diff, so I can go resolve the thread on GitHub.
- As a reviewer, I want a near-duplicate of a prior comment to be filtered out automatically, but I want two genuinely distinct issues at the same location to both make it through, so I'm not silently missing a real finding because it happens to be near an old one.
- As a reviewer, if the auto-detection mis-classifies my session (e.g. the previous comments on the PR were unrelated chatter, not a review), I want to override the detected mode at the start of the session, so I get the behavior I actually want.

## Requirements

**Mode auto-detection**

- At session start, after PR fetch succeeds, the skill queries the PR for comments authored by the authenticated `gh` user. The authenticated user is resolved via `gh api user --jq .login` once per session.
- The query uses `gh pr view <pr-number> --json comments` (top-level PR comments). The skill filters that list to entries whose `author.login` matches the authenticated user's login.
- If the filtered list is non-empty, the skill enters **follow-up mode**.
- If the filtered list is empty, the skill enters **first-review mode** and proceeds identically to the existing skill behavior.
- The chosen mode is announced to the reviewer as the first line after PR fetch, with a count. Example: `Detected follow-up review — you have 3 prior comments on PR #1250.` or `Detected first review — no prior comments by you on PR #1250.`
- The reviewer may override the detected mode by replying `fresh` (force first-review mode) or `follow-up` (force follow-up mode) at the next prompt. Any other reply proceeds with the detected mode.

**First-review mode (unchanged behavior)**

- When the detected mode is first-review and the reviewer does not override, the skill behaves exactly as the existing `pr-review` skill: Fetch → Delegate → Triage → Post. No deduplication, no stale-thread detection, no extra surfacing.

**`code-reviewer` agent update: emit severity labels**

- The `code-reviewer` agent at `.claude/agents/code-reviewer.md` is updated as part of this feature to emit an explicit severity label on each finding. The label is part of the agent's structured output so the `pr-review` skill can read and display it during triage.
- The label vocabulary is fixed: `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`. No other values are valid. There is no separate `nit` label — what is colloquially called a "nit" is emitted as `LOW` or `INFO` depending on severity.
- The agent emits exactly one label per finding from this vocabulary. The skill does not invent, normalize, re-rank, or translate labels — it surfaces them verbatim.

**Triage display: severity labels (both modes)**

- Every finding from `code-reviewer` carries a severity label assigned by the agent from the fixed `CRITICAL / HIGH / MEDIUM / LOW / INFO` vocabulary. The skill displays that label next to the finding in both the numbered overview and the one-by-one finding prompt.
- Numbered overview format with label: `1. [HIGH] src/foo.ts:42 — useAuthToken does not handle expired tokens.`
- One-by-one finding prompt shows the label on the first line above Location / Problem / Fix.
- If a finding arrives without a label (e.g. a finding the reviewer edited to remove the label, or a degenerate agent output), the skill displays it without a label rather than failing or inventing one.
- Labels are display-only inside the skill. They are not added to the body of posted PR comments — posted bodies retain the existing `**<path>:<line>** — <text>` format with no severity prefix.

**Follow-up mode: fetching prior comments**

- The skill fetches the full body of each prior comment authored by the user via the JSON returned from `gh pr view`. Each prior comment carries: body text, `databaseId` (or equivalent identifier exposed by `gh`), `createdAt` timestamp, and the comment URL.
- The skill carries forward the list of prior comments to the dedup and stale-detection steps. The list lives only in memory for the session.

**Follow-up mode: delegating to code-reviewer**

- The skill invokes `code-reviewer` against the latest PR diff exactly as the first-review flow does. The agent is not modified and is not told about prior comments — it produces findings against the current diff only.
- The handoff text to `code-reviewer` is identical to the existing skill.

**Follow-up mode: deduplication**

- After the agent returns findings, the skill compares each new finding against each prior comment body to filter near-duplicates.
- "Near-duplicate" is defined as: the new finding's body, after normalization, matches the prior comment's body, after normalization, by a verbatim or near-verbatim string match. Normalization lowercases, collapses whitespace, and strips the standard `**<path>:<line>** — ` location prefix used by the existing skill's posted comments.
- Two findings at the same file and line that describe different issues are not duplicates. The match is on issue text, not location.
- A finding that is filtered as a near-duplicate is dropped silently from the triage list. It is not surfaced to the reviewer as a kept item.
- After dedup, the skill prints a one-line summary: `Filtered N near-duplicates of prior comments.` so the reviewer knows the filter ran. The default value of N may be zero.

**Follow-up mode: stale thread detection**

- For each prior comment, the skill checks whether the file path and (where present in the comment body's location prefix) the line/function reference still exists in the latest diff context.
- A prior comment is marked **stale** if its location prefix references a file that is not in the current PR's changed-files list, or references a line range that is no longer present in the current diff for that file. If the prior comment has no parseable location prefix, it is not marked stale (the skill cannot reason about its anchor).
- Stale prior comments are surfaced to the reviewer in a dedicated section printed before triage begins. Format: a numbered list with the comment URL, the location prefix, and the first line of the body. Example heading: `Prior comments where the code is gone (consider resolving on GitHub):`.
- The skill does not silently drop or hide stale prior comments. It does not post or modify anything on GitHub for stale items — surfacing is read-only.

**Follow-up mode: triage**

- After dedup and stale surfacing, the remaining (non-duplicate) new findings are passed into the existing Triage flow unchanged: numbered overview, one-by-one or `batch` mode, `keep` / `drop` / `edit` / `show checklist` / `go to N`, identical comment formatting, identical refusal rules.
- If the dedup step filters every finding, the skill prints `No new findings — all of code-reviewer's output matched comments you already posted. Stale thread review above is still relevant.` and stops without entering triage or the post prompt.

**Follow-up mode: posting**

- Posting behavior is identical to the existing skill. Kept findings are posted as top-level PR comments via `gh pr comment <pr-number> --body-file -`. The explicit `yes` / `post` / `ship it` affirmation is required. No retries on failure. The hard refusal rules carry over.

**Session integrity**

- The skill does not write to `.docs/` or persist anything to disk for this feature.
- Nothing is posted to GitHub before the explicit affirmation at the end of triage.
- If the reviewer abandons the session, nothing is posted and no GitHub state is modified.

## Constraints

- Must reuse the existing `pr-review` skill at `.claude/skills/pr-review/SKILL.md`. This feature edits that skill in place rather than creating a parallel skill.
- Must update the existing `code-reviewer` agent at `.claude/agents/code-reviewer.md` in place to emit a severity label per finding from the fixed `CRITICAL / HIGH / MEDIUM / LOW / INFO` vocabulary. No new agent is created.
- Must use the GitHub CLI (`gh`) as the default tool. Invoke `Skill(github-tool-preference)` before any `gh` shell-out, as the existing skill does. `mcp__github__*` is fallback only.
- Must preserve the existing skill's first-review behavior exactly when no prior comments are detected. The change is additive — new mode-detection branch on top of the existing flow.
- Must preserve all existing hard refusals: no `gh pr review --approve`, no `gh pr review --request-changes`, no merge / close / edit, no inline comments, no AI attribution in posted bodies.
- The authenticated user lookup uses `gh api user --jq .login`. This is the single source of truth for "me" in mode detection.
- Dedup logic operates on comment body text only. Anchor information (line numbers, file paths) is parsed from the standardized location prefix the existing skill emits; the skill does not need a richer comment-metadata API.
- The skill is invoked directly by the user via slash command and is not wired into the `/feature` pipeline.

## Acceptance Criteria

- [ ] Running `/pr-review <N>` on a PR where the authenticated user has zero prior comments produces output identical to the existing skill — Fetch → Delegate → Triage → Post — with the addition of a one-line mode announcement at the top: `Detected first review — no prior comments by you on PR #<N>.`
- [ ] Running `/pr-review <N>` on a PR where the authenticated user has at least one prior comment announces follow-up mode at the top, with a count of prior comments.
- [ ] The authenticated user's login is resolved via `gh api user --jq .login` once per session.
- [ ] Prior comments are fetched via the existing `gh pr view <N> --json comments` call (no new API surface) and filtered by `author.login == <authenticated login>`.
- [ ] In follow-up mode, after `code-reviewer` returns findings, the skill compares each finding's body against each prior comment's body using normalized (lowercased, whitespace-collapsed, location-prefix-stripped) verbatim/near-verbatim matching, and drops findings that match.
- [ ] Two findings at the same file:line whose bodies describe different issues both survive deduplication.
- [ ] After dedup, the skill prints `Filtered N near-duplicates of prior comments.` where N is the count actually filtered (including zero).
- [ ] Prior comments whose location prefix references a file not in the current changed-files list, or a line not present in the current diff hunks for that file, are listed in a `Prior comments where the code is gone (consider resolving on GitHub):` section before triage begins.
- [ ] Prior comments without a parseable location prefix are not marked stale and are not surfaced in the stale section.
- [ ] The reviewer may reply `fresh` at the mode-confirmation prompt to force first-review mode, or `follow-up` to force follow-up mode. Any other reply uses the auto-detected mode.
- [ ] If dedup filters every finding from code-reviewer, the skill prints `No new findings — all of code-reviewer's output matched comments you already posted. Stale thread review above is still relevant.` and stops without entering triage or the post prompt.
- [ ] Surviving findings (post-dedup) are passed into the existing Triage flow unchanged: numbered overview, one-by-one default with `batch` opt-in, `keep` / `drop` / `edit` / `show checklist` / `go to N`, comment formatting `**<path>:<line>** — <text>`, posting via `gh pr comment <N> --body-file -`.
- [ ] All existing hard refusals continue to apply: no approve, no request-changes, no merge, no inline anchored comments, no AI attribution in posted bodies, no writes to `.docs/`.
- [ ] If `gh api user` fails (auth missing, network), the skill prints the `gh` stderr and stops. It does not silently fall back to first-review mode.
- [ ] If `gh pr view <N> --json comments` fails, the skill prints the `gh` stderr and stops. It does not assume zero prior comments.
- [ ] The `code-reviewer` agent at `.claude/agents/code-reviewer.md` is updated to emit a severity label per finding from the fixed vocabulary `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`. No other label values are valid; there is no `nit` label.
- [ ] In both first-review and follow-up modes, the numbered overview prints each finding with the severity label the `code-reviewer` agent assigned, in the form `<n>. [<LABEL>] <location> — <one-line summary>`.
- [ ] In both first-review and follow-up modes, the one-by-one finding prompt displays the severity label on the line above Location / Problem / Fix.
- [ ] Severity labels emitted by `code-reviewer` are passed through verbatim. The skill does not invent, re-rank, normalize, or strip labels from agent output. Labels are not appended to posted PR comment bodies — posting format remains `**<path>:<line>** — <text>` with no label prefix.
- [ ] A finding that arrives without a severity label is displayed without one (no `[LABEL]` token) and proceeds through triage normally. The skill does not fabricate a label.

## Open Questions

All open questions from the discovery conversation have been resolved and folded into the requirements, constraints, and acceptance criteria above. For the record:

- **Is the `code-reviewer` agent update in scope for this feature?** Resolved: yes. The agent at `.claude/agents/code-reviewer.md` is updated in place as part of this feature's implementation to emit an explicit severity label on each finding. See the new requirement block "`code-reviewer` agent update: emit severity labels" and the corresponding constraint and acceptance criterion.
- **What is the label vocabulary, and does `nit` belong in it?** Resolved: the vocabulary is fixed at `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`. There is no separate `nit` label — what people colloquially call a "nit" is emitted as `LOW` or `INFO` depending on severity.
