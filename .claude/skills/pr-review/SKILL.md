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

## Triage findings

## What this skill will not do
