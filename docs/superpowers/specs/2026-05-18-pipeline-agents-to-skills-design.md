# Design: Pipeline Agents to Skills Refactor

**Date:** 2026-05-18

## Problem

Pipeline step agents (Define, Research, Plan, Implement, Validate) are structured as full agents with both execution configuration (frontmatter) and workflow methodology (body) in the same file. This conflates two distinct concerns:

- **Who executes the step** — model, MCP servers, pre-loaded skills
- **How the step works** — gate logic, methodology, output specification

As a result, the workflow knowledge is locked inside agent files and can't be used outside the automated pipeline. A user who wants to run just the research or implement workflow interactively has no direct path to do so.

## Goal

Separate methodology from execution configuration. Move all workflow knowledge into skills so each pipeline step can be used standalone (`/define`, `/implement`, `/validate`) or automated via `/feature` — same logic, two execution modes.

## Non-goals

- Changing the pipeline dispatch mechanism (feature skill still dispatches agents)
- Converting reviewer agents (Senior Reviewer, QA Reviewer, Code Reviewer) — these are expert personas, not workflow steps
- Converting Document or Onboard agents — Document stays full per preference; Onboard is a standalone persona
- Any changes to context.yaml structure or the feature orchestrator logic

## Architecture

Every pipeline step has two files with distinct jobs:

**The skill** (`.claude/skills/<step>/SKILL.md`) is the source of truth. It contains:
- Gate logic (branch check, prerequisite file checks) — so standalone invocations self-validate
- Full step methodology
- Output specification

`disable-model-invocation: true` is set so standalone invocations (`/implement`) run inline in the current conversation.

**The agent** (`.claude/agents/<step>.md`) is the execution vessel. It contains:
- Frontmatter only: `name`, `description`, `model`, `skills`, `mcpServers` — preserved exactly from today
- Body: one line — `Read and follow .claude/skills/<step>/SKILL.md`

The feature orchestrator dispatches agents for context isolation and per-step model/MCP configuration. The agent immediately delegates to the skill. Result: same content, two execution modes.

## File map

### New files

| File | What moves here |
|------|----------------|
| `.claude/skills/define/SKILL.md` | Full Define methodology from `agents/define.md` body, plus gate logic |
| `.claude/skills/implement/SKILL.md` | Full Implement methodology from `agents/implement.md` body, plus gate logic |
| `.claude/skills/validate/SKILL.md` | Full Validate methodology from `agents/validate.md` body, plus gate logic |

### Updated files

| File | Change |
|------|--------|
| `.claude/agents/define.md` | Strip body to one line; preserve frontmatter exactly |
| `.claude/agents/research.md` | Strip body to one line; preserve frontmatter exactly |
| `.claude/agents/plan.md` | Strip body to one line; preserve frontmatter exactly |
| `.claude/agents/implement.md` | Strip body to one line; remove `shadcn` from skills list and mcpServers; preserve rest of frontmatter |
| `.claude/agents/validate.md` | Strip body to one line; preserve frontmatter exactly |
| `.claude/skills/research/SKILL.md` | Add gate logic section (branch check + spec approval check) currently only in agent |
| `.claude/skills/plan/SKILL.md` | Add gate logic section (branch check + prerequisite file checks) currently only in agent |
| `README.md` | Restructure skills/agents reference into three sections (see below) |

### Unchanged files

| File | Reason |
|------|--------|
| `.claude/agents/document.md` | Full agent by preference; persona elements |
| `.claude/agents/code-reviewer.md` | Reviewer persona |
| `.claude/agents/senior-reviewer.md` | Reviewer persona |
| `.claude/agents/qa-reviewer.md` | Reviewer persona |
| `.claude/agents/onboard.md` | Standalone persona tool |
| `.claude/skills/feature/SKILL.md` | Dispatch mechanism unchanged |
| All other skill files | No changes needed |

## Thin agent wrapper pattern

```markdown
---
name: implement
description: Implement step agent. Follows the plan document to build the feature
  incrementally with TDD. Only runs if 3_plan.md exists for the feature.
  Use after the Plan step is complete.
model: sonnet
skills:
  - agent-context
  - ui-design-brain
  - find-patterns
  - git-commit
mcpServers:
  - github
---

Read and follow `.claude/skills/implement/SKILL.md`.
```

All five pipeline agent files follow this exact pattern. Frontmatter is preserved from today's agent files (minus `shadcn` from implement). Body is always one line.

## Standalone skill pattern

Skills gain a gate section at the top that runs whether invoked standalone or via the agent. Gate logic currently living only in agents moves here — no duplication, since agents delegate entirely to the skill.

```markdown
---
name: implement
description: Execute a feature's implementation plan with TDD. Task by task,
  test first, with frequent commits and code review checkpoints.
argument-hint: "[feature folder path]"
disable-model-invocation: true
allowed-tools: Read Edit Write Bash(*) Agent
---

# Implement

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed
as your argument...
[branch verification, 3_plan.md existence check]

## Pre-Implementation Setup
...

## Implementation Loop
...
```

Gate logic is identical to what today's agents check before invoking their skills.

## README restructuring

Replace the current flat "Agents vs skills" table with three labelled sections.

### Pipeline skills

Skills for the `Define → Research → Plan → Implement → Validate` sequence. Run automatically via `/feature`, or invoke any step directly for standalone use.

| Step | Skill | What it does |
|------|-------|--------------|
| Define | `/define` | Collaborative spec conversation, branch setup, draft PR |
| Research | `/research` | Codebase analysis against the approved spec, writes `2_research.md` |
| Plan | `/plan` | File map and TDD task list, writes `3_plan.md` |
| Implement | `/implement` | Executes the plan task-by-task with TDD and code review checkpoints |
| Validate | `/validate` | Senior code review then QA review, writes `4_validate.md` |

### Reviewer agents

Expert personas invoked during the pipeline. Can also be invoked directly for a focused review session.

| Agent | What it does |
|-------|--------------|
| `code-reviewer` | Mid-implementation plan alignment and quality checks |
| `senior-reviewer` | Brutal final code review against spec, plan, and engineering standards |
| `qa-reviewer` | Coverage audit, test quality, e2e gaps, and evidence capture |

### Utility skills

Used by the pipeline internally. Also available for direct invocation outside a full pipeline run.

| Skill | What it does |
|-------|--------------|
| `/analyze-code` | Survey a file or module — structure, dependencies, behavior |
| `/find-patterns` | Identify conventions, naming patterns, and architectural decisions |
| `/web-search` | Look up versioned third-party docs and external APIs |
| `/verify-completeness` | Check spec requirements are present in the implementation |
| `/verify-correctness` | Check logic, error handling, edge cases, and test quality |
| `/verify-coherence` | Check design consistency and pattern conformance across files |
| `/security-review` | Security audit — auth, input validation, injection vectors, secrets |
| `/ui-design-brain` | UI design planning and component patterns |

The Document agent and Onboard agent retain their own sections in the README as standalone tools outside the pipeline.

## Acceptance criteria

- `/define`, `/research`, `/plan`, `/implement`, `/validate` can each be invoked directly and run their full workflow without the feature orchestrator
- Running `/feature` still dispatches each step as an isolated sub-agent with the correct model and MCP configuration
- Gate logic is present in each skill (not only in agent files)
- No pipeline step agent body exceeds two lines
- `shadcn` is removed from the implement agent frontmatter and from all skill references
- README documents pipeline skills, reviewer agents, and utility skills in separate labelled sections
- Document, Code Reviewer, Senior Reviewer, QA Reviewer, and Onboard agents are unchanged
