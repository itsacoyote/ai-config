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

Install portable skills from this repo's root:

```sh
mkdir -p <target>/.agents/skills
cp -R agents/skills/. <target>/.agents/skills/
```

Rules:

- `codex/AGENTS.md` is optional project guidance. Merge relevant sections into the target's
  existing `AGENTS.md` by hand; never overwrite project or personal instructions.
- Portable skills stay under `.agents/skills/` — never flatten them into the project root.
- If the target already has `.agents/skills/<name>/` directories, merge or rename per
  skill rather than overwriting.

## Or install the skills once, personally

Codex also discovers skills in `~/.agents/skills` across every project:

```sh
agents/install.sh
agents/install.sh --dry-run
```

Run the installer yourself from the repository checkout. It additively creates or updates
the shared skill files and reports personal paths it leaves untouched.

The installer never handles `AGENTS.md`, `~/.codex`, or Pi configuration. Project and
personal instructions remain manually managed.
