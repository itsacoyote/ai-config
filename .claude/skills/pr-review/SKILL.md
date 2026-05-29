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

## Delegate to code-reviewer

## Triage findings

## What this skill will not do
