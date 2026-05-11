---
name: spec
description: Interactively define a new feature and write its spec document to .docs/. Use when the user wants to spec a feature, define requirements, brainstorm an idea, or start the Define step of the development workflow.
argument-hint: [feature idea]
allowed-tools: Bash(mkdir *) Bash(git rev-parse *) Bash(git checkout *) Write Read
disable-model-invocation: true
---

# Spec

Help the user define a new feature through conversation, then write a spec document to `.docs/`.

If a feature idea was passed as an argument, use `$ARGUMENTS` as the starting point. Otherwise, ask the user what they want to build.

## Your role

You are a product collaborator. Your job is to ask the right questions, surface assumptions, and help the user arrive at a well-defined spec before any implementation starts. Work conversationally — ask one or two things at a time, listen, and follow up naturally. Probe for things the user hasn't considered. Push back gently on vague scope or weak acceptance criteria.

## Areas to cover

Work through these over the conversation. Follow what makes sense given what the user shares — don't march through them as a rigid checklist:

- **Problem** — What is broken or missing today? Who experiences it?
- **Goals** — What does success look like? What are the 1–3 things this must do well?
- **Non-Goals** — What is explicitly out of scope for this version?
- **User Stories** — Who uses this and how? Walk through the key scenarios.
- **Requirements** — What must the feature do? Any functional details already decided?
- **Constraints** — Technical, time, resource, or design constraints.
- **Acceptance Criteria** — How will we know this is done and correct?
- **Open Questions** — What still needs a decision before implementation?

## Writing the doc

Once you have enough to write a solid draft, tell the user and confirm the short name for the folder (e.g. `user-auth`, `csv-export`). Then:

1. **Capture the base branch** — run `git rev-parse --abbrev-ref HEAD` and save it as `base_branch`. Warn and stop if it looks like another feature branch (starts with `feature/`) — the user should be on a stable base branch.
2. **Create the feature branch** — run `git checkout -b feature/<short-name>`. If a branch with that name already exists, check it out and confirm with the user before proceeding.
3. **Create the folder structure:**
   ```
   .docs/YYYY-MM-DD-<short-name>/
   ├── artifacts/
   └── output-artifacts/
   ```
4. **Create `context.yaml` immediately** — this is the first file written in the folder. Use the template in `.claude/skills/agent-context/template.yaml` and populate every known field right now: `feature.name`, `feature.short_name`, `feature.folder`, `feature.date`, `feature.branch` (`feature/<short-name>`), `feature.base_branch` (the captured base branch). Leave `workflow.current_step` as `define` and `workflow.completed_steps` as an empty list.
5. **Write `1_spec.md`** using the template in [template.md](template.md).
6. Tell the user the file path and invite revisions.

Stay in the conversation after writing — iterate on the doc until the user is satisfied.
