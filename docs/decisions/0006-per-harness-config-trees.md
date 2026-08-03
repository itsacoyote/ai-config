# 6. Add per-harness config trees as unsynced duplicates

Date: 2026-08-03

Status: Accepted

Amends: [ADR 0004](0004-revert-agent-agnostic-library.md)

Tracking: beads epic `ai-config-bju`

## Context

[ADR 0004](0004-revert-agent-agnostic-library.md) reverted the agent-agnostic `.agents/`
library and returned the repo to Claude-only. Its cost analysis stands: the failure of
PRs #55/#56 was the **synchronization machinery** — checksummed manifests, catalog
regeneration, validators — which taxed every skill edit to maintain parity that was never
exercised.

Two things have changed since:

- The maintainer now actually runs the other harnesses: the Codex CLI, and Pi (pi.dev)
  calling the gpt-5-codex model. Without any port, those sessions violate the library's own
  conventions (commit format, branch names, PR process). The benefit ADR 0004 judged
  speculative is now concrete, if modest.
- The architecture on offer is the opposite of ADR 0003's: **duplicate the content and let
  the copies diverge freely**, rather than abstract it and enforce parity. Divergence is
  expected — the harnesses differ enough that the trees would grow apart legitimately.

Both harnesses read a root `AGENTS.md`, which carries the always-on conventions directly.
For skills, Codex has its own GA native mechanism — `.agents/skills/<name>/SKILL.md` with
`name`/`description` frontmatter, invoked explicitly (`$name`) or implicitly by description
match — so the codex tree ships skills in that layout rather than routing to them from
AGENTS.md prose.

## Decision

Add two self-contained top-level trees, `codex/` and `pi/`, beside `.claude/`:

- Each tree is a complete, copy-paste-able unit for its harness; installing one drags
  nothing else along. `AGENTS.md` files are templates copied to a target project's root.
- Content is **duplicated at porting time and never synced**. There is no manifest, no
  checksums, no catalog, no validator, no parity obligation, and no instruction anywhere
  to keep the trees aligned. Editing `.claude/` never obligates touching `codex/` or `pi/`,
  and vice versa.
- Porting a skill means rewriting it for the target harness: for Codex, a
  `.agents/skills/<name>/SKILL.md` with `name`/`description` frontmatter and no Claude
  mechanics (`Skill()` invocation, subagent references, Claude tool syntax, `.claude/`
  paths); keep the methodology. Substance the Claude version pulls from other skills,
  rules, scripts, or templates is inlined, since none of those travel.
- The first pass is minimal: `codex/` gets AGENTS.md, a README, and the three git skills;
  `pi/` gets only AGENTS.md. The Pi workflow is deliberately deferred to its own feature —
  Pi's minimalism demands its own design, not a copy of Codex's.
- `.claude/` remains the sole tree this repository itself runs on, and the README stays
  organized around it.

This amends ADR 0004's "stay Claude-only" decision while preserving its core finding: the
revert was right because of the sync machinery, and that machinery is not coming back.
ADR 0003's abstraction (neutral role manifests, adapters, installers) stays superseded.

## Consequences

### Positive

- Codex and Pi sessions get the git conventions for the cost of a one-time port.
- A skill edit is still one file in `.claude/skills/` — the per-change tax ADR 0004
  eliminated does not return.
- Each harness tree can be tuned to its harness without negotiating a shared abstraction.

### Negative / trade-offs

- The trees **will** drift from `.claude/` and from each other, silently — accepted by
  design. A convention changed in `.claude/` reaches the other trees only when someone
  ports it again by hand.
- Duplicated content means a fix to a ported skill's substance may need manual repetition
  in the sibling tree, with nothing flagging the omission.
- Anyone reading the repo sees three overlapping statements of the git conventions; the
  README must be explicit that `.claude/` is the canonical one for this repo's own work.

## Alternatives considered

- **Physically shared core directory** (`shared/` consumed by both trees). Rejected — it
  reintroduces coupling: a shared file can't diverge per harness without splitting, and each
  tree stops being independently copy-paste-able.
- **Symlinks from harness trees into `.claude/`.** Rejected in ADR 0003 already; copies must
  remain portable and the adaptations are intentional.
- **Separate repository for non-Claude config.** Rejected — porting constantly reads
  `.claude/` as source, and a second repo doubles the ceremony for a library only one
  person maintains.
- **Revive `.agents/` from history.** Rejected — its value was the abstraction/validation
  layer, which is exactly what failed.
- **Full-library port in one pass.** Rejected — most skills need real adaptation (subagent
  orchestration has no equivalent), and the first pass should prove the pattern cheaply.
