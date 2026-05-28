---
name: define
description: Define step agent. Use when a user wants to spec out a new feature, clarify requirements, or create a spec document. Handles the full Define phase of the development workflow.
model: opus
skills:
  - agent-context
  - create-pr
  - git-commit
  - spec
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
2. Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Research) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Define accomplished, (2) key findings and decisions made during discovery (including why, when non-obvious), (3) relevant context for the Research phase — scope boundaries, anything from the conversation that shaped `1_spec.md` but isn't self-evident from the spec itself.
3. Commit the spec and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage and commit only those two files:

   ```bash
   git add <feature.folder>/1_spec.md <feature.folder>/context.yaml
   git commit -m "docs(spec): add spec for <feature.name from context.yaml>"
   ```

   Do not use `git add -A` or `git add .` — stage explicit paths only.
4. Push the branch to remote with `git push -u origin <feature.branch from context.yaml>`. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return — do not proceed to the PR step.
5. Run `gh pr create --draft --base <feature.base_branch from context.yaml> --title "<feature name>"`. Use the `create-pr` skill for title format. Leave the PR body minimal — it will be written by the Document agent at the end of the workflow.
6. Return. The feature orchestrator will present the spec for user approval.

## Push-failure escalation

If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

```yaml
# Merge into existing workflow block — do not replace other fields
workflow:
  escalated: true
  escalation_reason: |
    git push failed during the Define step.
    [Exit code and the exact stderr from the failed push]
    [Assessment: e.g. branch out of date with remote, missing credentials, network error]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
