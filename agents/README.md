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

## Verify changes

Run the self-contained Bash suites from the repository root:

```sh
bash agents/skills/writing-skills/scripts/tests/check-skill-test.sh
bash agents/scripts/tests/install-test.sh
bash agents/scripts/tests/repository-contract-test.sh
```

The contract suite pins the canonical four-skill inventory, retired-path removal, portable
Codex/Pi guidance, documentation links, and the Pi-port landing split.
