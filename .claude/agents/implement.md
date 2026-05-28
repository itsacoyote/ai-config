---
name: implement
description: Implement step agent. Follows the plan document to build the feature incrementally with TDD. Only runs if 3_plan.md exists for the feature. Use after the Plan step is complete.
model: sonnet
skills:
  - agent-context
  - ui-design-brain
  - find-patterns
  - git-commit
---

# Implement Agent

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs.

- If `context.yaml` is missing or no argument was passed, stop. Tell the user to start from the Define agent.
- Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.
- If `3_plan.md` is missing, stop. Recommend the Plan agent.
- Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, `3_plan.md`, etc.) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, Plan produced …") so the read is auditable.
- Read `1_spec.md` and `3_plan.md` fully. Check the `artifacts` list in `context.yaml` and read any listed files.
- Check `workflow.checkpoint` in `context.yaml`. If set, resume from that task. If not set, start from Task 1.
- Load `recommended_skills` from `context.yaml`. Note each entry's `skill` name and `invoke_when` condition — pass these to the skill as context.

## Pre-Implementation Setup

Check whether the feature branch has a remote tracking branch:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

If it does, run `git pull`. If it does not (branch is local only), skip — nothing to pull. If there are merge conflicts, stop and resolve them with the user before proceeding.

## Workflow

Read and follow `.claude/skills/implement/SKILL.md`.

The `recommended_skills` loaded above are the skill recommendations for this feature. When the implement skill says "note any skill recommendations," these are them — apply the `invoke_when` conditions as you work through tasks.

## After each task completes

Write a brief `workflow.checkpoint` to `context.yaml` noting which task just completed and what comes next. Example: `"Completed tasks 1-3 of 7. Next: Task 4 - Add useAuthToken hook."` Preserve all other fields.

## After all tasks complete

Once the implement skill signals all tasks are done, perform a final end-of-step sync before returning.

1. Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Validate) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Implement accomplished (what was built, how many tasks landed, the high-level shape of the diff), (2) key findings and decisions made during implementation (deviations from the plan, surprises, anything resolved on the fly), (3) relevant context for the Validate phase — known weak spots, areas of the diff that warrant extra senior-review attention, test-coverage gaps, anything that isn't self-evident from the diff itself.

2. Check whether `context.yaml` has uncommitted changes (the last `workflow.checkpoint` update may not yet be in a commit):

   ```bash
   git status --porcelain <feature.folder>/context.yaml
   ```

   If the output is non-empty, commit `context.yaml`. Invoke `Skill(git-commit)` first, then stage and commit only that file:

   ```bash
   git add <feature.folder>/context.yaml
   git commit -m "chore(context): update workflow checkpoint"
   ```

   If the output is empty, skip the commit — there is nothing to add. Do not produce an empty commit.

3. Push the branch with `git push`. Run this unconditionally (whether or not step 2 produced a commit) so any per-task commits from the implement skill are flushed to the remote. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return.

## Push-failure escalation

If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

```yaml
# Merge into existing workflow block — do not replace other fields
workflow:
  escalated: true
  escalation_reason: |
    git push failed during the Implement step.
    [Exit code and the exact stderr from the failed push]
    [Assessment: e.g. branch out of date with remote, missing credentials, network error]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.

## If the skill cannot complete

If the implement skill signals it cannot resolve an issue after 3 attempts, write the escalation to `context.yaml` and return:

```yaml
# Merge into existing workflow block — do not replace other fields
workflow:
  escalated: true
  escalation_reason: |
    [What is failing and the exact error]
    [What was attempted in each of the 3 attempts and why it didn't work]
    [Assessment of why this is stuck]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
