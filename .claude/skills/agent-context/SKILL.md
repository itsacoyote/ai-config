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
3. Write the updated `context.yaml` back to the feature folder.
4. Pass `feature.folder` as the argument to the next agent.

## Template

See [template.yaml](template.yaml) for the full structure.

To add new fields in the future, extend the template and update this document. All agents will automatically have access to the new fields via `context.yaml`.
