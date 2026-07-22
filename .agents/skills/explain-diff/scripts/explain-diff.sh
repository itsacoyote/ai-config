#!/bin/sh
# explain-diff.sh — deterministic mechanics for the explain-diff skill.
#
# Encodes the mechanical parts so they aren't re-derived (or guessed) each run:
#   prepare  stamp today's date, build the dated /tmp output path, and gather the
#            diff + orientation for a target (working tree / PR / range / ref).
#   check    lint the finished HTML: self-contained (no external loads — which is
#            also the security guarantee that nothing leaks off-machine), code
#            blocks won't collapse newlines, and the filename is date-prefixed.
#
# It does NOT choose the target when ambiguous, pick the slug, infer a branch's
# true base, or write/read the explanation itself — those are judgment calls and
# stay in SKILL.md.
#
# Usage:
#   explain-diff.sh prepare [target] [--slug <slug>]
#       target: (omitted) working tree | <number> PR | a..b / a...b range | <ref> branch/commit
#   explain-diff.sh check <file.html>
#
# Known limitation: `check`'s self-contained scan is textual, so an *example*
# code block that literally shows `src="https://…"` or `url(https://…)` will be
# flagged. That's rare in a diff explainer, and erring toward flagging external
# loads is the safer bias — verify the flagged lines are genuinely inert text.
#
# Exit: 0 ok (warnings allowed); 1 check failed; 2 usage error; 3 environment error.

set -u

usage() {
  cat <<'EOF'
Usage:
  explain-diff.sh prepare [target] [--slug <slug>]
      target: (omitted) working tree | <number> PR | a..b / a...b range | <ref> branch/commit
  explain-diff.sh check <file.html>
EOF
}

# --- prepare ---------------------------------------------------------------
cmd_prepare() {
  target=""
  slug=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug)   [ $# -ge 2 ] || { echo "prepare: --slug needs a value" >&2; exit 2; }
                slug="$2"; shift 2 ;;
      --slug=*) slug="${1#--slug=}"; shift ;;
      -*)       echo "prepare: unknown option: $1" >&2; exit 2 ;;
      *)        if [ -z "$target" ]; then target="$1"; shift
                else echo "prepare: unexpected argument: $1" >&2; exit 2; fi ;;
    esac
  done

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 3
  fi

  today=$(date +%F)
  slug_out="${slug:-<slug>}"
  outpath="/tmp/${today}-explanation-${slug_out}.html"

  echo "=== explain-diff: prepare ==="
  echo "date:        $today"
  echo "output file: $outpath"
  [ -z "$slug" ] && echo "  (no --slug given — replace <slug> with a short kebab-case name for this change)"
  echo "  (write the single self-contained HTML file here, then run: explain-diff.sh check \"$outpath\")"
  echo

  # classify the target
  if [ -z "$target" ]; then
    kind="working tree"
  elif printf '%s' "$target" | grep -Eq '^[0-9]+$'; then
    kind="pr"
  elif printf '%s' "$target" | grep -Eq '\.\.'; then
    kind="range"
  else
    kind="ref"
  fi
  echo "target:      ${target:-(working tree)}  [$kind]"

  case "$kind" in
    "working tree")
      echo
      echo "--- status ---";                 git status --short
      if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo
        echo "note: untracked (new) files won't appear in 'git diff' below."
        echo "      To include them, 'git add -N <file>' first, or explain the committed work instead."
      fi
      echo; echo "--- diffstat (unstaged) ---";  git diff --stat
      echo; echo "--- diffstat (staged) ---";    git diff --staged --stat
      echo; echo "--- full diff (unstaged) ---"; git diff
      echo; echo "--- full diff (staged) ---";   git diff --staged
      ;;
    pr)
      if ! command -v gh >/dev/null 2>&1; then
        echo "error: target looks like a PR number but 'gh' is not installed" >&2; exit 3
      fi
      if ! gh auth status >/dev/null 2>&1; then
        echo "error: 'gh' is not authenticated (run: gh auth login)" >&2; exit 3
      fi
      echo
      echo "--- PR metadata ---";     gh pr view "$target"
      echo; echo "--- changed files ---"; gh pr diff "$target" --name-only
      echo; echo "--- full diff ---";     gh pr diff "$target"
      ;;
    range)
      echo
      echo "--- commits in range ---";  git log --oneline "$target"
      echo; echo "--- diffstat ---";     git diff --stat "$target"
      echo; echo "--- full diff ---";    git diff "$target"
      ;;
    ref)
      base=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
      if [ -z "$base" ]; then
        for b in main master; do
          if git show-ref --verify --quiet "refs/heads/$b" \
            || git show-ref --verify --quiet "refs/remotes/origin/$b"; then
            base="$b"; break
          fi
        done
      fi
      [ -z "$base" ] && base="main"
      echo
      echo "note: assuming base '$base' for ref '$target' — CONFIRM this is the right base."
      echo "      A branch's true base is a judgment call (see SKILL.md, Step 1)."
      echo
      echo "--- commits ($base..$target) ---"; git log --oneline "$base..$target"
      echo; echo "--- diffstat ($base...$target) ---"; git diff --stat "$base...$target"
      echo; echo "--- full diff ($base...$target) ---"; git diff "$base...$target"
      ;;
  esac
}

# --- check -----------------------------------------------------------------
cmd_check() {
  file="${1:-}"
  [ -n "$file" ] || { echo "check: missing <file.html>" >&2; exit 2; }
  [ -f "$file" ] || { echo "check: no such file: $file" >&2; exit 2; }

  fail=0
  warn=0
  fname=$(basename "$file")

  echo "=== explain-diff: check $file ==="

  # 1. filename must be date-prefixed (keeps the files time-sorted)
  if printf '%s' "$fname" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
    echo "PASS  filename is date-prefixed"
  else
    echo "FAIL  filename must start with YYYY-MM-DD- (got: $fname)"
    fail=1
  fi

  # 2. self-contained / offline — no external resource LOADS (src/link/@import/url()).
  #    Plain <a href="http…"> anchors are fine and intentionally not matched.
  p_src="src[[:space:]]*=[[:space:]]*[\"']?(https?:)?//"
  p_link="<link[^>]*href[[:space:]]*=[[:space:]]*[\"']?(https?:)?//"
  p_import="@import[^;]*(https?:)?//"
  p_url="url\\([[:space:]]*[\"']?(https?:)?//"
  ext=$( { grep -nEi "$p_src" "$file"; grep -nEi "$p_link" "$file"; \
           grep -nEi "$p_import" "$file"; grep -nEi "$p_url" "$file"; } 2>/dev/null \
         | awk '!seen[$0]++' )
  if [ -n "$ext" ]; then
    echo "FAIL  external resource load(s) — inline everything / use data: URIs:"
    printf '%s\n' "$ext" | sed 's/^/        /'
    fail=1
  else
    echo "PASS  self-contained (no external script/style/font/image loads)"
  fi

  # 3. code blocks won't collapse newlines (heuristic)
  if grep -Eqi '<pre[ >]' "$file" \
    || grep -Eqi 'white-space[[:space:]]*:[[:space:]]*pre(-wrap)?' "$file"; then
    echo "PASS  code blocks protected (<pre> and/or white-space:pre present)"
  else
    echo "WARN  no <pre> or white-space:pre|pre-wrap found — code blocks may collapse to one line"
    warn=1
  fi

  # 4. complete standalone document
  if grep -Eqi '<!doctype html|<html' "$file"; then
    echo "PASS  complete HTML document"
  else
    echo "WARN  no <!doctype html>/<html> — is this a full standalone page?"
    warn=1
  fi

  echo
  if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAILED — fix the FAIL items above before finishing."
    exit 1
  fi
  if [ "$warn" -ne 0 ]; then
    echo "RESULT: passed with warnings — review the WARN items."
  else
    echo "RESULT: all checks passed."
  fi
}

# --- dispatch --------------------------------------------------------------
[ $# -ge 1 ] || { usage; exit 2; }
sub="$1"; shift
case "$sub" in
  prepare)        cmd_prepare "$@" ;;
  check)          cmd_check "$@" ;;
  -h|--help|help) usage ;;
  *)              echo "unknown subcommand: $sub" >&2; usage; exit 2 ;;
esac
