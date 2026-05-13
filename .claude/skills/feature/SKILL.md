---
name: feature
description: Entry point for the development workflow. Orchestrates the full pipeline from Define through Document. Start a new feature or resume an in-progress one.
argument-hint: "[feature idea or description]"
disable-model-invocation: true
---

# Feature Workflow

Orchestrates the full development pipeline: Define → Research → Plan → Implement → Validate → Document.

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

**To resume:** Read the `context.yaml`, set `feature_folder` to its `feature.folder` value. Check `workflow.escalated` — if `true`, tell the user the previous run escalated and show `workflow.escalation_reason`. Reset `workflow.escalated` to `false` and `workflow.escalation_reason` to `""` in `context.yaml` before re-invoking the step. Then look up the agent for `workflow.current_step` in the **Step sequence** agent invocation table in the Pipeline section and invoke it (with `feature_folder` as argument), then continue the pipeline from there. If `workflow.current_step` is `define`, jump to the **Approval Gate** instead. If `workflow.current_step` is `complete`, announce the workflow is already complete and stop.

**To start new:** Continue to Step 3.

## Step 3: Start a new feature

If a feature idea was passed as `$ARGUMENTS`, use it as the starting context for the Define agent. Otherwise ask the user what they want to build first.

Announce: `"Starting Define..."`

Invoke the Define agent with the feature idea. After it returns, scan for context.yaml files again with the same `find` command. Read the one where `workflow.current_step` is `define` and `workflow.completed_steps` is empty — this is the one Define just created. Set `feature_folder` to its `feature.folder` value.

Then proceed to the **Approval Gate** below.

## Pipeline

### Post-return protocol

Run this after every agent returns:

1. Read `context.yaml` from `feature_folder`.
2. If `workflow.escalated` is `true`: halt immediately. Tell the user: `"Pipeline halted — " + workflow.escalation_reason`. Do not update `context.yaml`. Do not invoke the next agent. Stop.
3. Append the completed step name to `workflow.completed_steps` (initialize to `[]` if the key is absent).
4. Set `workflow.current_step` to the next step name (see sequence table below).
5. Write the updated `context.yaml`.

### Approval Gate (after Define)

Before advancing to Research:

1. Read `1_spec.md` from `feature_folder`.
2. Present the **Summary** and **Acceptance Criteria** sections to the user.
3. Ask: "Does this spec look right? Approve to continue to Research, or provide feedback to revise."
4. **Approved:** run the post-return protocol (completed: `define`, next: `research`), then announce `"Spec approved. Starting Research..."` and invoke the Research agent.
5. **Feedback given:** re-invoke the Define agent with `feature_folder` as the argument and the user's feedback noted in context. Repeat the gate after Define returns (skip the post-return protocol on the revision pass — only run it on approval).

### Step sequence

| Completed step | Next step |
|---|---|
| define | research |
| research | plan |
| plan | implement |
| implement | validate |
| validate | document |
| document | complete |

After the Approval Gate, invoke each remaining agent in order. Before each invocation announce `"Starting [Step]..."`. After each returns, run the post-return protocol, announce `"[Step] complete."`, then continue.

| Step | Agent to invoke |
|---|---|
| research | Research agent |
| plan | Plan agent |
| implement | Implement agent |
| validate | Validate agent |
| document | Document agent |

Pass `feature_folder` as the argument to every agent.

### Completion

After the Document agent returns and the post-return protocol runs without escalation:

1. Read `feature.branch` from `context.yaml`.
2. Run: `gh pr view <feature.branch> --json url -q .url`
3. Announce: `"Workflow complete. PR is ready for review: [PR URL]"`
