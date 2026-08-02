#!/usr/bin/env bash
# clwt-test.sh — self-contained test suite for .claude/scripts/clwt
#
# Builds a throwaway world under a fake $HOME: a bare "remote", a primary clone,
# and stub `claude` / `gh` binaries on PATH that log how they were invoked. That
# stub-logs-its-environment trick is what lets us assert the thing that matters
# most — that a launched session really does inherit the worktree as its cwd.
#
# Usage:  bash .claude/scripts/tests/clwt-test.sh
# Exits non-zero if any check fails.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
CLWT="$REPO_ROOT/.claude/scripts/clwt"

pass=0
fail=0
ok() { printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
not_ok() { printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# check <label> <command...>  — passes when the command exits 0
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else not_ok "$label"; fi
}

# check_fails <label> <command...> — passes when the command exits non-zero
check_fails() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then not_ok "$label"; else ok "$label"; fi
}

# check_output <label> <needle> <command...> — passes when stdout+stderr contains needle.
# Output is captured before grepping: under `pipefail` a pipeline reports the command's
# non-zero status even when grep matched, and most of what we assert on here is an
# intentional error path.
check_output() {
  local label=$1 needle=$2
  shift 2
  local out
  out=$("$@" 2>&1) || true
  if printf '%s\n' "$out" | grep -qF -- "$needle"; then ok "$label"; else not_ok "$label"; fi
}

# check_equals <label> <expected> <actual>
check_equals() {
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1 (expected '$2', got '$3')"; fi
}

section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------- world setup

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = Test\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n' \
  >"$GIT_CONFIG_GLOBAL"

mkdir -p "$HOME"
HOME=$(cd "$HOME" && pwd -P) # resolve symlinks once so path comparisons are stable
export HOME

REMOTE="$HOME/remotes/owner/project.git"
PRIMARY="$HOME/github/owner/project"
MANAGED="$HOME/github/.worktrees/owner/project"
BIN="$HOME/bin"
mkdir -p "$REMOTE" "$HOME/github/owner" "$BIN"

export CLWT_TEST_LOG="$TMP/launch.log"
: >"$CLWT_TEST_LOG"

# Stub `claude`: records the working directory it inherited, the tracker-root env
# var, and its arguments. This is the whole point of the suite.
cat >"$BIN/claude" <<'STUB'
#!/usr/bin/env bash
{
  printf 'pwd=%s\n' "$PWD"
  printf 'CLWT_REPO_ROOT=%s\n' "${CLWT_REPO_ROOT-<unset>}"
  printf 'args=%s\n' "$*"
} >>"$CLWT_TEST_LOG"
STUB
chmod +x "$BIN/claude"

# Stub `gh`: canned responses driven by files the tests write.
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
if [ -f "$CLWT_GH_UNAVAILABLE" ]; then
  echo "gh: not authenticated" >&2
  exit 1
fi
case "$1 ${2-}" in
  "auth status") exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"
export CLWT_GH_UNAVAILABLE="$TMP/gh-unavailable"

export PATH="$BIN:$PATH"

# Bare remote with a real commit, default branch `main`.
git init -q --bare "$REMOTE"
git init -q "$TMP/seed"
(
  cd "$TMP/seed"
  printf 'seed\n' >README.md
  git add README.md
  git commit -qm 'initial commit'
  git remote add origin "$REMOTE"
  git push -q origin HEAD:refs/heads/main
)
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main
git clone -q "$REMOTE" "$PRIMARY"
PRIMARY=$(cd "$PRIMARY" && pwd -P)

# `clwt` is invoked from inside the primary clone unless a test says otherwise.
clwt_in() {
  local dir=$1
  shift
  (cd "$dir" && "$CLWT" "$@")
}
clwt() { clwt_in "$PRIMARY" "$@"; }

printf 'clwt test suite\n'
printf 'script:  %s\n' "$CLWT"
printf 'sandbox: %s\n' "$TMP"

# ------------------------------------------------------------------ existence

section 'script'
check 'the clwt script exists and is executable' test -x "$CLWT"
check 'the clwt script parses as valid bash' bash -n "$CLWT"
if grep -q 'python' "$CLWT" 2>/dev/null; then
  not_ok 'the clwt script has no python dependency'
else
  ok 'the clwt script has no python dependency'
fi

# ----------------------------------------------------------------------- help

section 'help and dispatch'

SUBCOMMANDS='new branch open pr root list remove prune install help'
missing=''
for sub in $SUBCOMMANDS; do
  clwt help 2>&1 | grep -qE "^ *$sub( |$)" || missing="$missing $sub"
done
if [ -z "$missing" ]; then
  ok 'clwt help lists all ten subcommands'
else
  not_ok "clwt help lists all ten subcommands (missing:$missing)"
fi

check_output 'an unimplemented subcommand reports not yet implemented rather than unknown command' \
  'not yet implemented' clwt prune
check_output 'an unknown subcommand is reported as unknown' \
  'unknown command' clwt definitely-not-a-command
check_fails 'an unknown subcommand exits non-zero' clwt definitely-not-a-command

# ------------------------------------------------------- identity and roots

section 'repo identity and roots'

# `clwt debug-roots` prints the resolved foundation values, one per line, so the
# suite can assert them without reaching into the script's internals.
roots() { clwt_in "$1" debug-roots 2>/dev/null; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

R=$(roots "$PRIMARY")
check_equals 'clwt derives the owner from the origin remote' 'owner' "$(field "$R" owner)"
check_equals 'clwt derives the repo from the origin remote' 'project' "$(field "$R" repo)"
check_equals 'the managed root is under ~/github/.worktrees/<owner>/<repo>' \
  "$MANAGED" "$(field "$R" managed_root)"
check_equals 'the primary checkout resolves to the checkout and not to the git directory' \
  "$PRIMARY" "$(field "$R" primary)"

primary_value=$(field "$R" primary)
case $primary_value in
  *.git) not_ok 'the primary checkout does not end in .git' ;;
  *) ok 'the primary checkout does not end in .git' ;;
esac

# From a subdirectory of the primary checkout.
mkdir -p "$PRIMARY/nested/deeper"
check_equals 'the primary checkout resolves correctly from a subdirectory' \
  "$PRIMARY" "$(field "$(roots "$PRIMARY/nested/deeper")" primary)"

# From inside a worktree — the case `git rev-parse --show-toplevel` gets wrong.
WT="$MANAGED/probe-wt"
mkdir -p "$MANAGED"
git -c advice.detachedHead=false -C "$PRIMARY" worktree add -q -b probe/roots "$WT" HEAD 2>/dev/null
check_equals 'the primary checkout resolves correctly from inside a worktree' \
  "$PRIMARY" "$(field "$(roots "$WT")" primary)"
check_equals 'the managed root resolves correctly from inside a worktree' \
  "$MANAGED" "$(field "$(roots "$WT")" managed_root)"

# ssh-form and https-form remotes both parse.
ssh_probe=$(cd "$PRIMARY" && git remote set-url origin 'git@github.com:someone/thing.git' \
  && "$CLWT" debug-roots 2>/dev/null)
check_equals 'clwt derives owner and repo from an ssh origin remote' \
  'someone/thing' "$(field "$ssh_probe" owner)/$(field "$ssh_probe" repo)"

https_probe=$(cd "$PRIMARY" && git remote set-url origin 'https://github.com/someone/thing.git' \
  && "$CLWT" debug-roots 2>/dev/null)
check_equals 'clwt derives owner and repo from an https origin remote' \
  'someone/thing' "$(field "$https_probe" owner)/$(field "$https_probe" repo)"

(cd "$PRIMARY" && git remote set-url origin "$REMOTE")

# No origin at all.
git init -q "$TMP/no-remote"
check_fails 'clwt exits non-zero when the origin remote is missing' \
  clwt_in "$TMP/no-remote" debug-roots
check_output 'clwt names the missing origin remote in its error' \
  'origin' clwt_in "$TMP/no-remote" debug-roots

# Not a repository at all.
mkdir -p "$TMP/not-a-repo"
check_fails 'clwt outside a git repository exits non-zero' \
  clwt_in "$TMP/not-a-repo" debug-roots
check_output 'clwt says it must be run inside a git repository' \
  'git repository' clwt_in "$TMP/not-a-repo" debug-roots

# -------------------------------------------------------------------- summary

section "results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
