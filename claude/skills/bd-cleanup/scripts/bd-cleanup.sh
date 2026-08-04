#!/bin/sh
# bd-cleanup.sh — assess a beads database and (opt-in) reclaim space safely.
#
# Encodes ONLY the non-destructive part of the `bd-cleanup` skill — operations
# that keep every issue's content fully intact:
#
#   assess (read-only)  →  [server: bd doctor --fix]  →  bd compact --days N --force
#
# `bd compact` squashes Dolt auto-commit history older than N days into one
# commit (recent commits preserved) and runs Dolt GC — the usual fix for a
# bloated .beads/. It keeps every issue; only fine-grained commit-level
# time-travel within the squashed window is lost.
#
# Verified against bd 1.0.5: in EMBEDDED mode (this config's default, the
# .beads/embeddeddolt/ backend), `bd doctor` and `bd admin compact --dolt` are
# "not supported" and no-op/error — the working reclaim is top-level `bd compact`.
#
# This script has NO path to anything that loses or alters issue history.
# These stay in the skill, human-gated, and are NOT here:
#   • bd flatten                  — squashes ALL history (irreversible time-travel loss)
#   • bd admin compact (semantic) — "permanent graceful decay; original content discarded"
#   • bd gc                       — decays (summarizes) old issues
#   • bd prune / bd admin cleanup — permanently DELETE closed issues
#   • bd admin reset              — wipes all beads data/config
# Run those by hand, dry-run first, with explicit confirmation (see SKILL.md).
#
# Usage:
#   bd-cleanup.sh                 assess only (read-only) — sizes, history, stats, recommendation
#   bd-cleanup.sh --reclaim       assess, then run the safe ladder (bd compact)
#   bd-cleanup.sh --reclaim --days 90   squash only commits older than 90 days (default 30)
#
# Exit: 0 ok; 1 preflight failure or a step errored; 2 usage error.

set -u

RECLAIM=0
DAYS=30
while [ $# -gt 0 ]; do
  case "$1" in
    -r|--reclaim) RECLAIM=1; shift ;;
    --days)
      [ $# -ge 2 ] || { echo "error: --days requires a value" >&2; exit 2; }
      DAYS="$2"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$DAYS" in (*[!0-9]*|'') echo "error: --days must be a non-negative integer" >&2; exit 2 ;; esac

fail() { echo "✗ $*" >&2; exit 1; }
hr()   { echo "────────────────────────────────────────────────────"; }

# Run a command, print its combined output indented, and PRESERVE its exit code.
# (A bare `cmd | sed` would mask cmd's status behind sed's — POSIX sh has no pipefail.)
run_indented() {
  out="$("$@" 2>&1)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'
  return $rc
}

# ── Preflight ────────────────────────────────────────────────────────────────
[ -d .beads ] || fail "no .beads/ here — nothing to maintain. (Run from the repo root.)"
command -v bd >/dev/null 2>&1 || fail "bd is not installed."

# This config's default is embedded Dolt (stealth init → .beads/embeddeddolt/),
# where `bd doctor[ --fix]` is unsupported and no-ops. Top-level `bd compact`
# (the reclaim) works in both modes; doctor repairs only apply in server mode.
EMBEDDED=0
[ -d .beads/embeddeddolt ] && EMBEDDED=1

size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1+0}'; }
human()   { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

# ── Assess (read-only) ───────────────────────────────────────────────────────
echo "Beads maintenance — assessment"
hr
echo "Disk usage:"
printf '  %-22s %s\n' ".beads" "$(human .beads)"
[ -d .beads/embeddeddolt ] && printf '  %-22s %s\n' ".beads/embeddeddolt" "$(human .beads/embeddeddolt)"
[ -d .beads/backup ]       && printf '  %-22s %s\n' ".beads/backup"       "$(human .beads/backup)"

echo
echo "Closed issues: $(bd list --status closed --json 2>/dev/null | jq 'length' 2>/dev/null || echo '?')"

echo
echo "Dolt commit history (bd compact --dry-run) — non-destructive reclaim preview:"
run_indented bd compact --dry-run || true

echo
echo "Semantic-compaction candidates (bd admin compact --stats) — LOSSY option, not run here:"
run_indented bd admin compact --stats || true

echo
echo "Health:"
if [ "$EMBEDDED" = 1 ]; then
  echo "  bd doctor is not supported in embedded mode (this config's default) — skipped."
else
  run_indented bd doctor || true
fi
hr

if [ "$RECLAIM" = 0 ]; then
  cat <<EOF
Recommendation:
  • To reclaim space safely, re-run with --reclaim. It squashes Dolt commit
    history older than ${DAYS} days (bd compact --days ${DAYS} --force) and runs GC,
    keeping every issue. Tune the window with --days N.
  • These LOSE or alter history and are NOT done here — they need your judgment
    and a dry-run + confirmation (see the bd-cleanup skill):
      Step 2  semantic compaction (discards content) / bd flatten (irreversible)
      Step 3  prune / delete closed issues
EOF
  exit 0
fi

# ── Reclaim (non-destructive only) ───────────────────────────────────────────
before_kb="$(size_kb .beads)"

echo
if [ "$EMBEDDED" = 1 ]; then
  echo "▶ bd doctor --fix — skipped (not supported in embedded mode)"
else
  echo "▶ bd doctor --fix (safe repairs, no data loss)"
  run_indented bd doctor --fix || fail "bd doctor --fix failed — see output above."
fi

echo
echo "▶ bd compact --days $DAYS --force (squash Dolt commits >${DAYS}d, run GC — keeps all issues)"
run_indented bd compact --days "$DAYS" --force || fail "bd compact failed — see output above."

after_kb="$(size_kb .beads)"
hr
reclaimed_kb=$(( before_kb - after_kb ))
echo "Done (non-destructive reclaim)."
printf '  .beads: %s KB → %s KB' "$before_kb" "$after_kb"
if [ "$reclaimed_kb" -gt 0 ]; then
  printf '  (reclaimed %s KB)\n' "$reclaimed_kb"
else
  printf '  (no net reclaim — history may already be compact, or nothing older than %sd)\n' "$DAYS"
fi
echo "  Every issue is intact. For deeper reclaim (bd flatten — irreversible) or to"
echo "  prune/semantically compact (history loss), use the bd-cleanup skill — with confirmation."
exit 0
