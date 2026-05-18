---
name: define
description: Guide a collaborative spec conversation for a new feature. Works through scope, goals, constraints, and acceptance criteria to arrive at a clear, well-scoped design before anything gets built.
disable-model-invocation: true
allowed-tools: Read Bash(find *) Bash(git log *)
---

# Define

Help arrive at a clear, well-scoped feature spec through collaborative dialogue. If spec context is already in the conversation, build on it. If not, start from scratch with the user.

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every feature goes through this process. The conversation can be short for simple features, but you must go through it. A brief conversation is better than skipping and discovering missed requirements mid-implementation.

## The Process

**Explore context first:**

- Check files, docs, and recent commits to understand the current project state
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately and help decompose into sub-projects before continuing
- If the project is too large for a single spec, help the user identify the independent pieces, how they relate, and what order to build them. Then work through the first sub-project

**Ask clarifying questions — one at a time:**

- Prefer multiple choice when possible, open-ended when necessary
- One question per message — if a topic needs more exploration, break it into multiple messages
- Focus on: purpose, constraints, success criteria, non-goals

**Explore approaches:**

- Propose 2-3 different approaches with trade-offs
- Lead with your recommended option and explain why

**Present the design:**

- Once you understand what's being built, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200–300 words if nuanced
- Ask after each section whether it looks right
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, answer: what does it do, how do you use it, what does it depend on?
- Can someone understand a unit without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work, include targeted improvements as part of the design
- Don't propose unrelated refactoring

## Key Principles

- **One question at a time** — don't overwhelm with multiple questions
- **Multiple choice preferred** — easier to answer than open-ended when possible
- **YAGNI ruthlessly** — cut unnecessary features from all designs
- **Explore alternatives** — always propose 2-3 approaches before settling
- **Incremental validation** — present design section by section, get approval before moving on
- **Be flexible** — go back and clarify when something doesn't make sense
