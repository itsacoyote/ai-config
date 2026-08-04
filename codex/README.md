# Codex CLI configuration

A self-contained set of conventions and skills for [Codex CLI](https://developers.openai.com/codex/)
sessions, ported from this repository's `claude/` library. **Not synced with `claude/`** —
content was duplicated at porting time and diverges freely (see
[ADR 0006](../docs/decisions/0006-per-harness-config-trees.md)).

## What's here

| File | What it is |
|---|---|
| `AGENTS.md` | Always-on engineering conventions, loaded from a project's root |
| `.agents/skills/git-commit/SKILL.md` | Commit-message conventions |
| `.agents/skills/branch-names/SKILL.md` | Branch naming |
| `.agents/skills/create-pr/SKILL.md` | PR titles, bodies, and the pre-PR checklist |

The skills use Codex's native Agent Skills layout — Codex invokes them implicitly when the
task matches a skill's description, or explicitly via `$git-commit`, `$branch-names`,
`$create-pr`.

## Install into a project

`.agents` is dot-prefixed, so `cp -r codex/* <target>/` **silently skips it** and leaves a
project with conventions but no skills. Use these exact commands from this repo's root:

```sh
cp codex/AGENTS.md <target>/
cp -R codex/.agents <target>/
```

Rules:

- If the target already has an `AGENTS.md`, **merge this file's content into it by hand —
  never overwrite** the project's own guidance.
- `.agents/` stays nested exactly as shipped — never flatten its contents into the
  project root.
- If the target already has `.agents/skills/<name>/` directories, merge or rename per
  skill rather than overwriting.

## Or install the skills once, personally

Codex also discovers skills in `~/.agents/skills` across every project:

```sh
mkdir -p ~/.agents/skills
cp -R codex/.agents/skills/. ~/.agents/skills/
```

This overwrites same-named skills already in `~/.agents/skills` — check with
`ls ~/.agents/skills` first and merge by hand if `git-commit`, `branch-names`, or
`create-pr` already exist there.

`AGENTS.md` remains per-project — copy (or merge) it into each repository where the
conventions should apply.
