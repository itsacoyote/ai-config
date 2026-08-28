#!/usr/bin/env bash
# pwt-test.sh — self-contained test suite for pi/scripts/pwt
#
# Builds a throwaway world under a fake $HOME: a bare remote, a primary clone,
# linked worktrees, and stub `pi` binaries on PATH. The stub records its physical
# cwd, repository-root environment, and every argument in a separate file so
# spaces, empty values, and newlines are never flattened by the test harness.
#
# Usage:  bash pi/scripts/tests/pwt-test.sh
# Exits non-zero if any check fails.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
PWT=${PWT_UNDER_TEST:-"$REPO_ROOT/pi/scripts/pwt"}

pass=0
fail=0
ok() { printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
not_ok() { printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# check <label> <command...> — passes when the command exits 0.
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else not_ok "$label"; fi
}

# check_fails <label> <command...> — passes when the command exits non-zero.
check_fails() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then not_ok "$label"; else ok "$label"; fi
}

# check_output <label> <needle> <command...> — passes when stdout+stderr contains needle.
check_output() {
  local label=$1 needle=$2 out
  shift 2
  out=$("$@" 2>&1) || true
  if printf '%s\n' "$out" | grep -qF -- "$needle"; then ok "$label"; else not_ok "$label"; fi
}

# check_equals <label> <expected> <actual>
check_equals() {
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1 (expected '$2', got '$3')"; fi
}

# check_not_contains <label> <needle> <captured-text>
check_not_contains() {
  local label=$1 needle=$2 text=$3
  if printf '%s\n' "$text" | grep -qF -- "$needle"; then not_ok "$label"; else ok "$label"; fi
}

# check_contains <label> <needle> <captured-text>
check_contains() {
  local label=$1 needle=$2 text=$3
  if printf '%s\n' "$text" | grep -qF -- "$needle"; then ok "$label"; else not_ok "$label"; fi
}

current_section=''
section() {
  if [ -n "${PWT_TEST_STOP_AFTER:-}" ] && [ "$current_section" = "$PWT_TEST_STOP_AFTER" ]; then
    printf '\nmutation checkpoint: %d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
    exit
  fi
  current_section=$1
  printf '\n%s\n' "$1"
}

# ---------------------------------------------------------------- world setup

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pwt-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = Test\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n' \
  >"$GIT_CONFIG_GLOBAL"

# Keep both the fake home and the managed-root prefix symlinked. The runtime has
# to normalize the complete path; pre-resolving this fixture would hide that bug.
mkdir -p "$TMP/real-home"
ln -s "$TMP/real-home" "$HOME"
mkdir -p "$TMP/other-volume/worktrees/owner/project"
mkdir -p "$HOME/github/owner"
ln -s "$TMP/other-volume/worktrees" "$HOME/github/.worktrees"

REMOTE="$HOME/remotes/owner/project.git"
PRIMARY_LOGICAL="$HOME/github/owner/project"
MANAGED="$HOME/github/.worktrees/owner/project"
BIN="$HOME/bin"
mkdir -p "$REMOTE" "$BIN"
MANAGED=$(cd "$MANAGED" && pwd -P)

export PWT_TEST_LOG="$TMP/launch.log"
export PWT_TEST_ARGS_DIR="$TMP/launch-args"
export PWT_TEST_PI_STUB="$BIN/pi"
: >"$PWT_TEST_LOG"
mkdir -p "$PWT_TEST_ARGS_DIR"

# Stub `pi`: records observable launch behavior. One file per argument is
# intentional — `$*` would make `"space value"` and two separate arguments look
# identical, and would erase empty arguments entirely.
cat >"$BIN/pi" <<'STUB'
#!/usr/bin/env bash
{
  printf 'selected=%s\n' "${PWT_PI_SELECTED:-path}"
  printf 'pwd=%s\n' "$PWD"
  printf 'PWT_REPO_ROOT=%s\n' "${PWT_REPO_ROOT-<unset>}"
  printf 'argc=%s\n' "$#"
} >>"$PWT_TEST_LOG"
i=0
for arg in "$@"; do
  printf '%s' "$arg" >"$PWT_TEST_ARGS_DIR/$i"
  i=$((i + 1))
done
STUB
chmod +x "$BIN/pi"

export PATH="$BIN:$PATH"

# Bare remote with one real commit and a primary clone.
git init -q --bare "$REMOTE"
git init -q "$TMP/seed"
(
  cd "$TMP/seed" || exit 1
  printf 'seed\n' >README.md
  git add README.md
  git commit -qm 'initial commit'
  git remote add origin "$REMOTE"
  git push -q origin HEAD:refs/heads/main
)
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main
git clone -q "$REMOTE" "$PRIMARY_LOGICAL"
PRIMARY=$(cd "$PRIMARY_LOGICAL" && pwd -P)

mkdir -p "$MANAGED"
WORKTREE="$MANAGED/probe-wt"
git -C "$PRIMARY" worktree add -q -b probe/roots "$WORKTREE" HEAD 2>/dev/null

# A valid but unrelated repository makes the wrong-repository override test
# reach the identity comparison instead of failing earlier for a missing repo.
WRONG_REMOTE="$HOME/remotes/other/wrong.git"
WRONG="$HOME/github/other/wrong"
mkdir -p "$WRONG_REMOTE" "$HOME/github/other"
git init -q --bare "$WRONG_REMOTE"
git clone -q "$REMOTE" "$WRONG"
git -C "$WRONG" remote set-url origin "$WRONG_REMOTE"
WRONG=$(cd "$WRONG" && pwd -P)

unset PWT_REPO_ROOT

pwt_in() {
  local dir=$1
  shift
  (cd "$dir" && "$PWT" "$@")
}
pwt() { pwt_in "$PRIMARY" "$@"; }
pwt_with_root() {
  local dir=$1 root=$2
  shift 2
  (cd "$dir" && PWT_REPO_ROOT="$root" "$PWT" "$@")
}

printf 'pwt test suite\n'
printf 'script:  %s\n' "$PWT"
printf 'sandbox: %s\n' "$TMP"

# ------------------------------------------------------------------ existence

section 'script'
check 'the pwt script exists and is executable' test -x "$PWT"
check 'the pwt script parses as valid bash' bash -n "$PWT"
if grep -q 'python' "$PWT" 2>/dev/null; then
  not_ok 'the pwt script has no python dependency'
else
  ok 'the pwt script has no python dependency'
fi

# ----------------------------------------------------------------------- help

section 'help'

SUBCOMMANDS='new branch open pr root list remove prune install help'
missing=''
for sub in $SUBCOMMANDS; do
  pwt help 2>&1 | grep -qE "^ *$sub( |$)" || missing="$missing $sub"
done
if [ -z "$missing" ]; then
  ok 'pwt help lists all ten subcommands'
else
  not_ok "pwt help lists all ten subcommands (missing:$missing)"
fi

help_text=$(pwt help 2>/dev/null)
check_equals 'pwt --help prints the same usage as pwt help' "$help_text" "$(pwt --help 2>/dev/null)"
check_equals 'pwt -h prints the same usage as pwt help' "$help_text" "$(pwt -h 2>/dev/null)"
check_not_contains 'pwt help omits yolo mode' 'yolo' "$help_text"
check_output 'an unknown subcommand is reported as unknown' \
  'unknown command' pwt definitely-not-a-command
check_fails 'an unknown subcommand exits non-zero' pwt definitely-not-a-command

# ------------------------------------------------------- identity and roots

section 'roots'

# `pwt debug-roots` is an intentionally undocumented diagnostic seam. It makes
# the discovery boundary observable without testing private shell functions.
roots() { pwt_in "$1" debug-roots 2>/dev/null; }
root_value() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

roots_report=$(roots "$PRIMARY")
check_equals 'pwt derives the owner from the origin remote' 'owner' "$(root_value "$roots_report" owner)"
check_equals 'pwt derives the repo from the origin remote' 'project' "$(root_value "$roots_report" repo)"
check_equals 'the managed root is fully resolved' "$MANAGED" "$(root_value "$roots_report" managed_root)"
check_equals 'the primary checkout resolves physically' "$PRIMARY" "$(root_value "$roots_report" primary)"

check_equals 'the primary checkout resolves from inside a linked worktree' \
  "$PRIMARY" "$(root_value "$(roots "$WORKTREE")" primary)"

override_roots=$(pwt_with_root "$WORKTREE" "$PRIMARY" debug-roots 2>/dev/null)
check_equals 'PWT_REPO_ROOT accepts the intended physical primary checkout' \
  "$PRIMARY" "$(root_value "$override_roots" primary)"

OUTSIDE="$TMP/not-a-repository"
mkdir -p "$OUTSIDE"
outside_override_roots=$(pwt_with_root "$OUTSIDE" "$PRIMARY" debug-roots 2>/dev/null)
check_equals 'PWT_REPO_ROOT supplies repository discovery outside Git' \
  "$PRIMARY" "$(root_value "$outside_override_roots" primary)"
check_fails 'pwt still requires a repository when PWT_REPO_ROOT is unset' \
  pwt_in "$OUTSIDE" debug-roots

check_fails 'PWT_REPO_ROOT rejects a relative path' \
  pwt_with_root "$PRIMARY" . debug-roots
check_output 'the relative PWT_REPO_ROOT error names the absolute-path requirement' \
  'absolute' pwt_with_root "$PRIMARY" . debug-roots

check_fails 'PWT_REPO_ROOT rejects a missing path' \
  pwt_with_root "$PRIMARY" "$TMP/missing-primary" debug-roots
check_output 'the missing PWT_REPO_ROOT error names the missing directory' \
  'must name an existing directory' pwt_with_root "$PRIMARY" "$TMP/missing-primary" debug-roots

check_fails 'PWT_REPO_ROOT rejects a linked worktree' \
  pwt_with_root "$PRIMARY" "$WORKTREE" debug-roots
check_output 'the linked-worktree PWT_REPO_ROOT error names the primary checkout' \
  'primary checkout' pwt_with_root "$PRIMARY" "$WORKTREE" debug-roots

check_fails 'PWT_REPO_ROOT rejects a different repository' \
  pwt_with_root "$PRIMARY" "$WRONG" debug-roots
check_output 'the wrong-repository PWT_REPO_ROOT error names the repository mismatch' \
  'current repository' pwt_with_root "$PRIMARY" "$WRONG" debug-roots

# ------------------------------------------------- hostile remote URLs

section 'remote URL cannot escape the managed root'

# owner/repo become filesystem path segments, so remote identity is untrusted
# input. This is ported from the cwt suite and also pins the rule that errors do
# not echo credential-bearing remote URLs.
probe_remote() {
  (cd "$PRIMARY" && git remote set-url origin "$1" && "$PWT" debug-roots 2>&1)
}

for hostile in \
  'https://host/../..' \
  'https://host/owner/..' \
  'git@host:../../etc' \
  'https://host/ow ner/repo' \
  'https://host/owner/re;po' \
  'https://host/owner/$(touch pwned)'; do
  hostile_output=$(probe_remote "$hostile" || true)
  hostile_root=$(root_value "$hostile_output" managed_root)
  if [ -z "$hostile_root" ]; then
    ok "a hostile remote is rejected: $hostile"
  else
    not_ok "a hostile remote reaches managed-root construction: $hostile ($hostile_root)"
  fi
done

check 'no side effect ran from a command-substitution remote' \
  test ! -e "$PRIMARY/pwned"

credentialed_output=$(probe_remote 'https://user:supersecret@host/owner/re;po' || true)
check_not_contains 'a malformed credentialed remote is not echoed in an error' \
  'user:supersecret' "$credentialed_output"
check_contains 'a malformed credentialed remote still gives a useful error' \
  'cannot derive repository from origin remote' "$credentialed_output"

(cd "$PRIMARY" && git remote set-url origin "$REMOTE")

# ------------------------------------------------------------------ launching

section 'launch'

launch_reset() {
  : >"$PWT_TEST_LOG"
  rm -rf "$PWT_TEST_ARGS_DIR"
  mkdir -p "$PWT_TEST_ARGS_DIR"
}
launched() { sed -n "s/^$1=//p" "$PWT_TEST_LOG" | tail -1; }
check_arg_equals() {
  local label=$1 index=$2 expected=$3 expected_file="$TMP/expected-arg"
  printf '%s' "$expected" >"$expected_file"
  if [ -f "$PWT_TEST_ARGS_DIR/$index" ] && cmp -s "$expected_file" "$PWT_TEST_ARGS_DIR/$index"; then
    ok "$label"
  else
    not_ok "$label"
  fi
}

launch_reset
pwt root >/dev/null 2>&1
check_equals 'root launches pi from the physical primary checkout' "$PRIMARY" "$(launched pwd)"
check_equals 'root exports PWT_REPO_ROOT equal to the physical primary checkout' \
  "$PRIMARY" "$(launched PWT_REPO_ROOT)"
check_equals 'root passes no arguments to pi by default' '0' "$(launched argc)"

# Invoked from a linked worktree, root must still enter the primary checkout.
launch_reset
pwt_in "$WORKTREE" root >/dev/null 2>&1
check_equals 'root launches in the primary checkout when invoked from a worktree' \
  "$PRIMARY" "$(launched pwd)"
check_equals 'the worktree launch exports the physical primary checkout' \
  "$PRIMARY" "$(launched PWT_REPO_ROOT)"

# Each forwarded value is compared as file content so spaces, empties, and
# embedded newlines cannot be flattened by the fixture or assertion.
launch_reset
pwt root -- --model 'space value' '' $'line\nbreak' '--flag=value' >/dev/null 2>&1
check_equals 'normal launch preserves the forwarded argument count' '5' "$(launched argc)"
check_arg_equals 'normal launch preserves option arguments' 0 '--model'
check_arg_equals 'normal launch preserves spaces inside one argument' 1 'space value'
check_arg_equals 'normal launch preserves an empty argument' 2 ''
check_arg_equals 'normal launch preserves embedded newlines' 3 $'line\nbreak'
check_arg_equals 'normal launch preserves equals-form arguments' 4 '--flag=value'

launch_reset
check_fails 'an unknown pwt-side flag fails before pi launches' pwt root --yolo
check_equals 'an unknown pwt-side flag does not launch pi' '' "$(launched pwd)"
check_output 'the unknown pwt-side flag is named in the error' 'yolo' pwt root --yolo
check_fails 'root rejects a positional argument' pwt root somebranch

# A relative PATH entry resolves a different Pi before pwt changes cwd. If pwt
# performs a second PATH lookup after cd, the ordinary $BIN/pi stub wins instead.
RESOLVE_FROM="$WORKTREE/nested"
mkdir -p "$RESOLVE_FROM/relative-bin"
cat >"$RESOLVE_FROM/relative-bin/pi" <<'STUB'
#!/usr/bin/env bash
export PWT_PI_SELECTED=before-cd
exec "$PWT_TEST_PI_STUB" "$@"
STUB
chmod +x "$RESOLVE_FROM/relative-bin/pi"

launch_reset
(cd "$RESOLVE_FROM" && PATH="relative-bin:$PATH" "$PWT" root >/dev/null 2>&1)
check_equals 'the Pi executable is resolved before the launch cwd changes' \
  'before-cd' "$(launched selected)"
check_equals 'the pre-resolved Pi executable still launches from the physical primary checkout' \
  "$PRIMARY" "$(launched pwd)"

# -------------------------------------------------------------------- summary

section "results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
