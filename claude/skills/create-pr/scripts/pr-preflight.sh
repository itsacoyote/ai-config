#!/bin/sh
# pr-preflight.sh — deterministic discovery before opening a pull request.
#
# Encodes the mechanical part of the create-pr skill so it isn't re-derived each
# time: find the PR template by GitHub's precedence, surface the project's
# convention docs to read, and report PR readiness. It does NOT write the title
# or body, interpret a documented process, or choose among multiple templates —
# those are judgment and stay in the skill.
#
# Template precedence (first single file wins; GitHub's standard locations,
# case-insensitive name, in .github/ then repo root then docs/):
#   .github/PULL_REQUEST_TEMPLATE.md, .github/pull_request_template.md,
#   PULL_REQUEST_TEMPLATE.md, pull_request_template.md,
#   docs/PULL_REQUEST_TEMPLATE.md, docs/pull_request_template.md
# Then a PULL_REQUEST_TEMPLATE/ directory (multiple templates → you choose).
# If none, falls back to the create-pr skill's own template.md.
#
# Usage:
#   pr-preflight.sh                  full report + the body scaffold to fill in
#   pr-preflight.sh --template-only  print ONLY the chosen template body to stdout
#
# Exit: 0 ok; 2 usage error; 3 --template-only but multiple templates (you must choose).

set -u

TEMPLATE_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--template-only) TEMPLATE_ONLY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Resolve the skill's default template (absolute) BEFORE we cd to the repo root.
SKILL_DIR="$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || SKILL_DIR=""
DEFAULT_TEMPLATE="${SKILL_DIR:+$SKILL_DIR/template.md}"

# Operate from the repo root so template paths resolve correctly.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" && cd "$ROOT"

hr() { echo "────────────────────────────────────────────────────"; }

# ── Discover the PR template ─────────────────────────────────────────────────
TEMPLATE_PATH=""
for c in .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md \
         PULL_REQUEST_TEMPLATE.md pull_request_template.md \
         docs/PULL_REQUEST_TEMPLATE.md docs/pull_request_template.md; do
  if [ -f "$c" ]; then TEMPLATE_PATH="$c"; break; fi
done

TEMPLATE_DIR=""
for d in .github/PULL_REQUEST_TEMPLATE .github/pull_request_template \
         PULL_REQUEST_TEMPLATE docs/PULL_REQUEST_TEMPLATE; do
  if [ -d "$d" ]; then TEMPLATE_DIR="$d"; break; fi
done

# ── --template-only: emit just the body scaffold ─────────────────────────────
if [ "$TEMPLATE_ONLY" = 1 ]; then
  if [ -n "$TEMPLATE_PATH" ]; then
    cat "$TEMPLATE_PATH"; exit 0
  elif [ -n "$TEMPLATE_DIR" ]; then
    echo "multiple templates in $TEMPLATE_DIR — choose one (run without --template-only):" >&2
    ls -1 "$TEMPLATE_DIR" >&2; exit 3
  elif [ -n "$DEFAULT_TEMPLATE" ] && [ -f "$DEFAULT_TEMPLATE" ]; then
    cat "$DEFAULT_TEMPLATE"; exit 0
  else
    echo "no PR template found and skill default is unavailable." >&2; exit 3
  fi
fi

# ── Full report ──────────────────────────────────────────────────────────────
echo "PR preflight"
hr

echo "Convention docs present — READ these for any required PR process (base branch,"
echo "labels, reviewers, linked-issue syntax, title rules); the project's process wins:"
found_doc=0
for f in CLAUDE.md AGENTS.md CONTRIBUTING.md .github/CONTRIBUTING.md docs/CONTRIBUTING.md; do
  [ -f "$f" ] && { printf '  • %s\n' "$f"; found_doc=1; }
done
[ "$found_doc" = 0 ] && echo "  (none found)"

echo
chosen=""
if [ -n "$TEMPLATE_PATH" ]; then
  echo "PR template: $TEMPLATE_PATH — fill this out for the body."
  chosen="$TEMPLATE_PATH"
elif [ -n "$TEMPLATE_DIR" ]; then
  echo "PR template directory: $TEMPLATE_DIR — multiple templates; choose the one that"
  echo "fits the change (or ask):"
  ls -1 "$TEMPLATE_DIR" | sed 's/^/  • /'
else
  if [ -n "$DEFAULT_TEMPLATE" ] && [ -f "$DEFAULT_TEMPLATE" ]; then
    echo "PR template: none in project — using the create-pr skill default ($DEFAULT_TEMPLATE)."
    chosen="$DEFAULT_TEMPLATE"
  else
    echo "PR template: none found, and the skill default is unavailable — write the body free-form."
  fi
fi

echo
echo "Readiness:"
branch="$(git branch --show-current 2>/dev/null)"; [ -n "$branch" ] || branch="(detached HEAD)"
base="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
[ -n "$base" ] || base="main"
printf '  • current branch : %s\n' "$branch"
printf '  • base (target)  : %s\n' "$base"
if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  up="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"
  ahead="$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo '?')"
  if [ "${ahead:-0}" != "0" ]; then
    printf '  • push state     : tracks %s — %s local commit(s) NOT pushed (push before opening)\n' "$up" "$ahead"
  else
    printf '  • push state     : tracks %s, up to date\n' "$up"
  fi
else
  printf '  • push state     : no upstream — push with: git push -u origin %s\n' "$branch"
fi
if command -v gh >/dev/null 2>&1; then
  pr="$(gh pr list --head "$branch" --json number,state,isDraft \
        --jq '.[0] | select(.number) | "#\(.number) \(.state)\(if .isDraft then " (draft)" else "" end)"' 2>/dev/null)"
  [ -n "$pr" ] && printf '  • existing PR    : %s — edit it instead of opening a new one\n' "$pr" \
               || printf '  • existing PR    : none for this branch\n'
else
  printf '  • existing PR    : gh unavailable — could not check\n'
fi

if [ -n "$chosen" ]; then
  echo
  echo "───── body scaffold (from $chosen — fill it in) ─────"
  cat "$chosen"
fi
