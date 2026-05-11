---
name: agent-context
description: Documents the context-passing protocol used between workflow agents. Each agent reads context.yaml from the feature folder, does its work, updates the file, and passes the folder path to the next agent.
disable-model-invocation: true
---

# Agent Context Protocol

Every feature workflow has a `context.yaml` file that lives in the feature folder. This file is the shared state passed between agents. It is created by the `/spec` skill when the feature folder is initialized, and read and updated by every subsequent agent before handing off.

## File location

```text
.docs/YYYY-MM-DD-<short-name>/context.yaml
```

## Agent responsibilities

**On start:** Read `context.yaml` from the feature folder to load full context. Use `feature.folder` to locate all other docs (`1_spec.md`, `2_research.md`, etc.).

**On handoff:** Before invoking the next agent:

1. Update `workflow.current_step` to the next step name.
2. Append the completed step to `workflow.completed_steps`.
3. Clear `workflow.checkpoint` (set to `""`).
4. Write the updated `context.yaml` back to the feature folder.
5. Pass `feature.folder` as the argument to the next agent.

**During long steps:** For steps with multiple sub-tasks (Implement in particular), write a brief `workflow.checkpoint` after each committed sub-task so a disruption mid-step leaves a clear resume point. Example: `"Completed tasks 1-3 of 7. Next: Task 4 - Add useAuthToken hook."` For Implement specifically, `git log` is also a reliable record of completed tasks since each task ends with a commit.

## Resuming a disrupted workflow

If a workflow was interrupted, read `context.yaml` to orient:

1. **`workflow.current_step`** — the step that was active when disruption occurred. Resume here.
2. **`workflow.completed_steps`** — all prior steps finished cleanly. No need to re-run them.
3. **`workflow.checkpoint`** — if set, this is where the disrupted step left off. Start from here rather than the beginning of the step.

To resume, invoke the agent that owns `current_step` with `feature.folder` as the argument. The agent's gate will validate prerequisite docs are present and the agent will pick up from `checkpoint` if set.

**Step-specific resume notes:**

- **Implement** — if `checkpoint` is empty, check `git log` to see which plan tasks have committed. Start from the first uncommitted task.
- **Validate** — if `checkpoint` indicates senior review already passed, skip directly to the QA Reviewer.
- **All other steps** — restart the step from the beginning. Research, Plan, and Document are idempotent — re-running overwrites with a fresh result.

## Artifacts registry

The `artifacts` list in `context.yaml` is the shared registry of reference files created in the feature's `artifacts/` folder (primarily by Research). Any step that creates an artifact must append an entry before its handoff:

```yaml
- path: artifacts/filename.ext   # relative to feature.folder
  description: what it is and why it was created
  created_by: research           # which step produced it
```

Downstream agents (Plan, Implement, Validate) should check this list at the start of their step so they know what reference material is available without having to scan the directory manually.

## Output artifacts registry

The `output_artifacts` list is the registry of screenshots and recordings captured during QA as evidence that the feature works. These are saved to `output-artifacts/` and populated by the QA Reviewer during Validate. The Document agent reads this list to embed visual evidence in the PR description.

```yaml
- path: output-artifacts/filename.ext
  description: what the screenshot or recording shows
  user_story: the spec user story it demonstrates
  created_by: qa-review
```

## Documentation created registry

The `documentation_created` list is the registry of **new** documentation files created by the Document agent. Updates to existing files (README, CLAUDE.md, API docs) are not listed here — only newly created files whose paths wouldn't be predictable to a future agent or engineer.

```yaml
- path: docs/features/feature-name.md
  description: what the documentation covers
  created_by: document
```

## Template

See [template.yaml](template.yaml) for the full structure.

To add new fields in the future, extend the template and update this document. All agents will automatically have access to the new fields via `context.yaml`.
