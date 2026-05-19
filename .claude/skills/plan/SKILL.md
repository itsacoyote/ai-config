---
name: plan
description: Produce an implementation plan for a feature — file map and TDD-ordered task list. If spec and research are already in context, use them; otherwise ask the user to share them.
allowed-tools: Read Bash(find *)
disable-model-invocation: true
---

# Plan

Produce an implementation plan for a feature.

If a spec and research findings are already in context, use them. Otherwise, ask the user to share the spec and any relevant research before beginning.

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

## Output

Present the complete implementation plan in the conversation using the structure in [template.md](template.md) as a guide. Do not write files unless the user asks.
