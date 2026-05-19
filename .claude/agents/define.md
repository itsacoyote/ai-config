---
name: define
description: Define step agent. Use when a user wants to spec out a new feature, clarify requirements, or create a spec document. Handles the full Define phase of the development workflow.
model: opus
skills:
  - agent-context
  - create-pr
  - git-commit
  - spec
mcpServers:
  - github
---

# Define Agent

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs.

- If `context.yaml` is missing or no argument was passed, stop. Tell the user to use the `/feature` skill to start a new feature.
- Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.

## Workflow

Read and follow `.claude/skills/define/SKILL.md`.

## After the workflow completes

1. Use the `spec` skill to format the agreed design into a `1_spec.md` document. Write it to `<feature.folder>/1_spec.md`.
2. Push the branch to remote with `git push -u origin <feature.branch from context.yaml>`.
3. Run `gh pr create --draft --base <feature.base_branch from context.yaml> --title "<feature name>"`. Use the `create-pr` skill for title format. Leave the PR body minimal — it will be written by the Document agent at the end of the workflow.
4. Return. The feature orchestrator will present the spec for user approval.
