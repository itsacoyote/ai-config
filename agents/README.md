# Shared Agent Skills

Portable [Open Agent Skills](https://agentskills.io/) used by both Codex and Pi live in
`agents/skills/`. Put a skill here only when its core instructions, references, and scripts
work in both harnesses; keep harness-specific configuration under `codex/` or `pi/`.

The source layout mirrors the personal discovery location:

```text
agents/skills/<name>/SKILL.md  ->  ~/.agents/skills/<name>/SKILL.md
```

Codex and Pi both discover the standard project `.agents/skills/` and personal
`~/.agents/skills/` locations automatically. The repo's human-run `link.sh` symlinks every
skill here into `~/.agents/skills/` and removes anything else there except what the
private directory provides (see the [root README](../README.md#installing-the-library)).

For a project-local install, copy the desired skill directories into that project's
`.agents/skills/` and review conflicts by hand.

## Personal user preferences

[`AGENTS.md`](AGENTS.md) is a standalone personal user-preferences file, separate from the
shared skills. It preserves reusable communication, workflow, worktree, commit, and signing
policies without depending on a particular harness's commands or hooks. It is independently
maintained; it is not generated or synchronized with other templates. `link.sh` links it as
`~/.codex/AGENTS.md`; Pi has its own file under `pi/`. Keep private external-work sections
out of it: they belong in the private directory's `work-rules.md`.

While maintaining this library, follow the [root repository guidance](../AGENTS.md),
not the personal policies in the file.

## Verify changes

Run the self-contained Bash suites from the repository root:

```sh
bash agents/skills/writing-skills/scripts/tests/check-skill-test.sh
bash tests/link-test.sh
```
