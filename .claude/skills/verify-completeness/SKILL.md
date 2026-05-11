---
name: verify-completeness
description: Verify that the implementation covers everything required by the spec and plan. Checks acceptance criteria, user stories, and the plan's file map against the actual diff.
allowed-tools: Read Bash(git diff *) Bash(git log *) Bash(find *) Bash(grep *)
user-invocable: false
---

# Verify Completeness

Check that the implementation built everything the spec required and the plan specified.

## Current diff

```!
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'); git diff $(git merge-base HEAD ${BASE:-main}) HEAD
```

## What to check

**Acceptance criteria** — read every acceptance criterion in `1_spec.md`. For each one, find the code in the diff that satisfies it. If a criterion has no corresponding implementation, flag it as a gap.

**User stories** — read every user story in `1_spec.md`. Each story describes a user-facing behavior. Confirm the diff contains the code that enables it.

**Plan file map** — read the New Files and Modified Files tables in `3_plan.md`. Confirm every new file was created and every modified file was changed. Flag any file in the map that doesn't appear in the diff.

**Plan tasks** — scan the task list in `3_plan.md`. Confirm each task's implementation steps are reflected in the diff. Flag any task with no corresponding changes.

**Out of scope** — check the "Out of Scope" section of `3_plan.md`. Flag anything in the diff that matches items explicitly excluded.

## Output

List every gap found:

- **Gap:** what was specified but not implemented, with the exact spec or plan reference
- **Missing:** what needs to be added

If nothing is missing, state: "Completeness verified — all spec requirements and plan items are present in the diff."
