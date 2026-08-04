#!/bin/sh
# diff-scope.sh — resolve the pinned diff scope for a review dispatch.
#
# The deterministic git plumbing from .claude/references/diff-scope.md: a spawner
# (validate / autorun / document) resolves the scope ONCE and passes the pinned
# range to every review agent. This emits the canonical payload line:
#
#   Diff scope: <base>..<head> — changed files: path/A, path/B, …
#
# Modes:
#   (default) branch scope — everything on this branch vs the default branch:
#               base = git merge-base HEAD <default-branch>
#   --task [<base-sha>]     per-task scope — the implementer's commit(s):
#               base = <base-sha> if given, else HEAD~1 (single-commit task)
#   --base <branch>         override the default branch (else origin/HEAD, else main)
#   --range                 print just "<base>..<head>" (for `git diff "$(… --range)"`),
#                           instead of the full payload line — e.g. document reads its own diff
#
# Judgment stays with the caller: WHEN to recompute (validate recomputes before
# each spawn; autorun pins per task), WHICH agents to dispatch, how to read findings.
#
# Usage:  diff-scope.sh [--task [<base-sha>]] [--base <branch>] [--range]
# Exit:   0 ok; 1 cannot resolve the range; 2 usage.

set -u

MODE=branch
TASK_BASE=""
BASE_OVERRIDE=""
RANGE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --range) RANGE_ONLY=1; shift ;;
    --task)
      MODE=task
      # optional positional base sha (only if next arg isn't another flag)
      if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then TASK_BASE="$2"; shift 2; else shift; fi
      ;;
    --base)
      [ $# -ge 2 ] || { echo "error: --base needs a branch" >&2; exit 2; }
      BASE_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "error: not a git repository" >&2; exit 1; }

head="$(git rev-parse HEAD 2>/dev/null)" || { echo "error: cannot resolve HEAD" >&2; exit 1; }

if [ "$MODE" = task ]; then
  if [ -n "$TASK_BASE" ]; then
    base="$(git rev-parse "$TASK_BASE" 2>/dev/null)" || { echo "error: cannot resolve base '$TASK_BASE'" >&2; exit 1; }
  else
    base="$(git rev-parse HEAD~1 2>/dev/null)" || { echo "error: HEAD has no parent (single-commit task needs HEAD~1)" >&2; exit 1; }
  fi
else
  if [ -n "$BASE_OVERRIDE" ]; then
    BR="$BASE_OVERRIDE"
  else
    BR="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
    [ -n "$BR" ] || BR="main"
  fi
  base="$(git merge-base HEAD "$BR" 2>/dev/null)" || { echo "error: cannot compute merge-base of HEAD and '$BR' (does the branch exist?)" >&2; exit 1; }
fi

if [ "$RANGE_ONLY" = 1 ]; then
  printf '%s..%s\n' "$base" "$head"
  exit 0
fi

# Changed-file list as a comma-separated string for the payload line.
files="$(git diff --name-only "$base" "$head" 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
[ -n "$files" ] || files="(none)"

printf 'Diff scope: %s..%s — changed files: %s\n' "$base" "$head" "$files"
