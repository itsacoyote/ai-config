---
name: bd-cleanup
description: Use when the beads database has grown large or needs maintenance — reclaim disk space and prune or compact old closed issues. Leads with non-destructive reclaim (doctor, Dolt GC, compaction) and treats deletion as a dry-run-first, confirmed last resort. Developer-invoked.
disable-model-invocation: true
allowed-tools: Read Bash(bd *) Bash(du *) Bash(test *) Bash(command -v *) Bash(ls *)
---

# Beads Cleanup

Maintenance for a beads database that has grown large or accumulated cruft. Work from
**least destructive to most destructive** and **always preview before deleting** — closed
issues are the project's history, so prefer reclaiming space over erasing the record.

The usual cause of a large `.beads/` is not too many issues — it's **Dolt commit history**:
with auto-commit on every write, the embedded Dolt store grows over time. Garbage-collecting
that (`bd admin compact --dolt`) reclaims space **without touching a single issue**, and is
almost always the right first move.

The CLI is large and evolving — **verify flags with `bd admin <cmd> --help` first.** Top-level
aliases exist (`bd compact`, `bd cleanup`); this skill uses the canonical `bd admin …` form.

## When NOT to use

- Beads isn't set up here (`.beads/` absent) — nothing to maintain.
- Routine health only — if you just want repairs, `bd doctor --fix` alone is enough (step 2).
- You want to wipe beads entirely and start over — that's `bd admin reset`, a different,
  destructive operation explicitly **out of scope** here (see "Out of scope").

## Preflight

Confirm beads exists, or stop:

```bash
test -d .beads && command -v bd >/dev/null 2>&1 && echo ok || echo "no beads here"
```

## Step 1 — Assess before changing anything

Understand *why* it's large before acting:

```bash
du -sh .beads .beads/embeddeddolt 2>/dev/null   # where the size is
bd admin compact --stats                        # compaction stats / candidates
bd doctor                                        # health (read-only)
bd list --status closed --json | jq length 2>/dev/null   # how many closed issues
```

Report what you find, then pick the lightest step that addresses it.

## Step 2 — Routine repair (safe, no data loss)

```bash
bd doctor --fix
```

Handles common health issues and gitignore/schema repairs without deleting anything. Often
all that's needed.

## Step 3 — Reclaim disk without losing issues (preferred)

**Dolt garbage collection** — the usual fix for a bloated `.beads/`; reclaims storage from
Dolt's history, keeps every issue:

```bash
bd admin compact --dolt --dry-run   # preview
bd admin compact --dolt             # run GC
```

**Semantic compaction** — shrink *old closed* issues by summarizing them (they stay, just
smaller): Tier 1 ≈ 70% at 30+ days closed, Tier 2 ≈ 95% at 90+ days. The no-API path is
analyze→apply; `--auto` needs `ANTHROPIC_API_KEY`.

```bash
bd admin compact --stats            # what's eligible
bd admin compact --auto --dry-run   # preview (if using AI auto mode)
bd admin compact --auto --all       # compact all eligible (requires API key)
```

Prefer compaction over deletion whenever the history still has value.

## Step 4 — Prune old closed issues (destructive — last resort)

`bd admin cleanup` **permanently deletes** closed issues. **By default it deletes ALL closed
issues** — never run a bare `--force`. Always scope by age, dry-run first, and confirm with
the developer before deleting.

```bash
bd admin cleanup --older-than 90 --dry-run   # 1) preview only what's old enough
# review the preview with the developer; then, only on explicit confirmation:
bd admin cleanup --older-than 90 --force     # 2) actually delete those
```

- **Always `--dry-run` first** and show the developer exactly what would go.
- **Always `--older-than N`** (a conservative threshold, e.g. 90 days) unless the developer
  explicitly asks to delete all closed issues.
- `--ephemeral` targets only closed wisps (transient molecules) — a safer narrow sweep.
- `--cascade` recursively deletes *dependents* — call it out loudly; only with explicit consent.

## Out of scope

- **`bd admin reset`** removes *all* beads data, config, and hooks — a full wipe, not cleanup.
  This skill never runs it. If the developer truly wants a reset, they run it themselves
  (`bd admin reset --force`) deliberately.

## What this skill will not do

- **Never delete without a dry-run and explicit confirmation.** Preview, show, confirm, then `--force`.
- **Never run a bare `bd admin cleanup --force`** (it deletes every closed issue) — always `--older-than`.
- **Never run `bd admin reset`** — wiping beads is not cleanup.
- **Prefer non-destructive reclaim** (`doctor --fix`, `compact --dolt`, semantic compaction)
  over deleting issues; closed issues are history.
- **Never trust a flag it hasn't verified** against `bd admin <cmd> --help` — the CLI evolves.
