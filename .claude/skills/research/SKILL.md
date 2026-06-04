---
name: research
description: Analyze the codebase for a feature and present research findings conversationally — reusable code, gaps, patterns, and architectural context. Works standalone or as a pipeline step.
allowed-tools: Read Bash(find *) Bash(grep *) Bash(git log *) Bash(git show *) Bash(git blame *)
disable-model-invocation: true
---

# Research

Analyze the codebase for a feature and present research findings.

If a spec is already in context, use it. Otherwise, ask the user to share their feature spec or describe what they want to research.

## Research Methodology

Work systematically. Read the spec carefully to understand what the feature does, who uses it, and what it requires. Then explore the codebase with those requirements in mind.

**Facts first.** Document what you observe in the code. Add inferences or opinions only when they provide useful context, and label them clearly.

### What to look for

**Reusable code** — look for existing work that can be used or extended rather than built from scratch:

- API endpoints that could serve this feature as-is or with minor modification
- UI components that match the feature's needs
- Utilities, helpers, hooks, or services with relevant functionality
- Data models or schemas that already represent needed concepts

**Gaps** — what doesn't exist yet and will need to be created:

- New endpoints, if no existing one can be adapted
- New UI components, if nothing reusable fits
- New data structures or migrations

**Patterns and conventions** — document what the codebase already does so new work stays consistent:

- How similar features are structured
- Naming conventions in relevant areas
- Error handling patterns
- State management approach
- Testing conventions for affected code

**Architectural context** — anything about how the system is designed that constrains or informs how this feature should be built:

- Integration points between layers (frontend ↔ backend ↔ data)
- Authentication or authorization patterns that apply
- Performance or scaling considerations that are relevant

## Artifacts

If you produce any reference files (diagrams, data samples, exported schemas, etc.) during research, note them clearly in your findings so the user or a downstream agent can save them if needed.

## Supporting skills

Use these skills as needed during research:

- `/analyze-code [path]` — deep-dive into a specific file, module, or directory to understand its structure, dependencies, and behavior
- `/find-patterns [area]` — identify conventions, naming patterns, and architectural decisions across the codebase
- `/web-search [topic]` — look up documentation for third-party libraries, external APIs, or tools where the codebase alone isn't enough

## Output

Default: present findings **conversationally in this session**, using [template.md](template.md) as the structure for what to cover. Don't write files unless the user asks.

### Task tracking

<!-- BEADS: not enabled yet. When beads is set up in the project, turn this section on. -->

The intended task tracker is **beads** (the `bd` CLI). It is **not set up in this project yet** — so for now, present the "Gaps / what needs to be created" as a plain checklist in your findings and let the user decide what to track. Do not run `bd` until `.beads/` exists in the repo.

When beads is available, switch to issue output: turn each actionable gap into an issue, express ordering between them with dependencies, then hand off via `bd ready`.

```bash
bd create "<gap title>" -p <priority>   # one issue per actionable gap
bd dep add <child-id> <parent-id>       # blocking/ordering between gaps
bd ready                                # what's unblocked and ready to start
```
