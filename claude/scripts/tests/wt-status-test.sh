#!/usr/bin/env bash
# wt-status-test.sh — self-contained test suite for claude/scripts/wt-status.sh
#
# The script is allow-listed with a directory argument, so it runs with no
# permission prompt. The unrecoverable failure is code execution from a
# hand-written .git/config in the directory it is pointed at: core.fsmonitor and a
# filter.<x>.clean driver both run commands during `git status`. Two guards stop
# that — the argument must be the current directory or a registered worktree of
# the current repository, and git runs with the command-executing config keys it
# honours disabled. Both are mutation-tested below: the positive control (a real
# worktree IS accepted) comes first, so a guard that refuses everything cannot
# pass the refusal test for the wrong reason.
#
# Usage:  bash claude/scripts/tests/wt-status-test.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

set -u

pass=0
fail=0
ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SCRIPT="${WT_STATUS_UNDER_TEST:-$REPO_ROOT/claude/scripts/wt-status.sh}"

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
TMP=$(mktemp -d "$TMPBASE/wt-status-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp produced no directory" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# A trusted repository with one linked worktree.
TRUSTED="$TMP/trusted"; mkdir -p "$TRUSTED"
( cd "$TRUSTED" && git init -q . && echo a > a.txt && git add a.txt && git commit -qm init &&
  git worktree add -q "$TMP/trusted-wt" -b wt-branch ) || { echo "fixture setup failed" >&2; exit 1; }

# A hostile repository: a hand-written config that would run commands during
# status through two different keys. Each payload leaves a marker file.
HOSTILE="$TMP/hostile"; mkdir -p "$HOSTILE"
( cd "$HOSTILE" && git init -q . && echo '* filter=pwn' > .gitattributes && echo data > f.txt &&
  git add .gitattributes f.txt && git commit -qm init &&
  git config filter.pwn.clean "sh -c 'touch $TMP/PWNED_CLEAN; cat'" &&
  git config core.fsmonitor "sh -c 'touch $TMP/PWNED_FSMON; exit 1'" &&
  echo changed > f.txt ) || { echo "hostile fixture setup failed" >&2; exit 1; }

# run_from <cwd> [args...] — captures stdout+stderr in OUT and the status in STATUS.
OUT=''; STATUS=0
run_from() {
  local from="$1"; shift
  OUT="$(cd "$from" && bash "$SCRIPT" "$@" 2>&1)"
  STATUS=$?
}
no_markers() { [ ! -e "$TMP/PWNED_CLEAN" ] && [ ! -e "$TMP/PWNED_FSMON" ]; }
clear_markers() { rm -f "$TMP/PWNED_CLEAN" "$TMP/PWNED_FSMON"; }

section 'argument confinement'

run_from "$TRUSTED"
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q '^branch: main'; then
  ok 'reports the current directory with no argument'
else
  not_ok "reports the current directory with no argument (status=$STATUS): $OUT"
fi

# Positive control for the refusal below.
run_from "$TRUSTED" "$TMP/trusted-wt"
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q '^branch: wt-branch'; then
  ok 'accepts a registered worktree of the current repository as the argument'
else
  not_ok "accepts a registered worktree of the current repository as the argument (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): an unrelated directory is refused before any git
# command runs inside it. Remove the worktree-list check and this goes red: the
# hostile status runs and drops a marker.
clear_markers
run_from "$TRUSTED" "$HOSTILE"
if [ "$STATUS" = 1 ] && printf '%s' "$OUT" | grep -q 'refusing' && no_markers; then
  ok 'refuses an unrelated repository as the argument and runs nothing in it'
else
  not_ok "refuses an unrelated repository as the argument and runs nothing in it (status=$STATUS, markers: $(ls "$TMP" | grep PWNED | tr '\n' ' ')): $OUT"
fi

# A symlink to the hostile repo is resolved physically before the comparison.
ln -s "$HOSTILE" "$TMP/alias"
clear_markers
run_from "$TRUSTED" "$TMP/alias"
if [ "$STATUS" = 1 ] && no_markers; then
  ok 'refuses a symlink alias of an unrelated repository'
else
  not_ok "refuses a symlink alias of an unrelated repository (status=$STATUS): $OUT"
fi

NOTREPO="$TMP/notrepo"; mkdir -p "$NOTREPO"
run_from "$TRUSTED" "$NOTREPO"
if [ "$STATUS" = 1 ] && printf '%s' "$OUT" | grep -q 'refusing'; then
  ok 'refuses a plain directory that is not a worktree'
else
  not_ok "refuses a plain directory that is not a worktree (status=$STATUS): $OUT"
fi

run_from "$NOTREPO"
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q 'not a git working tree'; then
  ok 'reports a non-repository current directory and exits 0'
else
  not_ok "reports a non-repository current directory and exits 0 (status=$STATUS): $OUT"
fi

section 'config hardening'

# GUARD (mutation-tested): with the hostile repo as the CURRENT directory the
# confinement does not apply (the user chose that directory), so the -c flags are
# the only defence against core.fsmonitor. Remove `-c core.fsmonitor=false` from
# the wrapper and this goes red: the fsmonitor marker appears. The clean-filter
# marker is not asserted here; no flag disables a named filter driver, which is
# exactly why the argument is confined above.
clear_markers
run_from "$HOSTILE"
if [ "$STATUS" = 0 ] && [ ! -e "$TMP/PWNED_FSMON" ]; then
  ok 'does not run core.fsmonitor from the current repository config'
else
  not_ok "does not run core.fsmonitor from the current repository config (status=$STATUS, fsmon marker: $([ -e "$TMP/PWNED_FSMON" ] && echo yes || echo no)): $OUT"
fi

if grep -q 'GIT_CONFIG_NOSYSTEM=1' "$SCRIPT" && grep -q 'core.hooksPath=/dev/null' "$SCRIPT"; then
  ok 'ignores system git config and hooks'
else
  not_ok 'ignores system git config and hooks'
fi

section 'portability'

if sed 's/#.*//' "$SCRIPT" | grep -Eq '(^|[[:space:]])(mapfile|readarray|(declare|local)[[:space:]]+-A)([[:space:]]|$)'; then
  not_ok 'uses no bash 4 builtins'
else
  ok 'uses no bash 4 builtins'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
