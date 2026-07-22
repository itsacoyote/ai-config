# 3. Keep Claude and the portable agent library side by side

Date: 2026-07-23

Status: Accepted

Tracking: beads epic `ai-config-pfw`

## Context

This repository originally exposed its workflow only through Claude Code:
`.claude/skills/`, thin `.claude/agents/`, hooks, rules, and Claude-specific tool
syntax. Codex and Pi can both discover Agent Skills under `.agents/skills/`, but
they have different isolation and orchestration models:

- Codex supports project custom agents and sandbox policies.
- Pi has no built-in subagents or MCP. It can run isolated `pi --print` workers,
  dedicated saved sessions, and optional extensions, but an extension must not be
  required for the workflow.
- Skill tool metadata is not a portable permission boundary.
- Existing Claude users must not lose hooks, rules, settings, or behavior while
  portable parity is being established.

The workflow also needs one neutral definition of isolated roles and QA results;
copying permission policy independently into each harness would drift.

## Decision

Maintain two side-by-side libraries for now:

- `.claude/` remains the unchanged Claude Code implementation.
- `.agents/` contains 49 flat, portable skills plus shared references, neutral
  role prompts/contracts, scripts, a generated catalog, compatibility matrix,
  and versioned ownership manifest.
- `.codex/agents/` contains thin Codex adapters generated from or validated
  against `.agents/agents/roles.json`. Non-executing roles are read-only;
  `qa-review` has artifact-limited workspace writes; `implementer` inherits the
  supervised parent policy.
- Pi read-only and verification workers run as fresh processes through
  `.agents/scripts/run-pi-role.sh`. Implementation is rejected by that generic
  runner and must use `autorun`'s externally sandboxed implementation launcher.
- Research on Pi defaults to a dedicated session whose synthesis is persisted to
  beads. Bounded lenses may use fresh worker processes. Neither tmux nor a
  subagent extension is required.

The neutral role manifest is the machine-readable permission policy input.
Adapters must parse it rather than infer policy from prompts, filenames,
frontmatter, or Claude agents. The manifest and prompts are not themselves a
security boundary. Provider aliases and harness-specific dispatch syntax stay in
adapters.

Pi's generic runner isolates context and rejects implementation, but its
read-only and verification boundaries remain behavioral because it is not an
OS-enforced filesystem sandbox. Generic workers must not process untrusted
repositories or PR content without an external sandbox/container. Pi
implementation always requires the supervised external sandbox launcher.

The complete `.agents/` tree installs as one unit because skills depend on shared
references, scripts, role prompts, and schemas. The installer:

- preserves unrelated files;
- verifies source checksums before writing;
- protects locally modified previously-owned files;
- authenticates an exact prior manifest through hashes declared by the new
  source manifest before allowing prior-only removals;
- excludes optional project `.codex/` adapters from the default personal install.

Beads remains mandatory, and the workflow remains Define → Research → Plan →
Implement → Validate → Document with human approval at Define and at the draft-PR
handoff. Source editing is serialized. Review and QA roles return findings rather
than silently becoming implementers.

Neither `.claude/` nor `.agents/` is canonical across harnesses. A later decision
may choose a canonical source only after behavioral parity has been demonstrated
and recorded.

## Consequences

### Positive

- Codex and Pi gain the same workflow methodology without regressing Claude.
- Shared role, QA, reference, and installer contracts have one portable source.
- Permission differences are visible and validated instead of hidden in prose.
- Pi remains usable with its stock CLI and degrades browser work explicitly when
  no browser CLI or extension is available.
- Installation and upgrades protect unrelated and locally modified files.

### Negative / trade-offs

- Adapted skill copies can drift from `.claude/`; source checksums, declared
  differences, catalog checks, and the complete validator make that drift
  explicit but do not eliminate maintenance work.
- Pi implementation requires an external sandbox launcher. Without one,
  supervised Pi implementation blocks safely.
- Codex project adapters and root `AGENTS.md` are project configuration, so they
  are not installed by the default personal `.agents` installer.
- Browser/MCP behavior cannot be identical: Pi has no native MCP and must use an
  available CLI or extension capability.

## Alternatives considered

- **Replace `.claude/` immediately with `.agents/`.** Rejected because hooks,
  rules, invocation behavior, and real-harness parity are not interchangeable.
- **Make Claude files symlinks into `.agents/`.** Rejected because copied
  configurations must remain portable and the frontmatter/path adaptations are
  intentional.
- **Bundle a required Pi subagent extension.** Rejected because fresh processes
  and dedicated sessions provide the needed isolation without an extension or
  tmux dependency.
- **Put provider models and tool aliases in neutral roles.** Rejected because it
  would make the supposedly portable contract provider-specific.
- **Install only selected skills.** Rejected because shared references, scripts,
  schemas, and role contracts form one dependency-connected library.
