---
name: research
description: Analyze the codebase for an approved feature and produce a 2_research.md document in the feature's .docs/ folder. Use when starting the Research step of the development workflow.
argument-hint: [feature folder path]
allowed-tools: Read Bash(find *) Bash(grep *) Bash(git log *) Bash(git show *) Bash(git blame *) Write
disable-model-invocation: true
---

# Research

Analyze the codebase for the approved feature and write `2_research.md` to the feature's folder.

If a feature folder path was passed as an argument, use `$ARGUMENTS`. Otherwise, ask the user which feature folder to work in.

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

**Patterns and conventions** — document what the codebase already does so the Planner can stay consistent:

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

If you produce any artifacts during research (diagrams, data samples, reference files, exported schemas, etc.):

1. Place them in the feature's `artifacts/` folder.
2. Reference each one in `2_research.md`.
3. Append an entry for each to the `artifacts` list in `context.yaml` with its path relative to the feature folder, a description, and `created_by: research`. This makes them discoverable by all downstream agents without scanning the directory.

## Supporting skills

Use these skills as needed during research:

- `/analyze-code [path]` — deep-dive into a specific file, module, or directory to understand its structure, dependencies, and behavior
- `/find-patterns [area]` — identify conventions, naming patterns, and architectural decisions across the codebase
- `/web-search [topic]` — look up documentation for third-party libraries, external APIs, or tools where the codebase alone isn't enough

## Output

Write `2_research.md` in the feature's folder using the template in [template.md](template.md).
