# Design: Plan Skill — Recommended Skills for Implement

**Date:** 2026-05-18

## Problem

The Implement agent has a fixed set of skills loaded via frontmatter. There is no mechanism for the Plan agent — which has read the spec and research and understands the feature's domain — to surface which additional skills are relevant for a given implementation. Skills like `security-review`, `web-search`, and `ui-design-brain` go unused unless the Implement agent happens to think of them.

## Solution

The Plan agent scans `.claude/skills/*/SKILL.md` at the end of its run, reads each skill's `name` and `description` frontmatter, and selects the ones relevant to the current feature. For each selected skill it writes a one-line `invoke_when` hint. The result is written to `context.yaml` as `recommended_skills` before handing off to Implement.

The Implement agent reads this list during pre-implementation setup and, for each task in the implementation loop, checks whether any recommended skill's `invoke_when` condition matches before writing code.

## Approach

Scan `.claude/skills/*/SKILL.md` at runtime (Approach A). Self-maintaining — new skills automatically become available for recommendation. Skills already always-on in the implement agent's frontmatter (`git-commit`, `find-patterns`, `agent-context`) are excluded.

## Changes

### 1. `plan/SKILL.md`

Add a new **Step 3: Recommend skills** after writing `3_plan.md`:

- Scan `.claude/skills/*/SKILL.md`, read `name` and `description` frontmatter from each
- Exclude skills already loaded in the implement agent's frontmatter: `agent-context`, `ui-design-brain`, `shadcn`, `find-patterns`, `git-commit`
- For each remaining skill, decide if it is relevant to this feature based on the spec and research
- For each selected skill, write a one-line `invoke_when` hint
- Write `recommended_skills` to `context.yaml`

### 2. `agent-context/template.yaml`

Add `recommended_skills` block after `artifacts`:

```yaml
recommended_skills: []
# Skills the Plan agent determined are relevant for this feature's implementation.
# Populated during the Plan step. Read by the Implement agent before the implementation loop.
# Example entry:
# - skill: security-review
#   invoke_when: "After any task involving authentication, authorization, or input validation"
```

### 3. `agent-context/SKILL.md`

Add a `recommended_skills` section explaining the field's lifecycle: written by Plan, read by Implement, not updated by any later step.

### 4. `agents/implement.md`

**Pre-Implementation Setup** — add step 4 after "Run the existing test suite":

> **Load recommended skills** — read `recommended_skills` from `context.yaml`. For each entry, internalize the skill name and its `invoke_when` condition.

**Implementation Loop** — add a check at the start of each task (before writing tests): if the task matches a recommended skill's `invoke_when` condition, invoke that skill first.

## Out of Scope

- Adding `recommend-when` frontmatter to individual skill files
- Dynamic modification of the implement agent's `skills:` frontmatter
- Recommendations for steps other than Implement
