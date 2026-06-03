---
name: pr-review
description: Run an AI-assisted review of a specific GitHub pull request, then triage the findings interactively before posting them as PR comments.
argument-hint: "[pr-number]"
disable-model-invocation: true
allowed-tools: Read Bash(gh *) Bash(git *) Agent
---

# PR Review

## What this does

Before any `gh` shell-out in this skill, invoke `Skill(github-tool-preference)` to confirm `gh` is the correct tool.

This skill is invoked as `/pr-review $ARGUMENTS`. It fetches PR `$ARGUMENTS` from the current repository via `gh`, delegates the engineering review to the `code-reviewer` agent, walks the user through each finding interactively (keep / drop / edit), and posts only the findings the user explicitly keeps — and only after a final explicit "post now" approval. The workflow is: Fetch → Delegate → Triage → Post.

### Input validation

1. **If `$ARGUMENTS` is empty:** ask the user "Which PR number do you want to review?" and wait for a positive integer reply. Do not proceed until you have one.
2. **If `$ARGUMENTS` is not a positive integer (regex `^[1-9][0-9]*$`):** stop and reply "PR number must be a positive integer. Got: `<value>`." Do not call `gh`. Do not invoke the agent.
3. **If `$ARGUMENTS` is a positive integer but `gh pr view <pr-number>` returns non-zero** (PR not found, closed, merged, or access denied): print the exact `gh` stderr and stop. Do not invoke the agent.
4. **If `$ARGUMENTS` is a positive integer and `gh pr view` succeeds:** continue to ## Fetch the PR.

## Fetch the PR

Confirm the current directory is inside a GitHub repo, fetch PR metadata, and fetch the diff — all via `gh`.

1. Run `gh repo view --json nameWithOwner -q .nameWithOwner`. If it exits non-zero, print the stderr and stop.
2. Run `gh pr view $ARGUMENTS --json number,title,body,author,state,baseRefName,headRefName,isDraft,url,files`. If it exits non-zero, print the stderr and stop. If the `state` field is not `OPEN`, print "PR #$ARGUMENTS is `<state>`. Only OPEN PRs can be reviewed." and stop without invoking the agent.
3. Run `gh pr diff $ARGUMENTS`. If it exits non-zero, print the stderr and stop.

Carry forward to the Delegate step: PR title, PR body, changed-file list (the `files` array from step 2), and the unified diff text from step 3.

## Delegate to code-reviewer

Invoke the `code-reviewer` agent. Pass the PR title, PR body, changed-file list, and full diff as context.

Use this handoff text verbatim:

```
This is an external PR review, not a pipeline feature. No `3_plan.md` exists. Skip plan alignment entirely and review against engineering quality only (correctness, security, code quality, test quality). Here is the PR title, body, changed-file list, and full diff. Return findings in your standard Location / Problem / Fix shape.
```

The agent returns a list of findings. Each finding has a Location (file + line or function), a Problem statement, and a Fix suggestion. Do not modify, summarize, or re-rank the findings — they pass through verbatim to the Triage step.

If the agent's response is the approval string (e.g. "Approved — continue implementation.") or otherwise reports no findings, tell the user "PR #$ARGUMENTS has no findings — nothing to triage." and stop. Do not post anything.

## Triage findings

When the code-reviewer returns findings, present them to the user and walk through each one before anything is posted to GitHub.

### Overview

Before per-finding triage, print a numbered list of all findings with a one-line summary each. Example:

```
1. src/foo.ts:42 — useAuthToken does not handle expired tokens.
2. src/bar.ts:17 — Missing null check on response.data.
```

### Triage mode

Default to one-by-one. At the very first triage prompt, if the user replies `batch` or `review all`, switch to batch mode (described below). Otherwise stay one-by-one for the entire session.

### One-by-one mode

For each finding, print the finding number, location, problem, and fix in full. Then ask the user for input.

Accepted inputs:

| Input | Effect |
|-------|--------|
| `keep` | Mark finding as kept. Advance to next finding. |
| `drop` | Mark finding as dropped. Advance to next finding. |
| `edit` | Print the current finding in a fenced block. Ask "Paste the revised version." Store the user's reply verbatim as the new finding body. Re-prompt keep/drop on the revised text. Do not interpret or paraphrase the revised text. |
| `show checklist` | Print the current state: kept findings (with numbers), dropped findings (with numbers), remaining findings (with numbers). Do not advance. |
| `go to N` / `back to N` | Re-open finding N for re-decision. The previous decision on N is cleared. After N is re-decided, resume from where you left off. |
| anything else | Re-prompt the current finding without advancing. Do not interpret as `keep` or `drop`. |

### Batch mode

Print all findings numbered with full text. Ask the user to reply with one line per finding in the form `<n> keep`, `<n> drop`, or `<n> edit`, separated by commas or newlines. Apply the keep/drop decisions in one pass. For each `edit`, drop back into per-finding one-by-one mode just for those findings. Then resume to the Post step.

### Comment formatting

Every kept finding is posted with the location as a bold prefix. If the agent gave a file and line number, the body is:

```
**<path>:<line>** — <finding text>
```

If the agent gave a file and a function name instead of a line number, the body is:

```
**<path>** (`<function>`) — <finding text>
```

The separator is the em-dash `—` (U+2014, not a hyphen-minus). The finding text is the agent's wording, or the user's revised wording if the finding was edited.

### State

The running checklist exists only in this conversation. Never persist it to disk. Never write to `.docs/` for this skill. If the user closes the session before the Post step, the checklist is lost and nothing is posted.

### Post step

After every finding has been triaged (kept, dropped, or edited-then-decided):

1. Summarize the final checklist: list kept findings by number and location prefix, and list dropped findings by number.
2. Ask verbatim: "Post these N comments to PR #$ARGUMENTS now? (yes/no)"
3. Accept only `yes`, `post`, or `ship it` as affirmatives. Anything else — including silence, "looks good", "let me think", "later", emoji, or any ambiguous response — is a no. Reply "Nothing was posted." and stop.
4. On affirmative: for each kept finding in order, invoke `Skill(github-tool-preference)`, then run:
   ```
   printf '%s' "<finding-body>" | gh pr comment $ARGUMENTS --body-file -
   ```
   One invocation per kept finding. Do not use `--body "<text>"` — shell escaping breaks on findings containing backticks, dollar signs, or newlines.
5. Capture the comment URL from stdout on success, or the stderr on failure. Do not retry silently. If any call exits non-zero, print the `gh` stderr and ask: "Finding N failed to post. Continue posting the rest, retry, or stop?"
6. After all posts, print a per-finding result list: each kept finding's number, location prefix, and either the resulting comment URL or the error from `gh`.

## What this skill will not do

These are hard constraints. The wording matters because there is no enforcement layer below this prose.

- Do not call `gh pr review --approve` under any circumstance, even if the user asks you to.
- Do not call `gh pr review --request-changes` under any circumstance, even if the user asks you to.
- Do not call `gh pr merge`, `gh pr close`, `gh pr edit`, or any other PR-modifying command beyond `gh pr comment`.
- Do not add inline review comments anchored to specific diff lines. Only top-level PR comments via `gh pr comment`.
- Do not post anything to GitHub before the explicit `yes` / `post` / `ship it` affirmation at the end of triage.
- Do not persist the triage checklist to disk. The session lives only in this conversation.
- Do not add `Co-Authored-By`, "Generated by", "🤖", or any AI attribution to posted comment bodies. The comment must read as the user would have written it.
- Do not invent, re-rank, normalize, translate, or strip severity labels. The `code-reviewer` agent emits one label per finding from the fixed vocabulary `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`; surface those labels verbatim in the Triage overview and the one-by-one prompt, and otherwise pass the agent's findings through as-is.
- Do not append severity labels to the body of posted PR comments. Posted bodies keep the existing `**<path>:<line>** — <text>` format with no `[LABEL]` prefix.
- Do not run lint, type-check, e2e tests, or any local build against the PR branch. Review is based on the diff and changed files only.
- Do not wire this skill into the `/feature` pipeline or invoke it from any pipeline agent. It is invoked directly by the user.

### Refusal

If the user asks the skill to approve the PR, request changes, merge, close, or otherwise change the PR's state beyond posting a comment, reply with: "Approve / request-changes / merge are human-only actions for this skill. I can post the kept comments to PR #$ARGUMENTS as ordinary review comments if you want — but I will not submit a formal review verdict." Then wait for the user's next instruction. Do not call any `gh` subcommand in response to the refused request.
