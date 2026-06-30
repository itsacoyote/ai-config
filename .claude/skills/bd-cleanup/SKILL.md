---
name: bd-cleanup
description: Use when the beads database has grown large or needs maintenance — reclaim disk space and prune or compact old closed issues. A script does the non-destructive reclaim (assess + bd compact); flatten, semantic compaction, and deletion are lossy and stay dry-run-first, confirmed last resorts. Developer-invoked.
disable-model-invocation: true
allowed-tools: Read Bash(bd *) Bash(du *) Bash(test *) Bash(command -v *) Bash(ls *) Bash(sh ${CLAUDE_SKILL_DIR}/scripts/bd-cleanup.sh*) Bash(bash ${CLAUDE_SKILL_DIR}/scripts/bd-cleanup.sh*)
---

# Beads Cleanup

Maintenance for a beads database that has grown large or accumulated cruft. Work from
**least destructive to most destructive** and **always preview before deleting** — closed
issues are the project's history, so prefer reclaiming space over erasing the record.

The usual cause of a large `.beads/` is not too many issues — it's **Dolt commit history**:
with auto-commit on every write, the embedded Dolt store grows over time. Squashing that
history with **`bd compact`** (the top-level command) reclaims space **without touching a
single issue**, and is almost always the right first move.

**Two different `compact`s — don't confuse them.** Top-level **`bd compact`** squashes Dolt
*commit* history (non-destructive — every issue stays intact); **`bd admin compact`** does
*semantic* summarization that **discards original issue content** (lossy). This config's
default is **embedded** Dolt (`.beads/embeddeddolt/`), where — verified on bd 1.0.5 —
`bd doctor` and `bd admin compact --dolt` are *not supported* and no-op/error; `bd compact`
is the working reclaim. The CLI evolves, so **verify flags with `bd <cmd> --help` first.**

## When NOT to use

- Beads isn't set up here (`.beads/` absent) — nothing to maintain.
- Routine reclaim only — the script (below) handles assessment and the safe `bd compact`; you
  don't need the destructive steps for ordinary bloat.
- You want to wipe beads entirely and start over — that's `bd admin reset`, a different,
  destructive operation explicitly **out of scope** here (see "Out of scope").

## Step 1 — Assess and reclaim safely (the script)

Run the script. By default it **assesses read-only**; `--reclaim` then applies the
**non-destructive** ladder — operations that keep every issue's content fully intact.

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/bd-cleanup.sh                  # assess: sizes, history, stats, recommendation
sh ${CLAUDE_SKILL_DIR}/scripts/bd-cleanup.sh --reclaim        # assess, then squash old Dolt commits + GC
sh ${CLAUDE_SKILL_DIR}/scripts/bd-cleanup.sh --reclaim --days 90  # only squash commits older than 90 days (default 30)
```

What it does for you:

- **Preflights** (`.beads/` + `bd` present) and reports **where the size is** (`du`), how many
  closed issues exist, the Dolt commit-history breakdown (`bd compact --dry-run`), the
  semantic-compaction candidates (`bd admin compact --stats`, the lossy option), and health.
- On `--reclaim`, runs **`bd compact --days N --force`** — squashes Dolt commit history older
  than N days into one commit (recent commits preserved) and runs Dolt GC, the usual fix for a
  bloated `.beads/`, **without touching a single issue** — then reports the space reclaimed.
- **Knows about embedded mode.** This config's stealth setup uses embedded Dolt
  (`.beads/embeddeddolt/`), where `bd doctor[ --fix]` is unsupported and no-ops — the script
  detects this and skips it. (In server mode it runs `doctor --fix` first.) `bd compact` works
  in both modes.

The script has **no path to anything lossy** — it never deletes, never semantically compacts,
never flattens, never resets. Those are below, by hand, and only with your confirmation.

## Step 2 — Lossy / irreversible reclaim (judgment — NOT in the script)

If `bd compact` (Step 1) doesn't reclaim enough, these go further but each **loses something**.
None are in the script; run them by hand, dry-run first, with explicit confirmation.

**`bd flatten` — irreversible history squash (keeps issues).** Squashes *all* Dolt commit
history into a single commit and GCs. Issue data is fully preserved, but commit-level
time-travel is **gone for good**. The escalation when `bd compact` leaves too much behind.

```bash
bd flatten --dry-run   # preview: commit count + disk usage
bd flatten --force     # squash ALL history — irreversible — only on confirmation
```

**`bd admin compact` (semantic) — discards issue content.** Summarizes old *closed* issues;
bd's own docs call it *"permanent graceful decay — original content is discarded."* Not the
harmless "keep every issue" reclaim `bd compact` is. Use only when the full text of old closed
issues no longer has value. (In embedded mode, `--stats` works but actual compaction may be
unsupported — check `bd admin compact --help`.)

```bash
bd admin compact --stats            # what's eligible (Tier 1 ≈ 70% at 30+ days, Tier 2 ≈ 95% at 90+ days)
bd admin compact --analyze --json   # no-API path: export candidates for review, then --apply
bd admin compact --auto --all       # AI auto mode, compact all eligible (needs ANTHROPIC_API_KEY) — on confirmation
```

(`bd gc` bundles "decay old issues + compact commits + Dolt GC" in one shot — but the *decay*
part is the lossy semantic step above, so prefer the explicit commands so you can see and
confirm each effect.)

## Step 3 — Prune old closed issues (destructive — last resort)

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
- **Prefer the script's non-destructive reclaim** (`bd compact` keeps every issue intact) over
  the lossy options; closed issues are history. `bd flatten` *loses commit history*, semantic
  compaction *discards* issue content, and deletion *erases* issues — each needs explicit
  confirmation, none are in the script.
- **Never trust a flag it hasn't verified** against `bd <cmd> --help` — the CLI evolves, and
  embedded mode supports a different command set than server mode (`bd compact`, not
  `bd admin compact --dolt`).
