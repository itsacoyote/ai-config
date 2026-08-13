# Codex CLI configuration

Codex-specific conventions for [Codex CLI](https://developers.openai.com/codex/) sessions.
Portable Open Agent Skills shared with Pi live separately under [`../agents/skills`](../agents/skills/).

## What's here

| File | What it is |
|---|---|
| `AGENTS.md` | Always-on engineering conventions, loaded from a project's root |
| `../agents/skills/` | Portable skills for commits, branches, PRs, and skill authoring |

The skills use Codex's native Agent Skills layout — Codex invokes them implicitly when the
task matches a skill's description, or explicitly via `$git-commit`, `$branch-names`,
`$create-pr`, `$writing-skills`.

## Install into a project

Install the guidance and portable skills separately from this repo's root:

```sh
cp codex/AGENTS.md <target>/
mkdir -p <target>/.agents/skills
cp -R agents/skills/. <target>/.agents/skills/
```

Rules:

- If the target already has an `AGENTS.md`, **merge this file's content into it by hand —
  never overwrite** the project's own guidance.
- Portable skills stay under `.agents/skills/` — never flatten them into the project root.
- If the target already has `.agents/skills/<name>/` directories, merge or rename per
  skill rather than overwriting.

## Or install the skills once, personally

Codex also discovers skills in `~/.agents/skills` across every project:

```sh
mkdir -p ~/.agents/skills
cp -R agents/skills/. ~/.agents/skills/
```

This overwrites same-named skills already in `~/.agents/skills` — check with
`ls ~/.agents/skills` first and merge by hand if `git-commit`, `branch-names`, or
`create-pr`, or `writing-skills` already exist there.

`AGENTS.md` remains per-project — copy (or merge) it into each repository where the
conventions should apply.
