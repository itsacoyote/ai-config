---
name: feature
description: Entry point for the development workflow. Start a new feature or resume an in-progress one.
argument-hint: "[feature idea or description]"
disable-model-invocation: true
---

# Feature

Start a new feature workflow or resume an in-progress one.

## Step 1: Check for in-progress workflows

Run:

```bash
find .docs -name "context.yaml" 2>/dev/null | sort
```

For each `context.yaml` found, read it and check `workflow.current_step`. A workflow is in-progress if `workflow.current_step` is not `complete`.

## Step 2: If in-progress workflows exist

List each one for the user with:
- Feature name (`feature.name`)
- Current step (`workflow.current_step`)
- Checkpoint if set (`workflow.checkpoint`)

Ask: "Do you want to resume one of these, or start a new feature?"

**To resume:** Read the `context.yaml`, determine `workflow.current_step`, then invoke the agent for that step with `feature.folder` as the argument:

| Step | Agent to invoke |
|------|----------------|
| `research` | Research agent |
| `plan` | Plan agent |
| `implement` | Implement agent |
| `validate` | Validate agent |
| `document` | Document agent |

**To start new:** Continue to Step 3.

## Step 3: Start a new feature

If a feature idea was passed as `$ARGUMENTS`, use it as the starting context for the Define agent. Otherwise ask the user what they want to build first.

Invoke the Define agent with the feature idea.
