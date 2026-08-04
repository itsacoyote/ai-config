---
name: find-patterns
description: Use during research, or before implementing, to identify the conventions, patterns, and architectural decisions in the codebase, so new work stays consistent with how things are already built.
argument-hint: "[area, pattern type, or feature domain]"
allowed-tools: Read Bash(find *) Bash(grep *)
---

# Find Patterns

Identify the conventions and patterns in `$ARGUMENTS` — or across the whole codebase if no target is given.

## What to look for

**Structural patterns** — how are features and modules organized? Is there a consistent folder structure? How are related files grouped (by type, by feature, by domain)?

**Naming conventions** — how are files, functions, variables, components, and API routes named? Are there prefixes, suffixes, or casing conventions? Look for inconsistencies too — they're worth flagging.

**Component and UI patterns** — how are UI components structured? What props patterns are common? How is state managed locally vs. globally? How are forms, lists, modals, and other common patterns implemented?

**API and data patterns** — how are endpoints structured and named? How are requests made from the frontend? How is error handling done at the API boundary? How are responses shaped?

**State and data flow patterns** — where does state live? How does it move between layers? What patterns are used for async operations, loading states, and errors?

**Testing patterns** — how are tests structured? What gets unit tested vs. integration tested? How are mocks and fixtures organized?

**Error handling patterns** — how are errors caught, logged, and surfaced to users? Are there consistent wrappers or utilities?

## What to report

- Pattern name and a clear description of what it is
- Where it's used (specific files or directories as examples)
- Why it matters for the feature under research — will the implementation need to follow this pattern?
- Any inconsistencies found that the implementer should be aware of
