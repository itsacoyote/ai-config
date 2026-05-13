---
name: spec
description: Interactively define a new feature and write its spec document to .docs/. Use when the user wants to spec a feature, define requirements, brainstorm an idea, or start the Define step of the development workflow.
argument-hint: "[feature idea]"
allowed-tools: Write Read
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

Once you have enough to write a solid draft:

1. **Write `1_spec.md`** using the template in [template.md](template.md). Write it into the feature folder passed as your argument — the branch, folder, and `context.yaml` were created before you were invoked.
2. Tell the user the file path and invite revisions.

Stay in the conversation after writing — iterate on the doc until the user is satisfied.
