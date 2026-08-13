# Shared Agent Skills

Portable [Open Agent Skills](https://agentskills.io/) used by both Codex and Pi live in
`agents/skills/`. Put a skill here only when its core instructions, references, and scripts
work in both harnesses; keep harness-specific configuration under `codex/` or `pi/`.

The source layout mirrors the personal discovery location:

```text
agents/skills/<name>/SKILL.md  ->  ~/.agents/skills/<name>/SKILL.md
```

Until the installer lands, copy a skill directory into a project's `.agents/skills/` or
the personal `~/.agents/skills/` location. Never copy either harness's `AGENTS.md` as part
of installing this shared library.
