# 1. Beads is a hard requirement for the workflow

Date: 2026-06-16

Status: Accepted

Tracking: beads epic `ai-config-262`

## Context

The workflow skills and agents in this library were built **dual-mode**: every
workflow skill could run fully standalone (tracking state conversationally) and
"enhanced" when [beads](https://github.com/gastownhall/beads) (`bd`) was set up.
The contract lived in `.claude/references/beads.md` and led with "never run `bd`
in standalone mode."

This created ongoing cost:

- ~16 skills and 6 agents each carried two code paths and a detection branch,
  diluting their core instructions.
- The system of record was ambiguous — beads *or* the conversation — which the
  maintainer wanted to eliminate.
- The committed `SessionStart` hook (`bd prime --hook-json`) was silently broken:
  `--hook-json` is not a valid `bd prime` flag, so it errored on every session
  and injected nothing.

## Decision

Beads is now a **hard requirement** for the workflow. The standalone path is
removed from all workflow skills and agents.

- A committed, self-contained session-start gate hook under `.claude/hooks/`
  detects beads (`test -d .beads && command -v bd`). When absent it injects a
  warning directing the user to run the `setup-beads` skill; when present it
  injects lightweight context (`bd ready`) and does **not** invoke `bd prime`
  (whose opinionated injected text fights this repo's `MEMORY.md` system).
- Each workflow skill gains a preflight that hard-stops and redirects to
  `setup-beads` when beads is absent.
- `.claude/references/beads.md` is reshaped from a "dual-mode contract" into the
  single canonical "beads is required" interaction guide.
- Issue **data** stays local/stealth (git-excluded) as before; only the
  *requirement* and the *gate hook* are committed and travel with the library.
- `setup-beads` and `bd-cleanup` remain runnable without beads present — they are
  the bootstrap and maintenance paths and cannot require what they install.

## Consequences

**Positive**

- One unambiguous system of record (beads).
- Skills and agents shed their dual code paths and detection branching.
- The single source of truth for beads interaction is one reference file.
- The broken session hook is replaced with a working, purpose-built gate.

**Negative / trade-offs**

- The library can no longer be adopted "as-is" without running `setup-beads`
  first; a fresh project sees warnings until beads is initialized. The gate hook
  and per-skill redirect are the mitigations.
- One-time sweep across ~16 skills + 6 agents + reference + docs.

## Alternatives considered

- **Keep dual-mode (status quo).** Rejected: the maintainer explicitly wants a
  single system of record, and the dual paths are a standing maintenance tax.
- **Warn but continue (soft requirement).** Skills would warn yet still track
  conversationally. Rejected: this preserves the standalone path the change is
  meant to remove, keeping the system of record ambiguous.
- **Fix `bd prime --hook-json` instead of a custom hook.** Rejected: even a
  corrected `bd prime` injects session-close/push and anti-`MEMORY.md` guidance
  that conflicts with this repo's configuration.
- **New model-invocable `beads` skill.** Rejected: `.claude/references/beads.md`
  is already the single source of truth; a second artifact would duplicate and
  drift.
