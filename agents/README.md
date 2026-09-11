# Shared Agent Skills

Portable [Open Agent Skills](https://agentskills.io/) used by both Codex and Pi live in
`agents/skills/`. Put a skill here only when its core instructions, references, and scripts
work in both harnesses; keep harness-specific configuration under `codex/` or `pi/`.

The source layout mirrors the personal discovery location:

```text
agents/skills/<name>/SKILL.md  ->  ~/.agents/skills/<name>/SKILL.md
```

Codex and Pi both discover the standard project `.agents/skills/` and personal
`~/.agents/skills/` locations automatically. For a personal additive install, run this
yourself from the repository checkout:

```sh
agents/install.sh
agents/install.sh --dry-run
```

The installer manages only regular files below `agents/skills/`. It preserves and reports
personal files already below `~/.agents/skills/`, skips source symlinks, and refuses unsafe
destination links before writing.

It never reads, installs, merges, or modifies `AGENTS.md`, `~/.codex`, or Pi configuration.
Keep personal `~/.agents/AGENTS.md` and harness-native configuration under manual control.

For a project-local install, copy the desired skill directories into that project's
`.agents/skills/` and review conflicts by hand.

## Personal user preferences

[`AGENTS.md`](AGENTS.md) is a standalone personal user-preferences template, separate
from the shared skills. It preserves reusable communication, workflow, worktree, commit,
and signing policies without depending on a particular harness's commands or hooks.
It is independently maintained; it is not generated or synchronized with other templates.

Review and merge the preferences by hand into the user-instruction location supported by
your chosen harness. Omit the opening repository source note when doing so. Neither this
repository path nor `~/.agents/AGENTS.md` is a universal global-discovery location; follow
your harness's own loading rules. The skills installer does not manage this file or your
live user instructions. Keep private external-work sections out of repository copies.

While maintaining this library, follow the [root repository guidance](../AGENTS.md),
not the personal policies in the template.

## Verify changes

Run the self-contained Bash suites from the repository root:

```sh
bash agents/skills/writing-skills/scripts/tests/check-skill-test.sh
bash agents/scripts/tests/install-test.sh
bash agents/scripts/tests/repository-contract-test.sh
```

The contract suite pins the canonical four-skill inventory, retired-path removal, portable
Codex/Pi guidance, documentation links, and the Pi-port landing split.
