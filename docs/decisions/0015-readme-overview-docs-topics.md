# 15. Keep the README an overview and move topic detail into docs/

Date: 2026-10-09

Status: Accepted

Amends: [ADR 0004](0004-revert-agent-agnostic-library.md) (its "README returns as the
catalog and workflow front door" consequence)

Tracking: beads epic `ai-config-ewp`

## Context

The README grew to 603 lines, nearly half of it `clwt` flag behavior and install
internals. The overview was hard to find, and a reader could not link to one topic without
linking to the whole file.

[ADR 0004](0004-revert-agent-agnostic-library.md) (lines 35-39) called an earlier move of
the catalog and workflow orientation into `docs/technical-guide.md` a front-door
regression: the README fell to 58 lines and was organized around installing a portable
library. That risk applies to any split, so this decision has to show how it differs.

## Decision

The README is an overview of at most 150 lines. Each topic has one file in `docs/`:
workflow, catalog, `clwt`, install, and harnesses. The README is the index to them.

This is not the regression ADR 0004 rejected:

- The README keeps the workflow diagram, the six-step table, and every name in the
  catalog. A reader gets the orientation without leaving the file.
- The split is by topic for using the library, not around installing a portable one.
  Detail is one link away.
- The README stays organized around the Claude tree
  ([ADR 0006](0006-per-harness-config-trees.md), lines 58-59) and keeps stating that
  `claude/` is canonical for this repository's own work (ADR 0006, lines 81-82).

## Consequences

- Skill and agent names live in two places: the README "What's inside" section and
  `docs/catalog.md`. `AGENTS.md` carries the rule to update both.
- `clwt-test.sh` content checks read `docs/clwt.md`, not the README.
- A topic can be linked and edited on its own.

## Alternatives considered

- **Keep the catalog tables in the README and drop the length limit.** Rejected: the
  catalog alone is about 135 lines, so the overview would stay buried.
