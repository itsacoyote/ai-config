# 8. Pi ships a personal global context file, not a per-project template

Date: 2026-08-04

Status: Accepted

Amends: [ADR 0007](0007-claude-tree-global-install.md) (its "codex/ and pi/ are
per-project copies" statement, for pi/ only)

Tracking: beads epic `ai-config-hmc`

## Context

[ADR 0006](0006-per-harness-config-trees.md) created `pi/` as a per-project AGENTS.md
template, mirroring `codex/`. In practice the content the maintainer wants Pi to carry is
**personal** — communication rules (the maintainer's personal communication
accommodations), personal engineering conventions, and a change gate — which applies in
every repository, not per project. Pi reads a global context file from `~/.pi/agent/AGENTS.md` in addition to
project files, which is the natural home for personal content: install once, active
everywhere, nothing leaks into shared repositories.

Pi is also the most minimal harness — no permission system, no skills autoloading (yet) —
so this one file carries the weight that Claude Code spreads across settings, hooks, and
skills. That argues for a single tightly-written global file over copies scattered
through projects.

## Decision

- `pi/AGENTS.md` is the maintainer's **personal global Pi context file**, installed with
  `mkdir -p ~/.pi/agent && cp pi/AGENTS.md ~/.pi/agent/AGENTS.md`. The per-project
  template model is dropped for Pi.
- The file carries: who-the-maintainer-is, the unified "how to write to me" rules, the
  visual-anchor conventions, the engineering conventions (formerly the template's whole
  content), an inline description of the Define→…→Document workflow, and a hard change
  gate (workflow required; trivial changes need explicit approval first).
- `codex/` keeps its per-project copy model — Codex's project-scoped discovery is the
  point there. The three trees remain unsynced (ADR 0006 stands).

## Consequences

### Positive

- Personal rules follow the maintainer to every repo without per-project setup or the
  risk of committing personal accommodations into shared projects.
- One file to keep tight, matching Pi's one-file philosophy.

### Negative / trade-offs

- Pi projects get no project-scoped conventions from this repo; if a shared project needs
  Pi guidance, that becomes that project's own AGENTS.md, written separately.
- The change gate is prose, not an enforced permission boundary — Pi has no mechanism to
  make it one. Accepted: the gate's value is unambiguous instructions, and the workflow
  skills port (next feature) will reinforce it.

## Alternatives considered

- **Keep the per-project template and add a separate global file.** Rejected — the
  template's conventions content is personal anyway; two files with overlapping scope
  recreates the drift-and-conflict problem this feature exists to remove.
- **Merge personal content into the per-project template.** Rejected — personal
  accommodations would be copied into (and committed to) shared repositories.
