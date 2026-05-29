# Spec: PR Review Skill

**Date:** 2026-05-29
**Status:** Draft

## Summary

Add a new `pr-review` skill that lets the user run an AI-assisted review of a specific GitHub pull request without ever giving the AI the authority to actually approve, request changes, or post unreviewed comments. The user invokes it as `/pr-review <pr-number>`. The skill fetches the PR, delegates the actual review work to the existing `code-reviewer` agent, returns the findings to the user, then walks through each finding interactively so the user can decide which to keep. Only the findings the user explicitly keeps are posted to the PR — and only after a final explicit "post now" approval. The skill produces ordinary review *comments*; it never submits an "Approve" or "Request changes" review.

## Problem Statement

Today there is no first-class way to use the `code-reviewer` agent against a real GitHub pull request from this repo's workflow. The agent is wired into the internal `Implement → Validate` pipeline and reviews local feature branches against a `3_plan.md`. When the user wants a second opinion on someone else's PR, they have to either copy/paste the diff into a conversation, or run the agent ad-hoc with no structured way to triage its findings before they land as PR comments. Two specific pains result:

- The user has no checklist-style triage step between "agent generated 12 findings" and "comments appear on the PR." Findings either all get posted, or none do.
- There is a real risk of the AI posting a formal "Approve" or "Request changes" review on someone else's PR. The user's strong preference — and the policy this skill encodes — is that those verdicts are human-only.

## Goals

- The user can run `/pr-review <pr-number>` from inside this repo and get a structured set of code review findings for that PR.
- Every finding is presented to the user one at a time (or as a reviewable list, see Open Questions) with `keep` / `drop` options before anything is posted.
- A running checklist tracks which findings are kept and which are dropped, visible to the user at any time during the review session.
- Nothing is posted to GitHub until the user gives an explicit, separate "post now" approval after triage is complete.
- When posting, the skill posts kept findings as ordinary PR comments only. It never submits an "Approve" or "Request changes" review.

## Non-Goals

- This skill does **not** approve PRs. Submitting an "Approve" review is reserved for a human and the skill will refuse to do so even if asked.
- This skill does **not** request changes on PRs. Submitting a "Request changes" review is reserved for a human and the skill will refuse to do so even if asked.
- This skill does **not** merge PRs, close PRs, edit PR titles or descriptions, or change PR labels.
- This skill does **not** add inline review comments anchored to specific diff lines. Findings are posted as top-level PR comments (issue comments on the PR). Inline review threads can be reconsidered in a follow-up.
- This skill is not a replacement for the existing `Validate` step or `senior-reviewer` agent — it is purely a tool for reviewing *external* PRs interactively, not for gating the user's own feature work.
- This skill does not run e2e tests, lint, type-check, or any local build against the PR branch. It reviews based on the diff and changed files only.
- This skill is not wired into the `/feature` pipeline. It is invoked directly by the user.

## User Stories

- As a reviewer, I want to run `/pr-review 1250` and get a structured list of findings on PR #1250 so that I have a starting point for my own review without rereading the entire diff from scratch.
- As a reviewer, I want to see each finding one at a time with a keep/drop choice so that I can apply my own judgment and discard noise before anything is posted publicly.
- As a reviewer, I want a running checklist of kept vs. dropped findings during triage so that I can see what I've decided without scrolling.
- As a reviewer, I want the skill to wait for an explicit "post now" confirmation before any comment hits GitHub so that I never get surprised by something I didn't approve being posted on someone else's PR.
- As a reviewer, I want the skill to refuse to submit an "Approve" or "Request changes" review even if I or the agent asks for it so that the formal verdict on a PR always reflects a human decision, not an AI's.
- As a reviewer, if I abandon the session (close the conversation, hit cancel during triage), I want nothing to be posted to the PR so that an unfinished review never produces a public comment.

## Requirements

**Invocation**

- A slash command `/pr-review` is available. Calling `/pr-review <pr-number>` starts a review session for that PR.
- If the user invokes `/pr-review` without a PR number, the skill asks the user which PR they want to review and waits for a number before continuing.
- The skill validates that the argument is a positive integer. If it isn't, the skill stops and asks for a valid PR number.

**Fetching the PR**

- The skill uses the GitHub CLI (`gh`) for all GitHub interactions, in line with `Skill(github-tool-preference)`. It only falls back to `mcp__github__*` if `gh` is unavailable or fails for a reason the CLI cannot resolve.
- The skill detects the current repository from the working directory (`gh repo view --json nameWithOwner`).
- The skill fetches the PR's metadata (title, author, base/head branches, state) and the full diff (`gh pr diff <pr-number>`) and the list of changed files (`gh pr view <pr-number> --json files`).
- If the PR does not exist, is closed/merged, or the current user lacks access, the skill reports the error and stops without invoking the agent.

**Delegating the review**

- The skill invokes the existing `code-reviewer` agent with the PR diff, changed file list, PR title, and PR body as context. The skill does **not** modify the `code-reviewer` agent — it consumes it as-is.
- The skill makes clear to the agent that there is no `3_plan.md` for this review (this is an external PR, not a pipeline feature), so the agent should review against engineering quality only: correctness, security, code quality, test quality. Plan alignment is N/A and should be skipped without complaint.
- The agent returns its findings as a list. Each finding has a location (file + line/function), a problem statement, and a fix suggestion — matching the existing `code-reviewer` output shape.

**Triage checklist**

- After the agent returns, the skill presents a numbered list of findings to the user with a one-line summary each.
- The skill then walks the user through each finding individually, presenting the full finding text and asking `keep` or `drop`.
- The user can also reply `edit` to revise the wording of a finding before deciding keep/drop on the revised version.
- At any point during triage the user can ask "show me the checklist" or equivalent, and the skill prints the current state (kept findings, dropped findings, remaining findings).
- The user can navigate back to a prior finding and change its decision before the post step. (Mechanism: the user references the finding by number; the skill updates the checklist.)

**Posting**

- After every finding has been triaged (kept, dropped, or edited-then-decided), the skill summarizes the final checklist and explicitly asks: "Post these N comments to PR #X now? (yes/no)"
- Posting only happens on an unambiguous affirmative ("yes", "post", "ship it"). Anything else — including silence, "looks good," "let me think," `Ctrl+C`, ambiguous responses — does **not** trigger posting.
- Each kept finding is posted as a separate top-level PR comment via `gh pr comment <pr-number> --body <finding text>`.
- The skill does **not** call `gh pr review --approve` under any circumstance.
- The skill does **not** call `gh pr review --request-changes` under any circumstance.
- If the user tries to instruct the skill to approve or request changes (e.g. "go ahead and approve it"), the skill refuses with a short explanation that those actions are human-only, and offers to post the comments instead.
- After posting, the skill reports back which comments were posted successfully and which (if any) failed, with the error from `gh`.

**Session integrity**

- If the user abandons the session at any point before the explicit "post now" confirmation, nothing is posted. The checklist exists only in the conversation; the skill does not persist it to disk or post partial results.
- The skill does not retry posting silently. If `gh pr comment` fails, the skill surfaces the error and asks the user how to proceed.

## Constraints

- Must use `gh` CLI as the default tool for GitHub interaction (`Skill(github-tool-preference)`). `mcp__github__*` is fallback only.
- Must reuse the existing `code-reviewer` agent without modification. Any improvement to the agent itself is out of scope for this feature.
- Must follow the existing skill layout under `.claude/skills/<skill-name>/SKILL.md` and adhere to the same frontmatter conventions used by other skills in this repo (`name`, `description`, optional `argument-hint`, `disable-model-invocation`, `allowed-tools`).
- The skill is invoked directly by the user via slash command; it is **not** added to the `/feature` pipeline or invoked by any pipeline agent.
- The skill must produce no `Co-Authored-By` trailers and no AI attribution in any posted comment. Comments are posted as the authenticated `gh` user and the body should read as the user would write it.

## Acceptance Criteria

- [ ] `.claude/skills/pr-review/SKILL.md` exists with valid frontmatter (`name: pr-review`, a `description`, an `argument-hint` for the PR number, and any necessary `allowed-tools`).
- [ ] Invoking `/pr-review 1250` in a repo with a PR #1250 fetches the PR via `gh`, runs the `code-reviewer` agent against the diff, and returns a numbered list of findings.
- [ ] Invoking `/pr-review` with no argument prompts the user for a PR number and waits.
- [ ] Invoking `/pr-review abc` (non-numeric) stops with a clear error and does not call `gh` or the agent.
- [ ] Invoking `/pr-review 99999999` (nonexistent PR) reports the `gh` error and stops without invoking the agent.
- [ ] After the agent returns findings, the skill walks the user through each finding with `keep` / `drop` / `edit` options and tracks decisions in a checklist.
- [ ] At any point during triage, asking for the checklist prints kept, dropped, and remaining findings.
- [ ] No `gh pr comment` call is ever made before the user gives explicit "post now" affirmation.
- [ ] On affirmative confirmation, only the kept findings are posted, one comment per finding, via `gh pr comment`.
- [ ] If the user types "approve this PR" or similar during the session, the skill refuses and does not call `gh pr review --approve`.
- [ ] If the user types "request changes" or similar during the session, the skill refuses and does not call `gh pr review --request-changes`.
- [ ] If the user abandons the session before the post step, no comments appear on the PR.
- [ ] Posted comments contain no AI attribution, `Co-Authored-By` trailers, or "Generated by" lines.

## Open Questions

- **Triage UX — one-by-one vs. batch.** The spec currently locks in one-finding-at-a-time triage. For PRs with 15+ findings this gets tedious. Should the skill optionally accept a "review all at once" mode where the user replies with the keep/drop decisions as a list? Defaulting to one-by-one with an explicit `batch` opt-in is the leading candidate. Decide during Research/Plan.
- **Comment formatting.** Kept findings post as top-level PR comments. Should the body include the file path and line number in a standard prefix (e.g. `**src/foo.ts:42** — ...`) so reviewers reading the PR can jump to the location, or should the body just be the finding text? Recommendation: include a standard prefix; finalize the exact format in Plan.
- **Edit mechanism.** When the user chooses `edit` on a finding, does the skill present the full finding for inline rewrite, or does it ask "what do you want to change?" and apply the change conversationally? Recommendation: inline rewrite (skill prints the finding, user pastes the revised version). Finalize in Plan.
