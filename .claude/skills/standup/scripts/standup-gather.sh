#!/bin/sh
# standup-gather.sh — READ-ONLY data gather for the standup skill.
#
# Runs the fixed set of read-only bd/git/gh queries that feed a standup, scoped
# to a time window and the current git user, and dumps the raw results in
# labeled sections. The skill then SYNTHESIZES the briefing from this output —
# translating IDs/hashes into plain language, picking the "you were here"
# pointer, dropping empty buckets, labeling inferences.
#
# READ-ONLY BY CONSTRUCTION: every command here only reads (bd list/ready,
# git log/status/diff/branch/stash list, gh pr list / run list). Nothing mutates
# a file, issue, branch, or remote. Keep it that way — never add a write here.
#
# Window: pass a window as $1 (default 24h). Shorthand Nh/Nd/Nw and bare phrases
# ("friday", "last week", "yesterday", "since monday") are accepted. git uses it
# directly via --since (it parses all of these). For bd's closed-after cutoff a
# YYYY-MM-DD date is computed when the window is relative (GNU or BSD date);
# otherwise recent closed issues are dumped and the skill filters by the window.
# gh "merged" is likewise dumped recent-with-timestamps for the skill to filter.
#
# Beads is REQUIRED (per the standup skill): if it isn't set up, the script exits
# non-zero with a setup-beads message and gathers nothing. gh is optional — a
# missing/unauthed gh degrades to a noted skip of the PR/CI section.
#
# Usage:  standup-gather.sh [window]      e.g. standup-gather.sh 3d
# Exit:   0 gathered ok; 1 beads not set up; 0 with help.

set -u

RAW="${1:-24h}"
case "$RAW" in -h|--help) sed -n '2,30p' "$0"; exit 0 ;; esac
RAW="${RAW#since }"

# GIT_SINCE: a git-parseable relative string. N/UNIT set only for shorthand.
N=""; UNIT=""
case "$RAW" in
  *[0-9][hH]) N="${RAW%[hH]}"; UNIT=H; GIT_SINCE="$N hours ago" ;;
  *[0-9][dD]) N="${RAW%[dD]}"; UNIT=d; GIT_SINCE="$N days ago" ;;
  *[0-9][wW]) N="${RAW%[wW]}"; UNIT=w; GIT_SINCE="$N weeks ago" ;;
  *)          GIT_SINCE="$RAW" ;;
esac

# BD_AFTER: YYYY-MM-DD cutoff for `bd --closed-after`, best-effort and portable.
BD_AFTER=""
if date --version >/dev/null 2>&1; then            # GNU date understands the phrase
  BD_AFTER="$(date -d "$GIT_SINCE" +%Y-%m-%d 2>/dev/null || true)"
elif [ -n "$UNIT" ]; then                          # BSD/macOS: relative shorthand only
  BD_AFTER="$(date -v-"${N}${UNIT}" +%Y-%m-%d 2>/dev/null || true)"
fi

ME="$(git config user.email 2>/dev/null || true)"
[ -n "$ME" ] || ME="$(git config user.name 2>/dev/null || true)"

# Resolve the shared beads-preflight via THIS script's own location (not cwd), so it
# works whether the library is project-local or global (~/.claude). This script lives
# at <lib>/skills/standup/scripts/, the preflight at <lib>/references/. Capture before cd.
SELF_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
PREFLIGHT="$SELF_DIR/../../../references/beads-preflight.sh"

# Operate from the repo root so .beads/ resolves against the project.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" && cd "$ROOT"

# Beads is REQUIRED for standup (see SKILL.md) — gate before gathering anything.
if ! sh "$PREFLIGHT" >/dev/null 2>&1; then
  echo "standup: beads is not set up here — run the setup-beads skill, then retry." >&2
  exit 1
fi

sec() { echo; echo "===== $1 ====="; }

echo "STANDUP DATA GATHER — read-only"
echo "window      : $GIT_SINCE${BD_AFTER:+   (bd/gh: filter to on-or-after $BD_AFTER)}"
echo "author      : ${ME:-<git user not set>}"
echo "NOTE: bd 'closed' and gh 'merged' are dumped recent-with-timestamps — filter them to the window during synthesis."

# ── Beads (required; gated above) ────────────────────────────────────────────
sec "BEADS"
echo "--- closed (Done candidates; filter by closedAt) ---"
if [ -n "$BD_AFTER" ]; then
  bd list --status closed --closed-after "$BD_AFTER" --json 2>&1
else
  bd list --status closed --limit 50 --json 2>&1
fi
echo "--- in_progress (where you left off) ---"
bd list --status in_progress --json 2>&1
echo "--- blocked (with blockers) ---"
bd list --status blocked --json 2>&1
echo "--- ready (Next — unblocked, pick up next) ---"
bd ready 2>&1

# ── Git ──────────────────────────────────────────────────────────────────────
sec "GIT"
echo "--- commits in window (all branches${ME:+, author=$ME}) ---"
git log --all --since="$GIT_SINCE" ${ME:+--author="$ME"} \
  --pretty=format:'%h %ad %d %s' --date=short 2>&1
echo
echo "--- current branch ---";        git branch --show-current 2>&1
echo "--- working tree (status -s) ---"; git status -s 2>&1
echo "--- stashes ---";               git stash list 2>&1
echo "--- unpushed (@{u}..HEAD) ---";  git log '@{u}..HEAD' --pretty=format:'%h %s' 2>/dev/null || echo "(no upstream tracking branch)"
echo
echo "--- uncommitted diffstat (unstaged then staged) ---"
git diff --stat 2>&1
git diff --cached --stat 2>&1

# ── Pull requests / CI ───────────────────────────────────────────────────────
sec "PULL REQUESTS / CI"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "--- open PRs (yours) ---"
  gh pr list --author "@me" --state open \
    --json number,title,headRefName,isDraft,reviewDecision,updatedAt 2>&1
  echo "--- recently merged (yours; filter by mergedAt) ---"
  gh pr list --author "@me" --state merged --limit 30 \
    --json number,title,mergedAt 2>&1
  echo "--- review requested of you (open) ---"
  gh pr list --search "review-requested:@me state:open" \
    --json number,title,author,updatedAt 2>&1
  echo "--- recent CI runs ---"
  gh run list --limit 10 2>&1
else
  echo "(gh unavailable or not authenticated — skipping PRs/CI)"
fi
