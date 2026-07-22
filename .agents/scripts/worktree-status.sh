#!/usr/bin/env bash
# worktree-status.sh — repo-agnostic git worktree orientation.
#
# Answers "where am I": current worktree, branch, working-tree state, and the
# other worktrees in this repo. Read-only. Safe in any git repo (or none).
#
# Usage:  worktree-status.sh [--brief]
#   (default)  full multi-line orientation
#   --brief    single line, for a SessionStart hook / statusline

set -u
BRIEF=0
[ "${1:-}" = "--brief" ] && BRIEF=1

# Not a git repo -> say so and leave (exit 0; this is orientation, not an error).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$BRIEF" = 1 ]; then echo "not a git repo"; else echo "Not inside a git repository."; fi
  exit 0
fi

top=$(git rev-parse --show-toplevel 2>/dev/null)
name=$(basename "$top")
branch=$(git branch --show-current 2>/dev/null)
[ -z "$branch" ] && branch="(detached $(git rev-parse --short HEAD 2>/dev/null))"

dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
stash=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

# ahead/behind vs upstream, only if an upstream is configured
ahead=0; behind=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  set -- $(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
  behind=${1:-0}; ahead=${2:-0}
fi

if [ "$BRIEF" = 1 ]; then
  state="clean"; [ "$dirty" -gt 0 ] && state="DIRTY:$dirty"
  extra=""
  [ "$stash" -gt 0 ] && extra="$extra stash:$stash"
  [ "$ahead" -gt 0 ] && extra="$extra ahead:$ahead"
  [ "$behind" -gt 0 ] && extra="$extra behind:$behind"
  echo "worktree=$name branch=$branch $state$extra"
  exit 0
fi

# ---- full mode ----
echo "Worktree: $name   ($top)"
echo "Branch:   $branch"
tree="clean"; [ "$dirty" -gt 0 ] && tree="$dirty uncommitted file(s)"
line="Tree:     $tree"
[ "$stash" -gt 0 ] && line="$line · $stash stash entr(y/ies)"
[ "$ahead" -gt 0 ] && line="$line · $ahead ahead"
[ "$behind" -gt 0 ] && line="$line · $behind behind upstream"
echo "$line"

echo
echo "All worktrees in this repo (→ = current):"
git worktree list | while IFS= read -r wl; do
  wpath=$(echo "$wl" | awk '{print $1}')
  if [ "$wpath" = "$top" ]; then echo "  → $wl"; else echo "    $wl"; fi
done

echo
echo "Recent commits on this branch:"
git log --oneline -3 2>/dev/null | sed 's/^/  /'
