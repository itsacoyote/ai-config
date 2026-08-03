# 4. Revert the agent-agnostic library and stay Claude-only

Date: 2026-08-02

Status: Accepted

Supersedes: [ADR 0003](0003-agent-agnostic-library.md)

Amended by: [ADR 0006](0006-per-harness-config-trees.md) — reintroduces per-harness trees
as unsynced duplicates; the rejection of sync machinery stands.

Tracking: beads epic `ai-config-vzg`

## Context

[ADR 0003](0003-agent-agnostic-library.md) decided to maintain `.claude/` and a portable
`.agents/` library side by side, so Codex and Pi could run the same workflow methodology.
That decision shipped in PR #55, followed by PR #56 which added `pwt`, a Pi worktree
launcher. Together they added 251 files: 49 portable skill copies, shared references,
neutral role manifests, an installer, a checksum-validating manifest, a catalog generator,
`.codex/` adapters, a root `AGENTS.md`, and `docs/technical-guide.md`.

Reviewing the result in use, the cost/benefit did not hold:

- **Maintenance cost is paid on every edit, and it is not small.** ADR 0003 accepted drift
  between the two trees as a known trade-off, mitigated by checksums, a declared-differences
  manifest, catalog regeneration, and a validator. In practice that means a one-line change
  to a skill becomes: edit `.claude/`, assess and edit `.agents/`, regenerate the catalog,
  refresh the manifest, run the validator, run the portable tests, and confirm the Claude
  diff is clean. That is a per-change tax on the repository's most common operation.
- **The benefit was never realized.** The portability goal was speculative. No Codex or Pi
  workflow was actually run against the portable tree, so the recurring cost bought parity
  that existed on paper. ADR 0003 itself deferred the question of a canonical source until
  "behavioral parity has been demonstrated" — that demonstration never happened.
- **The front door regressed.** `README.md` went from 239 lines to 58, with the skill
  catalog and workflow orientation displaced into a `docs/technical-guide.md` organized
  around installing the portable library rather than around using the skills. The primary
  reader of this repository got a worse entry point in exchange for the secondary reader's
  install instructions.
- **Neither tree improved.** `.claude/` was byte-identical before and after both PRs. The
  change was purely additive scaffolding around an unchanged core.

Separately, `pwt` from PR #56 is a genuinely good idea — centrally organized worktrees
under `~/github/.worktrees/<owner>/<repo>/<name>/` with create/reuse/list/remove
subcommands — but it was written against Pi, not Claude Code.

## Decision

Revert to the Claude-only configuration captured by the `claude-only-v1` tag (commit
`b7e25cf`, PR #54). Specifically:

- Remove `.agents/`, `.codex/`, `AGENTS.md`, and `docs/technical-guide.md`.
- Restore `README.md`, `CLAUDE.md`, and ADR 0002 to their tagged content, dropping the
  dual-tree maintenance obligations and the cross-harness dispatch section.
- `.claude/` remains the single library and the sole source of truth. There is no portable
  tree and no parity obligation.

The revert lands as a **single forward-only restore commit** on `main` via a pull request.
PRs #55 and #56 stay in the history rather than being rewritten, so the reverted work
remains readable and recoverable by ref.

ADR 0003 is retained and marked superseded rather than deleted, per the ADR lifecycle in
the `documentation-and-adrs` skill. Its reasoning about harness isolation models, the
non-portability of skill tool metadata as a permission boundary, and the behavioral (not
OS-enforced) nature of a generic runner's read-only mode is still correct, and is worth
having if multi-harness support is ever revisited.

The `pwt` concept is kept as tracked follow-up work (beads `ai-config-qsj`) to be
reimplemented natively for Claude Code, with the original recoverable at
`git show e128a71:.agents/scripts/pwt`.

## Consequences

### Positive

- A skill edit is one file in `.claude/skills/` again — no parallel copy, manifest refresh,
  catalog regeneration, or validator run.
- `README.md` returns as the catalog and workflow front door.
- `CLAUDE.md` drops the "assess both trees" instruction and the portable maintenance
  checklist, so future contributors are not held to a contract for a tree that no longer
  exists.
- The repository's scope matches how it is actually used: a Claude Code configuration
  library.

### Negative / trade-offs

- Codex and Pi users get nothing from this repository. That is accepted; they were not
  being served in practice anyway.
- If multi-harness support is revived, the portable tree must be rebuilt or recovered from
  history rather than incrementally maintained. The ADR 0003 rationale survives to inform
  that, but the code does not survive in the tree.
- `main` carries two merged PRs whose entire content is subsequently removed, which reads
  oddly in the log. Preserving published history was judged worth that cost.

## Alternatives considered

- **Keep `.agents/` and stop maintaining it.** Rejected — an unmaintained duplicate of 49
  skills is worse than no duplicate. It silently drifts and misleads anyone who installs it.
- **Keep the portable tree but drop the sync obligations** (no manifest, no validator, no
  catalog). Rejected — those mechanisms were the only thing making drift visible. Removing
  them keeps the cost of the duplicate while discarding its safeguards.
- **`git revert -m 1` on both merge commits.** Rejected in favor of a single restore
  commit: two revert-of-merge commits produce a noisier log and make any future re-land of
  #55/#56 awkward, since git treats the reverted-merge ancestry as already applied.
- **Hard reset `main` to `claude-only-v1` and force-push.** Rejected — it rewrites already
  published history for a cosmetically cleaner log, and would require every other clone and
  worktree tracking `main` to reset.
- **Delete ADR 0003.** Rejected — the ADR lifecycle in `documentation-and-adrs` is explicit
  that superseded ADRs are retained for historical context.
- **Salvage `pwt` into the tree now** (e.g. under `.claude/skills/` or `archive/`).
  Rejected for this change — porting it is real design work with open questions about how
  it relates to the `reground` skill and `.worktreeinclude`. Filed as `ai-config-qsj` so it
  is queued rather than half-landed.
