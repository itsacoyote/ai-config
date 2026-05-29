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

## What this skill will not do
