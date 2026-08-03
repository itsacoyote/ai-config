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

# The remote's default branch moves to `stable` *after* the clone, leaving
# origin/HEAD in the clone pointing at the old default. Task 3 needs exactly this:
# `clwt new` must base on the branch origin considers default *now*, not the one
# cached at clone time. Borrowed from the pwt suite, which had the same fixture.
(
  cd "$TMP/seed"
  git checkout -q -b stable
  printf 'stable\n' >stable.txt
  git add stable.txt
  git commit -qm 'add stable branch'
  git push -q origin stable
)
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/stable

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

section 'harness fixtures'
# Guard the fixture itself: if this stops being stale, task 3's "bases on the
# current origin default" test would pass for the wrong reason.
check_equals 'the clone origin/HEAD is stale relative to the remote default' \
  'refs/heads/main|stable' \
  "$(git -C "$PRIMARY" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/|refs/heads/|')|$(git -C "$PRIMARY" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^\t ]*\).*|\1|p')"

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

# ------------------------------------------------- hostile remote URLs

section 'remote URL cannot escape the managed root'

# owner/repo become path segments under ~/github/.worktrees, so a remote URL is
# untrusted input on a filesystem path. Assert that nothing derived from one can
# point outside the managed root.
probe_remote() {
  (cd "$PRIMARY" && git remote set-url origin "$1" && "$CLWT" debug-roots 2>&1)
}

for hostile in \
  'https://host/../..' \
  'https://host/owner/..' \
  'git@host:../../etc' \
  'https://host/ow ner/repo' \
  'https://host/owner/re;po' \
  'https://host/owner/$(touch pwned)'; do
  out=$(probe_remote "$hostile" || true)
  root=$(printf '%s\n' "$out" | sed -n 's/^managed_root=//p')
  case $root in
    '')
      ok "a hostile remote is rejected: $hostile"
      ;;
    "$HOME/github/.worktrees/"*/*)
      # Accepted, but it must still be confined and contain no traversal.
      case $root in
        *..*) not_ok "a hostile remote escapes the managed root: $hostile ($root)" ;;
        *) ok "a hostile remote stays confined: $hostile" ;;
      esac
      ;;
    *)
      not_ok "a hostile remote escapes the managed root: $hostile ($root)"
      ;;
  esac
done

check 'no side effect ran from a command-substitution remote' \
  test ! -e "$PRIMARY/pwned"

(cd "$PRIMARY" && git remote set-url origin "$REMOTE")

# ----------------------------------------------------------------------- list

section 'list'

# A managed worktree (created by hand here — clwt new arrives in task 3) and an
# unmanaged one outside the managed root.
git -C "$PRIMARY" worktree add -q -b feat/listed "$MANAGED/feat-listed" 2>/dev/null
UNMANAGED="$HOME/elsewhere/stray"
mkdir -p "$HOME/elsewhere"
git -C "$PRIMARY" worktree add -q -b feat/stray "$UNMANAGED" 2>/dev/null

check_output 'list shows a managed worktree by branch name' 'feat/listed' clwt list
check_output 'list shows the managed worktree path' "$MANAGED/feat-listed" clwt list
check_output 'list marks a worktree outside the managed root as unmanaged' 'unmanaged' clwt list
check_output 'list shows the unmanaged branch too' 'feat/stray' clwt list

bare_out=$(clwt 2>&1)
list_out=$(clwt list 2>&1)
check_equals 'clwt with no arguments prints the worktree list' "$list_out" "$bare_out"

check_fails 'list rejects extra arguments' clwt list nonsense

# The primary checkout is a worktree in git's eyes; it must not be offered as
# something clwt manages.
if clwt list 2>&1 | grep -qF "$PRIMARY "; then
  not_ok 'list does not present the primary checkout as a managed worktree'
else
  ok 'list does not present the primary checkout as a managed worktree'
fi

# Empty state, in a repo with no worktrees of its own.
git clone -q "$REMOTE" "$HOME/github/owner/lonely"
check_output 'list reports plainly when there are no managed worktrees' \
  'No managed worktrees' clwt_in "$HOME/github/owner/lonely" list

# ------------------------------------------------------------------ launching

section 'launch primitive, root, and --yolo'

# The stub `claude` records the working directory and environment it was handed.
# Reading those back is the only honest way to assert the thing this tool exists
# for: that the launched process really is rooted in the target directory.
launch_reset() { : >"$CLWT_TEST_LOG"; }
launched() { sed -n "s/^$1=//p" "$CLWT_TEST_LOG" | tail -1; }

launch_reset
clwt root >/dev/null 2>&1
check_equals 'root launches claude in the primary checkout' "$PRIMARY" "$(launched pwd)"
check_equals 'root exports CLWT_REPO_ROOT equal to the primary checkout' \
  "$PRIMARY" "$(launched CLWT_REPO_ROOT)"

root_env=$(launched CLWT_REPO_ROOT)
case $root_env in
  *.git) not_ok 'the exported CLWT_REPO_ROOT does not end in .git' ;;
  *) ok 'the exported CLWT_REPO_ROOT does not end in .git' ;;
esac
check_equals 'root passes no arguments to claude by default' '' "$(launched args)"

# Invoked from inside a worktree, root must still land in the primary checkout —
# the case `git rev-parse --show-toplevel` gets wrong.
launch_reset
clwt_in "$MANAGED/feat-listed" root >/dev/null 2>&1
check_equals 'root launches in the primary checkout even when invoked from a worktree' \
  "$PRIMARY" "$(launched pwd)"
check_equals 'CLWT_REPO_ROOT is correct when clwt is invoked from inside a worktree' \
  "$PRIMARY" "$(launched CLWT_REPO_ROOT)"

# --yolo
launch_reset
clwt root --yolo >/dev/null 2>&1
check_equals '--yolo passes --dangerously-skip-permissions to claude' \
  '--dangerously-skip-permissions' "$(launched args)"

launch_reset
clwt root >/dev/null 2>&1
check_equals 'without --yolo no permission flag is passed to claude' '' "$(launched args)"

launch_reset
clwt root --yolo -- --model opus >/dev/null 2>&1
check_equals '--yolo composes with arguments after --' \
  '--dangerously-skip-permissions --model opus' "$(launched args)"

launch_reset
clwt root -- --model opus >/dev/null 2>&1
check_equals 'arguments after -- are passed through to claude' \
  '--model opus' "$(launched args)"

launch_reset
clwt root -- >/dev/null 2>&1
check_equals 'a bare -- with no following arguments is not an error' \
  "$PRIMARY" "$(launched pwd)"

check_fails 'an unknown clwt-side flag is rejected rather than silently forwarded' \
  clwt root --yolol
check_output 'an unknown clwt-side flag is named in the error' 'yolol' clwt root --yolol
check_fails 'root rejects a positional argument' clwt root somebranch

section 'open'

# feat/listed already has a managed worktree at $MANAGED/feat-listed, and
# feat/stray has an unmanaged one at $UNMANAGED (both created in the list section).
launch_reset
clwt open feat/listed >/dev/null 2>&1
check_equals 'open launches claude with the worktree as its working directory' \
  "$MANAGED/feat-listed" "$(launched pwd)"
check_equals 'open exports CLWT_REPO_ROOT set to the primary checkout' \
  "$PRIMARY" "$(launched CLWT_REPO_ROOT)"

launch_reset
clwt open feat/listed --yolo >/dev/null 2>&1
check_equals '--yolo works on open as well as root' \
  '--dangerously-skip-permissions' "$(launched args)"

check_fails 'open refuses a worktree outside the managed root' clwt open feat/stray
check_output 'open explains that the worktree is outside the managed root' \
  'managed' clwt open feat/stray

check_fails 'open exits non-zero when the branch has no managed worktree' \
  clwt open feat/never-existed
check_output 'open names the branch it could not find' \
  'feat/never-existed' clwt open feat/never-existed

check_fails 'open requires a branch argument' clwt open
check_fails 'open rejects an invalid branch name' clwt open 'not a branch'

# A symlink pointing into the managed root must not be accepted as a managed
# worktree — otherwise the containment check can be walked around.
SYMLINKED="$MANAGED/symlinked"
ln -s "$UNMANAGED" "$SYMLINKED"
git -C "$PRIMARY" worktree add -q -b feat/symlinked "$MANAGED/feat-symlinked" 2>/dev/null
rm -rf "$MANAGED/feat-symlinked"
ln -s "$UNMANAGED" "$MANAGED/feat-symlinked"
check_fails 'open refuses a symlinked worktree path' clwt open feat/symlinked
rm -f "$SYMLINKED" "$MANAGED/feat-symlinked"

section 'new'

launch_reset
clwt new feat/alpha >/dev/null 2>&1
check 'new creates a managed worktree' test -d "$MANAGED/feat-alpha"
check_equals 'new names the worktree from the branch with slashes as dashes' \
  "$MANAGED/feat-alpha" "$(launched pwd)"
if git -C "$PRIMARY" worktree list --porcelain | grep -qF "$MANAGED/feat-alpha"; then
  ok 'new registers the new worktree with git'
else
  not_ok 'new registers the new worktree with git'
fi

# The fixture moved the remote default to `stable` after the clone, so origin/HEAD
# in the clone still says `main`. stable.txt exists only on `stable` — its presence
# proves clwt asked the remote what its default is *now* rather than trusting the
# cached ref.
check 'new bases the new branch on the current origin default branch' \
  test -f "$MANAGED/feat-alpha/stable.txt"

check_equals 'new launches claude in the worktree it created' \
  "$MANAGED/feat-alpha" "$(launched pwd)"

launch_reset
clwt new feat/beta --yolo >/dev/null 2>&1
check_equals '--yolo works on new' \
  '--dangerously-skip-permissions' "$(launched args)"

# Branch-name validation. These become directory names, so they are untrusted
# input on a filesystem path.
check_fails 'new rejects a branch name without a type prefix' clwt new nomprefix
check_output 'new explains that a type prefix is required' 'feat/' clwt new noprefix
check_fails 'new rejects a branch name failing git check-ref-format' clwt new 'feat/bad..name'
check_fails 'new rejects a path-traversing branch name' clwt new '../evil'
check_fails 'new rejects a deeper path-traversing branch name' clwt new 'feat/../../evil'
check_fails 'new rejects a branch name containing whitespace' clwt new 'feat/a b'
check_fails 'new requires a branch argument' clwt new

check 'no traversal escaped the managed root' test ! -e "$HOME/github/.worktrees/owner/evil"
check 'no traversal escaped to the home directory' test ! -e "$HOME/evil"

# A directory squatting on the target path produces a confusing failure from
# `git worktree add`; clwt should catch it first.
mkdir -p "$MANAGED/feat-occupied"
check_fails 'new refuses when the target path exists but is not a registered worktree' \
  clwt new feat/occupied
check_output 'new explains that the target path is occupied' \
  'exists' clwt new feat/occupied
rmdir "$MANAGED/feat-occupied"

# An existing local branch that is not checked out anywhere is `branch`'s job.
git -C "$PRIMARY" branch feat/dormant >/dev/null 2>&1
check_fails 'new fails when the local branch already exists but is unchecked out' \
  clwt new feat/dormant
check_output 'new points at clwt branch when the local branch already exists' \
  'clwt branch' clwt new feat/dormant

# -------------------------------------------------------------------- install

section 'install'

LOCAL_BIN="$HOME/.local/bin"

reset_install() { rm -rf "$LOCAL_BIN"; }

# Fresh install into a directory that does not exist yet.
reset_install
export PATH="$LOCAL_BIN:$PATH"
check 'install succeeds when ~/.local/bin does not exist' clwt install
check 'install creates the ~/.local/bin directory' test -d "$LOCAL_BIN"
check 'install creates a symlink at ~/.local/bin/clwt' test -L "$LOCAL_BIN/clwt"
check_equals 'the installed symlink points at the repo script' \
  "$CLWT" "$(readlink "$LOCAL_BIN/clwt" 2>/dev/null)"

# Idempotence.
check 'install is idempotent when the correct symlink already exists' clwt install
check_output 'install says it is already installed on a repeat run' 'already' clwt install

# Refuses to clobber a real file.
reset_install
mkdir -p "$LOCAL_BIN"
printf 'not a symlink\n' >"$LOCAL_BIN/clwt"
check_fails 'install refuses to clobber an existing non-symlink file' clwt install
check_output 'install explains why it refused to clobber' 'not a symlink' clwt install
check 'the pre-existing file survives a refused install' \
  grep -q 'not a symlink' "$LOCAL_BIN/clwt"

# Repoints a symlink that aims somewhere else.
rm -f "$LOCAL_BIN/clwt"
ln -s "$TMP/some-other-clwt" "$LOCAL_BIN/clwt"
check 'install repoints a symlink that aims elsewhere' clwt install
check_equals 'the repointed symlink now targets the repo script' \
  "$CLWT" "$(readlink "$LOCAL_BIN/clwt" 2>/dev/null)"

# Warns when the install directory is not on PATH.
reset_install
off_path_out=$(PATH="$BIN:/usr/bin:/bin" clwt install 2>&1)
if printf '%s\n' "$off_path_out" | grep -qF 'PATH'; then
  ok 'install warns when ~/.local/bin is not on PATH'
else
  not_ok 'install warns when ~/.local/bin is not on PATH'
fi

# Invoked *through* the installed symlink, install must resolve back to the repo
# script rather than to itself.
reset_install
clwt install >/dev/null 2>&1
via_symlink=$("$LOCAL_BIN/clwt" install 2>&1)
check_equals 'install through the installed symlink still targets the repo script' \
  "$CLWT" "$(readlink "$LOCAL_BIN/clwt" 2>/dev/null)"
check 'install through the installed symlink succeeds' \
  test -L "$LOCAL_BIN/clwt"

# install must work outside a git repository — it has nothing to do with a repo.
check 'install works outside a git repository' clwt_in "$TMP/not-a-repo" install

# -------------------------------------------------------------------- summary

section "results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
