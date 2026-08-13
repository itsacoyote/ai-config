# 10. Share portable Agent Skills between Codex and Pi

Date: 2026-08-13

Status: Accepted

Partially supersedes: [ADR 0006](0006-per-harness-config-trees.md) and
[ADR 0008](0008-pi-global-only-config.md)

Tracking: beads epic `ai-config-vrs`

## Context

ADR 0006 deliberately duplicated Codex and Pi configuration so each harness could diverge
without synchronization machinery. That remains correct for `AGENTS.md`, native settings,
tools, permissions, and workflows that depend on one harness.

Portable skills now have a narrower interoperability boundary. Codex and Pi both implement
the Open Agent Skills directory format and automatically discover repository
`.agents/skills/` and personal `~/.agents/skills/`. Pi documents those locations in its
[official skill documentation](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md).
Keeping identical portable skills in two harness trees would add drift without buying useful
adaptation.

This is not a revival of the architecture rejected in
[ADR 0003](0003-agent-agnostic-library.md). That design synchronized a complete neutral
workflow through manifests, generated adapters, role schemas, checksums, catalogs, and
cross-harness validation. The useful boundary here is much smaller: a skill belongs in the
shared tree only when its shipped instructions and bundled resources work directly in both
harnesses.

## Decision

- `agents/skills/` is the canonical source for portable Agent Skills shared by Codex and Pi.
- A skill with required Codex-only or Pi-only behavior stays in the corresponding harness
  tree. Small capability differences may be documented inside a portable skill only when
  both paths are supported and the common methodology remains coherent.
- There is no duplication, synchronization manifest, generated adapter, parity catalog, or
  obligation to make harness-specific trees match the shared library.
- Codex and Pi load project copies from `.agents/skills/` and personal copies from
  `~/.agents/skills/`. Their explicit invocation syntax may differ and belongs in the skill's
  capability guidance when relevant.
- `agents/install.sh` is a human-run, additive personal installer. It inventories regular
  files below `agents/skills/`, validates the complete destination plan, then installs into
  `~/.agents/skills/`. It preserves and reports personal-only files.
- The installer owns no instructions or native harness configuration. It never reads,
  installs, merges, or modifies `AGENTS.md`, `~/.codex`, `~/.pi`, or `~/.pi/agent`.
  Project `AGENTS.md` and personal `~/.agents/AGENTS.md` remain manually managed.
- `writing-skills` is portable and is the authoring guide for subsequent ports. Ports must
  re-derive discovery, invocation, tools, permissions, and isolation from current primary
  documentation rather than mechanically replacing vendor terms.

## Landing order for the Pi skill port

This shared-library epic lands first. The existing `feat/pi-skills` branch remains untouched
until then, then rebases onto the landed change:

- portable skills move to `agents/skills/`;
- Pi-only skills and configuration stay under `pi/`;
- no duplicate portable copy remains in a Pi-native skills directory.

That landing order keeps the already-active Pi work separate while giving it one final,
unambiguous destination split.

## Consequences

### Positive

- One portable skill edit reaches both harnesses through their standard discovery locations.
- Harness-specific configuration still diverges without cross-tree maintenance pressure.
- The installer has a deliberately narrow ownership boundary and cannot replace personal
  instruction files.
- `writing-skills` can guide ports before the larger Pi workflow arrives.

### Negative / trade-offs

- Authors must decide whether a skill is genuinely portable; a shared location does not make
  harness-specific assumptions portable automatically.
- Behavioral verification still needs each claimed harness because a standard directory
  shape does not guarantee identical selection or tool behavior.
- The personal installer overwrites same-named library files by design. Local variants need
  distinct names or must be restored after choosing to update the shared copy.

## Alternatives considered

- **Keep duplicate Codex and Pi copies.** Rejected for portable skills because silent drift
  has no compensating harness adaptation.
- **Restore ADR 0003's neutral workflow and adapters.** Rejected because manifests,
  generation, schemas, checksums, and parity validation recreate the maintenance system that
  was previously removed.
- **Symlink harness trees to one another.** Rejected because project copies should remain
  ordinary portable directories and harness-specific skills still need independent homes.
- **Install `AGENTS.md` with the skills.** Rejected because project and personal instruction
  files combine multiple sources and are human-owned configuration.
