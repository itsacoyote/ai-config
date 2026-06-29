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

If you produce any reference files (diagrams, data samples, exported schemas, etc.) during research, note them clearly in your findings so the user can save them if needed.

## Supporting skills

Use these skills as needed during research:

- `/analyze-code [path]` — deep-dive into a specific file, module, or directory to understand its structure, dependencies, and behavior
- `/find-patterns [area]` — identify conventions, naming patterns, and architectural decisions across the codebase
- `/web-search [topic]` — look up documentation for third-party libraries, external APIs, or tools where the codebase alone isn't enough

## Output

**Preflight (required).** Before doing any workflow work, verify beads is set up:
`sh .claude/references/beads-preflight.sh`. If it exits non-zero, **stop** — do not
proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

Present findings **conversationally in this session**, using [template.md](template.md) as the structure for what to cover (a findings outline — not a file to write). Don't write step-doc files.

Attach findings to the feature epic and turn each actionable gap into a child issue with dependencies — beads is the system of record. See [`.claude/references/beads.md`](../../references/beads.md) for the full model.

Next step: hand the findings to `planning-and-task-breakdown` (Plan). See `feature-workflow` for the full sequence.
