# Design: Pipeline Agents to Skills Refactor

**Date:** 2026-05-18

## Problem

Pipeline step agents (Define, Research, Plan, Implement, Validate) bundle two distinct concerns into one file:

- **Pipeline infrastructure** — gate checks, context.yaml management, feature folder file I/O, branch verification
- **Workflow methodology** — how to have the spec conversation, how to analyze a codebase, how to implement with TDD

The methodology is locked inside agent files and can only run in the context of the automated pipeline. A user who wants to use the research or implement workflow interactively in a conversation has no path to do so.

## Goal

Split every pipeline step into two layers: an **agent** that owns all pipeline infrastructure, and a **skill** that owns the pure workflow methodology. Skills work conversationally — no context.yaml, no feature folder, no gate checks. Agents manage all of that before and after invoking the skill.

The result: each pipeline step is usable standalone (`/define`, `/implement`, `/validate`) in any conversation, and still runs fully automated via `/feature` with the same methodology.

## Non-goals

- Changing the pipeline dispatch mechanism (feature skill still dispatches agents)
- Converting reviewer agents (Senior Reviewer, QA Reviewer, Code Reviewer) — these are expert personas, not workflow steps
- Converting Document or Onboard agents — Document stays full by preference; Onboard is a standalone persona tool
- Any changes to context.yaml structure or the feature orchestrator logic

## Architecture

### The two layers

**The agent** (`.claude/agents/<step>.md`) owns all pipeline coupling:

- Gate checks (branch verification, context.yaml existence, prerequisite file checks)
- Loading inputs from the feature folder into the conversation context (spec, research, plan)
- Invoking the skill — by this point, all relevant context is already in the conversation
- Post-skill file writes (writing `2_research.md`, `3_plan.md`, etc. to the feature folder)
- context.yaml updates (checkpoints, escalation, artifacts list)

Agents remain substantial files. They slim down relative to today because methodology moves out, but gate + context loading + post-skill handling is real work.

**The skill** (`.claude/skills/<step>/SKILL.md`) owns the methodology only:

- How to conduct the workflow (questions to ask, analysis approach, implementation loop, etc.)
- Quality criteria for the output
- No references to context.yaml, feature folders, or pipeline state
- No file writes to the feature folder (application code edits in Implement are fine)
- Works conversationally — if inputs aren't in context, ask the user for them

`disable-model-invocation: true` means standalone skill invocations run inline in the current conversation. Pipeline invocations go through the agent, which creates an isolated context, pre-loads all inputs, then runs the skill.

### How pipeline invocation works

1. Feature orchestrator dispatches the agent (isolated context, correct model, MCP servers)
2. Agent runs gate checks and halts if prerequisites aren't met
3. Agent reads feature folder inputs (spec, research, plan) into the conversation context
4. Agent invokes the skill — the skill runs with all inputs already available in context
5. Agent handles post-skill work: writes output files, updates context.yaml

### How standalone invocation works

1. User runs `/define`, `/research`, etc.
2. Skill runs inline in the current conversation
3. Skill asks for whatever inputs it needs (spec, plan, etc.) if not already in context
4. Output stays in the conversation — user asks to save to a file if they want

## File map

### New files

| File | Contents |
|------|----------|
| `.claude/skills/define/SKILL.md` | Collaborative spec conversation methodology — questions, approaches, design review. No git ops, no file writes. |
| `.claude/skills/implement/SKILL.md` | TDD implementation methodology — pre-setup, task loop, code review criteria, coverage requirements, escalation criteria. No context.yaml writes. |
| `.claude/skills/validate/SKILL.md` | Validation methodology — when and how to invoke senior review and QA review, how to coordinate fix iterations. No context.yaml writes. |

### Updated files — skills

| File | Change |
|------|--------|
| `.claude/skills/research/SKILL.md` | Remove file writing section (`Write 2_research.md`) and argument-hint. Skill presents research findings conversationally. Methodology content unchanged. |
| `.claude/skills/plan/SKILL.md` | Remove file writing section (`Write 3_plan.md`) and argument-hint. Skill presents the plan conversationally. Methodology content unchanged. Also remove the `recommended_skills` context.yaml update step — agent handles that. |

### Updated files — agents

| File | Change |
|------|--------|
| `.claude/agents/define.md` | Replace methodology body with: gate check (context.yaml exists, correct branch) + invoke define skill + post-skill (write `1_spec.md`, create draft PR). |
| `.claude/agents/research.md` | Replace methodology body with: gate check + load `1_spec.md` into context + invoke research skill + write `2_research.md` + update context.yaml artifacts. |
| `.claude/agents/plan.md` | Replace methodology body with: gate check + load spec and research into context + invoke plan skill + write `3_plan.md` + update context.yaml `recommended_skills`. |
| `.claude/agents/implement.md` | Replace methodology body with: gate check + load spec, plan, artifacts into context + invoke implement skill + write context.yaml checkpoint. Remove `shadcn` from frontmatter skills and mcpServers. |
| `.claude/agents/validate.md` | Replace methodology body with: gate check + load context + invoke validate skill + write `4_validate.md` + write context.yaml escalation if needed. |

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

## Agent pattern

Agents handle infrastructure before and after the skill. Example structure for the implement agent:

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

# Implement Agent

## Gate
[branch verification, context.yaml check, 3_plan.md existence check — halt if any fail]

## Context
Read `1_spec.md`, `3_plan.md`, and any artifacts listed in `context.yaml` into context.
Load `recommended_skills` from `context.yaml`.

## Workflow
Read and follow `.claude/skills/implement/SKILL.md`.

## After the skill completes
Update `workflow.checkpoint` in `context.yaml`.
Write escalation fields to `context.yaml` if the skill could not complete.
```

The frontmatter is preserved from today (minus `shadcn` for implement). The body is restructured, not stripped to one line.

## Skill pattern

Skills are pure methodology — no gate checks, no context.yaml, no feature folder references. They ask for what they need if it isn't already in context.

```markdown
---
name: implement
description: Guide a TDD implementation from a plan document. Task by task,
  test first, with code review checkpoints.
disable-model-invocation: true
allowed-tools: Read Edit Write Bash(*) Agent
---

# Implement

Work through the implementation plan task by task. If no plan is in context,
ask the user to share one.

## Pre-Implementation Setup
[read plan files, run test suite baseline, note recommended skills]

## Implementation Loop
[TDD loop — write tests, implement, pass tests, lint, coverage, commit]

## Code Review
[criteria for when to invoke the code reviewer agent]

## Coverage Requirements
[>80% across unit, integration, e2e]

## Escalation
[how to handle repeated failures — describe what happened and return]
```

No references to `context.yaml`, `feature_folder`, branch names, or `.docs/` paths.

## README restructuring

Replace the current flat "Agents vs skills" table with three labelled sections.

### Pipeline skills

Skills for the `Define → Research → Plan → Implement → Validate` sequence. Run automatically via `/feature`, or invoke any step directly for a conversational session.

| Step | Skill | What it does |
|------|-------|--------------|
| Define | `/define` | Collaborative spec conversation — questions, approaches, acceptance criteria |
| Research | `/research` | Codebase analysis for a feature — reuse, gaps, patterns, constraints |
| Plan | `/plan` | File map and TDD task list for a feature |
| Implement | `/implement` | TDD implementation guidance — task loop, code review, coverage |
| Validate | `/validate` | Senior code review then QA review coordination |

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

- `/define`, `/research`, `/plan`, `/implement`, `/validate` each work conversationally without any feature folder or pipeline context
- Skills contain no references to `context.yaml`, feature folder paths, branch names, or `.docs/` structure
- Skills contain no file writes to the feature folder (application code edits in Implement are fine)
- Agents handle all gate checks, context loading, output file writes, and context.yaml updates
- Running `/feature` still dispatches each step as an isolated sub-agent with correct model and MCP configuration
- `shadcn` is removed from the implement agent frontmatter and from all skill references
- README documents pipeline skills, reviewer agents, and utility skills in separate labelled sections
- Document, Code Reviewer, Senior Reviewer, QA Reviewer, and Onboard agents are unchanged
