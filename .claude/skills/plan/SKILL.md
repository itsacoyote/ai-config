---
name: plan
description: Write a 3_plan.md implementation plan for an approved and researched feature. Produces a file map and explicit, TDD-ordered task list. Use after spec and research docs are both present in the feature folder.
argument-hint: "[feature folder path]"
allowed-tools: Read Write Bash(find *)
disable-model-invocation: true
---

# Plan

Write `3_plan.md` for the feature in `$ARGUMENTS`. If no path is provided, ask which feature folder to plan.

Read `1_spec.md` and `2_research.md` fully before writing anything, including any artifacts referenced in the research doc.

## Guiding principles

**DRY** — if two tasks would produce similar code, consolidate it. Name the shared abstraction explicitly. Don't leave it to the implementer to notice.

**YAGNI** — if it's not required by the spec's acceptance criteria, it does not go in the plan. Cut generalization, future-proofing, and "nice to haves" without mercy.

**TDD** — tests are written before implementation in every task, without exception. Each test case is named explicitly. The implementer should be able to write the test before touching production code.

**Frequent commits** — every task ends with a commit. Commit messages follow the project's established convention.

**Focused files** — each file has one clear responsibility. Files that change together live together. Split by responsibility, not by technical layer. Prefer smaller, focused files over large ones that do too much.

## Step 1: Build the file map

Before writing any tasks, decide and document every file that will be created or modified. This is where decomposition gets locked in — do it deliberately.

For each file:

- State its single responsibility in one sentence
- Define its public interface: what it exports or exposes to other files
- Note which research finding or spec requirement it addresses

The file map has three tables: New Files, Modified Files, and Deleted Files. If the feature removes or replaces any existing files, list them in Deleted Files with the reason. Deletion decisions belong in the map, not discovered mid-implementation.

Do not write tasks until the file map is complete and internally consistent. Every file in the map must earn its place — if its responsibility could belong to another file without violating the single-responsibility rule, merge them.

## Step 2: Write tasks

Tasks are ordered by dependency — foundational code first, dependent code after. Each task is atomic: one logical unit of work, one commit.

For every task:

- **Name it** precisely (e.g. "Add `useAuthToken` hook" not "Add auth logic")
- **List the files** it touches, from the file map
- **Write the tests first** — name each test case explicitly as it would appear in the test file. No vague cases like "it handles errors" — write `it('throws AuthError when token is expired')`. No "should" — test names are assertive statements, not intentions.
- **List implementation steps** as discrete, ordered actions. Each step names the specific function, component, prop, route, or schema being added or changed. No step may say "implement" or "handle" without naming exactly what.
- **For deletion tasks** — explicitly name the file to delete, list every import and reference to remove or update, and include a step to verify nothing references the deleted file after removal.
- **End with a commit** using a conventional commit message

## Step 3: Recommend skills

After writing `3_plan.md`, scan `.claude/skills/*/SKILL.md` to build a list of locally available skills. For each file, read the `name` and `description` fields from the YAML frontmatter.

Exclude skills that are already always-on in the Implement agent's frontmatter and need no conditional recommendation:
- `agent-context`
- `ui-design-brain`
- `shadcn`
- `find-patterns`
- `git-commit`

For each remaining skill, decide whether it is relevant to this feature by comparing its `description` against what you know from `1_spec.md` and `2_research.md`. Use these heuristics as a starting point:

| Skill | Relevant when |
|-------|---------------|
| `security-review` | Feature involves authentication, authorization, session handling, payments, file uploads, input validation, cryptography, or SQL queries |
| `web-search` | Feature integrates with an external API, third-party service, or library not already used in the codebase |
| `verify-correctness` | Feature contains non-trivial algorithms, data transformations, or business logic with many edge cases |
| `verify-coherence` | Feature spans multiple files or modules and consistency across interfaces is a risk |

For each selected skill, write a one-line `invoke_when` hint that is specific to this feature (not generic — reference the actual tasks or code areas from the plan).

Write the result to `context.yaml` in the feature folder:

```yaml
recommended_skills:
  - skill: security-review
    invoke_when: "Before implementing the JWT validation logic in Task 3 and the role-check middleware in Task 5"
```

If no local skills are relevant beyond the always-on set, write `recommended_skills: []` to make the absence explicit.

## Output

Write `3_plan.md` using the template in [template.md](template.md).
