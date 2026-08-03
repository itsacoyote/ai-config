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

# HOME is deliberately left UNRESOLVED here. Pre-resolving it hid a real bug:
# managed_root was built from a raw $HOME while every path compared against it was
# pwd -P'd, so on a symlinked home clwt disowned the worktrees it had just made.
# The sandbox home is reached through a symlink below to keep that exposed.
mkdir -p "$TMP/real-home"
ln -s "$TMP/real-home" "$HOME"
export HOME

REMOTE="$HOME/remotes/owner/project.git"
PRIMARY="$HOME/github/owner/project"
MANAGED="$HOME/github/.worktrees/owner/project"
BIN="$HOME/bin"
mkdir -p "$REMOTE" "$HOME/github/owner" "$BIN"

# ~/github/.worktrees is itself a symlink to somewhere else entirely — relocating
# worktrees to another volume is an ordinary thing to do. Combined with the
# symlinked $HOME above, this means clwt must resolve the *whole* managed-root
# path, not just its first component. Assertions compare against the resolved
# path; that asymmetry is the regression test. Leave it this way.
mkdir -p "$TMP/other-volume/worktrees/owner/project"
mkdir -p "$HOME/github"
ln -s "$TMP/other-volume/worktrees" "$HOME/github/.worktrees"
MANAGED=$(cd "$MANAGED" && pwd -P)

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
#
# PR state per branch comes from $CLWT_GH_STATES/<branch with / as ->. A missing
# file means "no pull request for this branch", which `gh` signals with a non-zero
# exit — the *same* signal as "gh is broken". Keeping that ambiguity faithful is
# the point: it is what the implementation has to disambiguate.
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
if [ -f "$CLWT_GH_UNAVAILABLE" ]; then
  echo "gh: could not authenticate" >&2
  exit 1
fi
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case "$*" in
    *headRefName*)
      # `clwt pr` asking for a pull request's metadata by number.
      meta="$CLWT_GH_PRS/$3"
      if [ ! -f "$meta" ]; then
        echo "could not resolve to a pull request with the number of $3" >&2
        exit 1
      fi
      sed -n 's/^headRefName=//p' "$meta"
      sed -n 's/^isCrossRepository=//p' "$meta"
      exit 0
      ;;
    *)
      # `clwt prune` asking for a branch's merge state.
      state_file="$CLWT_GH_STATES/$(printf '%s' "$3" | tr '/' '-')"
      if [ ! -f "$state_file" ]; then
        echo "no pull requests found for branch \"$3\"" >&2
        exit 1
      fi
      cat "$state_file"
      exit 0
      ;;
  esac
fi
if [ "$1" = "pr" ] && [ "$2" = "checkout" ]; then
  meta="$CLWT_GH_PRS/$3"
  if [ ! -f "$meta" ]; then
    echo "could not resolve to a pull request with the number of $3" >&2
    exit 1
  fi
  if grep -q '^checkoutFails=true$' "$meta"; then
    # What really happens when a merged PR's head branch has been deleted.
    echo "fatal: couldn't find remote ref" >&2
    exit 1
  fi
  head_ref=$(sed -n 's/^headRefName=//p' "$meta")
  # Real gh checks the PR out into the current working tree; so does this.
  git checkout -q -b "$head_ref" 2>/dev/null || git checkout -q "$head_ref"
  exit 0
fi
exit 0
STUB
chmod +x "$BIN/gh"
export CLWT_GH_UNAVAILABLE="$TMP/gh-unavailable"
export CLWT_GH_STATES="$TMP/gh-states"
export CLWT_GH_PRS="$TMP/gh-prs"
mkdir -p "$CLWT_GH_STATES" "$CLWT_GH_PRS"
pr_state() { printf '%s\n' "$2" >"$CLWT_GH_STATES/$(printf '%s' "$1" | tr '/' '-')"; }
pr_meta() {
  printf 'headRefName=%s\nisCrossRepository=%s\n' "$2" "$3" >"$CLWT_GH_PRS/$1"
}

export PATH="$BIN:$PATH"

# Bare remote with a real commit, default branch `main`.
git init -q --bare "$REMOTE"
git init -q "$TMP/seed"
(
  cd "$TMP/seed"
  printf 'seed\n' >README.md
  # A tracked .gitignore covering .env is what makes a *copied* .env register as
  # ignored rather than untracked. Without it the remove tests would exercise the
  # wrong branch of the cleanliness check entirely.
  printf '.env\n' >.gitignore
  git add README.md .gitignore
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
UNMANAGED=$(cd "$UNMANAGED" && pwd -P) # resolved, like every path clwt reports

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
# The link target is a sibling *inside* the managed root: if it pointed outside,
# the containment check would reject it on its own and the symlink guard would
# never decide anything — the test would pass for the wrong reason.
git -C "$PRIMARY" worktree add -q -b feat/symlinked "$MANAGED/feat-symlinked" 2>/dev/null
rm -rf "$MANAGED/feat-symlinked"
ln -s "$MANAGED/feat-listed" "$MANAGED/feat-symlinked"
check_fails 'open refuses a symlinked worktree path inside the managed root' \
  clwt open feat/symlinked
rm -f "$MANAGED/feat-symlinked"

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

section 'branch'

# An existing local branch with no worktree (created in the `new` section).
launch_reset
clwt branch feat/dormant >/dev/null 2>&1
check 'branch creates a managed worktree for an existing local branch' \
  test -d "$MANAGED/feat-dormant"
check_equals 'branch launches claude in that worktree' \
  "$MANAGED/feat-dormant" "$(launched pwd)"

# A branch that exists only on the remote.
(
  cd "$TMP/seed"
  git checkout -q -b feat/remote-only
  printf 'remote only\n' >remote-only.txt
  git add remote-only.txt
  git commit -qm 'remote only branch'
  git push -q origin feat/remote-only
)
launch_reset
clwt branch feat/remote-only >/dev/null 2>&1
check 'branch checks out a branch that exists only on origin' \
  test -f "$MANAGED/feat-remote-only/remote-only.txt"
check_equals 'branch launches claude in the origin-only worktree' \
  "$MANAGED/feat-remote-only" "$(launched pwd)"

check_fails 'branch fails for a branch that exists nowhere' clwt branch feat/nonexistent
check_output 'branch names the branch it could not find' \
  'feat/nonexistent' clwt branch feat/nonexistent
check_fails 'branch requires a branch argument' clwt branch
check_fails 'branch rejects an invalid branch name' clwt branch 'feat/a b'

section 'already checked out elsewhere'

# Case (a): already in a managed worktree — reuse it and launch.
launch_reset
clwt branch feat/alpha >/dev/null 2>&1
check_equals 'branch reuses an existing managed worktree rather than failing' \
  "$MANAGED/feat-alpha" "$(launched pwd)"
launch_reset
clwt new feat/alpha >/dev/null 2>&1
check_equals 'new also reuses an existing managed worktree' \
  "$MANAGED/feat-alpha" "$(launched pwd)"

# Case (b): checked out in the primary checkout. `git worktree add` would refuse
# with "already checked out"; clwt should say something more useful.
primary_branch=$(git -C "$PRIMARY" symbolic-ref --short HEAD)
check_fails 'branch refuses when the branch is checked out in the primary checkout' \
  clwt branch "$primary_branch"
check_output 'that refusal names the primary checkout' \
  "$PRIMARY" clwt branch "$primary_branch"
check_output 'that refusal suggests clwt root' \
  'clwt root' clwt branch "$primary_branch"

# Case (c): checked out in an unmanaged worktree.
check_fails 'branch refuses when the branch is checked out in an unmanaged worktree' \
  clwt branch feat/stray
check_output 'that refusal names the unmanaged path' "$UNMANAGED" clwt branch feat/stray
check_output 'that refusal says clwt does not manage it' 'manage' clwt branch feat/stray

# The three cases must be distinguishable, not one generic message.
msg_primary=$(clwt branch "$primary_branch" 2>&1 || true)
msg_unmanaged=$(clwt branch feat/stray 2>&1 || true)
if [ "$msg_primary" != "$msg_unmanaged" ]; then
  ok 'the primary-checkout and unmanaged refusals are distinct messages'
else
  not_ok 'the primary-checkout and unmanaged refusals are distinct messages'
fi

section 'worktreeinclude copy'

# Nothing configured yet: creation must be a no-op, not an error.
launch_reset
clwt new feat/no-include >/dev/null 2>&1
check 'creation succeeds when worktreeinclude is absent' test -d "$MANAGED/feat-no-include"

printf '# nothing matches this\nnever-matches-anything\n' >"$PRIMARY/.worktreeinclude"
launch_reset
clwt new feat/empty-include >/dev/null 2>&1
check 'creation succeeds when worktreeinclude matches nothing' \
  test -d "$MANAGED/feat-empty-include"

# Now with real patterns and real untracked files.
mkdir -p "$PRIMARY/config"
printf 'SECRET=1\n' >"$PRIMARY/.env"
printf '{"local":true}\n' >"$PRIMARY/config/local.json"
printf 'spaced\n' >"$PRIMARY/with space.txt"
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
config/local.json
with space.txt
PATTERNS

launch_reset
copy_out=$(clwt new feat/copied 2>&1)
check 'a worktreeinclude match is copied into the new worktree' \
  test -f "$MANAGED/feat-copied/.env"
check 'a nested worktreeinclude match keeps its relative path' \
  test -f "$MANAGED/feat-copied/config/local.json"
check 'a worktreeinclude match whose filename contains a space is copied' \
  test -f "$MANAGED/feat-copied/with space.txt"
if printf '%s\n' "$copy_out" | grep -qE 'copied 3'; then
  ok 'copying reports the number of files copied'
else
  not_ok "copying reports the number of files copied (got: $(printf '%s' "$copy_out" | tr '\n' '|'))"
fi
check_equals 'the copied file has the same contents as the original' \
  'SECRET=1' "$(cat "$MANAGED/feat-copied/.env" 2>/dev/null)"

# The guard this whole task exists for. `git ls-files --others --ignored
# --exclude-from` DOES return gitignored paths — verified — so a .beads entry
# here would otherwise be copied, forking the issue database exactly as it did
# before PR #48.
mkdir -p "$PRIMARY/.beads/backup"
printf '{"id":"x"}\n' >"$PRIMARY/.beads/issues.jsonl"
printf 'blob\n' >"$PRIMARY/.beads/backup/snap.darc"
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
.beads/
PATTERNS

launch_reset
beads_out=$(clwt new feat/beads-guard 2>&1)
check 'the beads directory is never copied even when worktreeinclude matches it' \
  test ! -e "$MANAGED/feat-beads-guard/.beads"
check 'no file under the beads directory is copied either' \
  test ! -e "$MANAGED/feat-beads-guard/.beads/issues.jsonl"
check 'the non-beads match is still copied alongside the refusal' \
  test -f "$MANAGED/feat-beads-guard/.env"
if printf '%s\n' "$beads_out" | grep -qF '#48'; then
  ok 'skipping the beads directory prints a warning naming PR 48'
else
  not_ok 'skipping the beads directory prints a warning naming PR 48'
fi

# --exclude-from resolves relative to the current directory, and clwt is often
# run from inside a worktree. The pattern file and the copy source must both come
# from the primary checkout regardless of where clwt was invoked.
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
PATTERNS
launch_reset
clwt_in "$MANAGED/feat-alpha" new feat/from-inside >/dev/null 2>&1
check 'worktreeinclude is read from the primary checkout when clwt runs inside a worktree' \
  test -f "$MANAGED/feat-from-inside/.env"

# branch must run the copy too, not just new.
git -C "$PRIMARY" branch feat/copy-on-branch >/dev/null 2>&1
launch_reset
clwt branch feat/copy-on-branch >/dev/null 2>&1
check 'branch also copies worktreeinclude matches' \
  test -f "$MANAGED/feat-copy-on-branch/.env"

# A failing copy must abort and clean up, not report success with a count that
# includes the file it never copied. An unreadable source is the simplest way to
# make `cp` fail; root ignores the mode, so skip there rather than assert falsely.
if [ "$(id -u)" -ne 0 ]; then
  printf 'nope\n' >"$PRIMARY/unreadable.txt"
  chmod 000 "$PRIMARY/unreadable.txt"
  cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
unreadable.txt
PATTERNS

  launch_reset
  copyfail_out=$(clwt new feat/copy-fails 2>&1 || true)

  check_equals 'a failed copy does not launch claude' '' "$(launched pwd)"
  check 'a failed copy leaves no worktree behind' test ! -e "$MANAGED/feat-copy-fails"
  if git -C "$PRIMARY" worktree list --porcelain | grep -qF 'feat-copy-fails'; then
    not_ok 'a failed copy unregisters the worktree it made'
  else
    ok 'a failed copy unregisters the worktree it made'
  fi
  if printf '%s\n' "$copyfail_out" | grep -qiF 'cannot copy'; then
    ok 'a failed copy says which file it could not copy'
  else
    not_ok "a failed copy says which file it could not copy (got: $(printf '%s' "$copyfail_out" | tr '\n' '|'))"
  fi
  if printf '%s\n' "$copyfail_out" | grep -qE 'copied [0-9]+ file'; then
    not_ok 'a failed copy does not report a success count'
  else
    ok 'a failed copy does not report a success count'
  fi

  chmod 644 "$PRIMARY/unreadable.txt"
  rm -f "$PRIMARY/unreadable.txt"
else
  ok 'copy-failure assertions skipped (running as root; mode bits do not apply)'
fi

rm -f "$PRIMARY/.worktreeinclude"

section 'remove'

# Clean worktree: removed, branch kept.
launch_reset
clwt new feat/removable >/dev/null 2>&1
check 'the worktree to remove exists first' test -d "$MANAGED/feat-removable"
check 'remove deletes a clean managed worktree' clwt remove feat/removable
check 'the worktree directory is gone' test ! -d "$MANAGED/feat-removable"
check 'remove keeps the branch by default' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/removable

# --delete-branch
launch_reset
clwt new feat/disposable >/dev/null 2>&1
check 'remove --delete-branch succeeds' clwt remove feat/disposable --delete-branch
check_fails 'remove --delete-branch deletes the branch as well' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/disposable

# Uncommitted work blocks removal.
launch_reset
clwt new feat/dirty-tracked >/dev/null 2>&1
printf 'edited\n' >>"$MANAGED/feat-dirty-tracked/README.md"
check_fails 'remove refuses a worktree with uncommitted changes' clwt remove feat/dirty-tracked
check 'the refused worktree still exists' test -d "$MANAGED/feat-dirty-tracked"

# An untracked file is real work too, and plain --porcelain would miss it only
# with -uno; --untracked-files=all is what catches it.
launch_reset
clwt new feat/dirty-untracked >/dev/null 2>&1
printf 'scratch\n' >"$MANAGED/feat-dirty-untracked/notes.md"
check_fails 'remove refuses a worktree with an untracked file' clwt remove feat/dirty-untracked

# The HIGH-1 case. .env is gitignored, so a worktree holding a copied one is
# *ignored*-dirty but not actually dirty. It must be removable — otherwise every
# worktree clwt creates becomes unremovable — and the destruction must be named.
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
PATTERNS
printf 'SECRET=1\n' >"$PRIMARY/.env"
launch_reset
clwt new feat/has-ignored >/dev/null 2>&1
check 'the ignored file was copied in' test -f "$MANAGED/feat-has-ignored/.env"

ignored_status=$(cd "$MANAGED/feat-has-ignored" && git status --porcelain --untracked-files=all)
check_equals 'the copied ignored file does not register as untracked work' '' "$ignored_status"

remove_out=$(clwt remove feat/has-ignored 2>&1)
check 'remove succeeds on a worktree containing a copied worktreeinclude file' \
  test ! -d "$MANAGED/feat-has-ignored"
if printf '%s\n' "$remove_out" | grep -qF '.env'; then
  ok 'remove names the ignored files it is about to destroy'
else
  not_ok "remove names the ignored files it is about to destroy (got: $(printf '%s' "$remove_out" | tr '\n' '|'))"
fi
rm -f "$PRIMARY/.worktreeinclude"

# Standing inside the worktree you are removing.
launch_reset
clwt new feat/self-remove >/dev/null 2>&1
check_fails 'remove refuses the worktree containing the caller working directory' \
  clwt_in "$MANAGED/feat-self-remove" remove feat/self-remove
check 'the worktree survives a refused self-removal' test -d "$MANAGED/feat-self-remove"
check_output 'the self-removal refusal explains itself' \
  'standing in' clwt_in "$MANAGED/feat-self-remove" remove feat/self-remove
check 'removing it from elsewhere still works' clwt remove feat/self-remove

# Guards inherited from the managed-root contract.
check_fails 'remove refuses a worktree outside the managed root' clwt remove feat/stray
check 'the unmanaged worktree survives' test -d "$UNMANAGED"
check_fails 'remove fails for a branch with no worktree' clwt remove feat/never-existed
check_fails 'remove requires a branch name' clwt remove
check_fails 'remove rejects an unknown flag' clwt remove feat/listed --nope

# A failing git must never be read as "clean" or as "nothing will be destroyed" —
# both mistakes delete things. There was previously no coverage here at all, which
# is how a guard that could never fire shipped with the suite fully green.
#
# The stub git forwards everything except the one subcommand under test, so only
# that call fails and the rest of clwt still works.
FAILGIT="$TMP/failgit"
mkdir -p "$FAILGIT"
make_failing_git() {
  cat >"$FAILGIT/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "$1" ]; then
    echo "fatal: simulated git failure" >&2
    exit 128
  fi
done
exec $(command -v git) "\$@"
STUB
  chmod +x "$FAILGIT/git"
}

launch_reset
clwt new feat/failing-git >/dev/null 2>&1
printf 'SECRET=1\n' >"$MANAGED/feat-failing-git/.env"

make_failing_git 'ls-files'
out=$(PATH="$FAILGIT:$PATH" clwt remove feat/failing-git 2>&1 || true)
check 'remove refuses when git cannot list ignored files' \
  test -d "$MANAGED/feat-failing-git"
if printf '%s\n' "$out" | grep -qiF 'refusing to remove'; then
  ok 'remove says why it refused when git failed'
else
  not_ok "remove says why it refused when git failed (got: $(printf '%s' "$out" | tr '\n' '|'))"
fi
check_fails 'remove exits non-zero when git cannot list ignored files' \
  env PATH="$FAILGIT:$PATH" "$CLWT" remove feat/failing-git

make_failing_git 'status'
check 'remove refuses when git cannot report status' \
  test -d "$MANAGED/feat-failing-git"
check_fails 'remove exits non-zero when git status fails' \
  env PATH="$FAILGIT:$PATH" "$CLWT" remove feat/failing-git
rm -f "$FAILGIT/git"

check 'the worktree survives every simulated git failure' \
  test -f "$MANAGED/feat-failing-git/.env"
clwt remove feat/failing-git >/dev/null 2>&1

section 'prune'

# Four worktrees covering every state that decides candidacy, plus one that is
# merged-but-dirty.
launch_reset
for b in merged-a still-open no-pr closed-unmerged merged-dirty; do
  clwt new "feat/$b" >/dev/null 2>&1
done
pr_state feat/merged-a MERGED
pr_state feat/still-open OPEN
pr_state feat/closed-unmerged CLOSED
pr_state feat/merged-dirty MERGED
# feat/no-pr deliberately has no state file at all.
printf 'wip\n' >"$MANAGED/feat-merged-dirty/wip.txt"

dry=$(clwt prune 2>&1)

check 'prune without --yes removes nothing' test -d "$MANAGED/feat-merged-a"
if printf '%s\n' "$dry" | grep -qF 'feat/merged-a'; then
  ok 'prune without --yes lists the merged candidate'
else
  not_ok 'prune without --yes lists the merged candidate'
fi

# Only the block after "would remove" is the candidate list; everything before it
# is the left-alone report, which prints in the same shape. Scoping matters — a
# naive grep over the whole output matches the explanation and reads as a failure.
candidates=$(printf '%s\n' "$dry" | sed -n '/would remove/,$p')
left_alone=$(printf '%s\n' "$dry" | sed -n '1,/would remove/p')

for pair in "still-open:still open" "no-pr:no pull request" "closed-unmerged:closed but unmerged" "merged-dirty:merged but dirty"; do
  b=${pair%%:*}
  why=${pair#*:}
  if printf '%s\n' "$candidates" | grep -qF "feat/$b"; then
    not_ok "prune never lists a worktree that is $why (feat/$b)"
  else
    ok "prune never lists a worktree that is $why (feat/$b)"
  fi
  if printf '%s\n' "$left_alone" | grep -qF "feat/$b"; then
    ok "prune explains why it left feat/$b alone"
  else
    not_ok "prune explains why it left feat/$b alone"
  fi
done

# Applying removes exactly the candidate, and nothing else.
clwt prune --yes >/dev/null 2>&1
check 'prune --yes removes the merged and clean worktree' test ! -d "$MANAGED/feat-merged-a"
check 'prune --yes leaves the still-open worktree' test -d "$MANAGED/feat-still-open"
check 'prune --yes leaves the worktree with no pull request' test -d "$MANAGED/feat-no-pr"
check 'prune --yes leaves the closed-but-unmerged worktree' test -d "$MANAGED/feat-closed-unmerged"
check 'prune --yes leaves the merged-but-dirty worktree' test -d "$MANAGED/feat-merged-dirty"
check 'prune --yes keeps the branch of what it removed' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/merged-a

# Standing inside a worktree that would otherwise be a candidate.
launch_reset
clwt new feat/merged-self >/dev/null 2>&1
pr_state feat/merged-self MERGED
clwt_in "$MANAGED/feat-merged-self" prune --yes >/dev/null 2>&1
check 'prune never removes the worktree containing the caller working directory' \
  test -d "$MANAGED/feat-merged-self"
check 'prune removes it once the caller is elsewhere' clwt prune --yes
check 'the self-standing worktree is gone afterwards' test ! -d "$MANAGED/feat-merged-self"

# gh unavailable must be loud, not a silent "nothing to prune".
touch "$CLWT_GH_UNAVAILABLE"
launch_reset
clwt new feat/merged-b >/dev/null 2>&1
pr_state feat/merged-b MERGED
check_fails 'prune exits non-zero when gh is unavailable' clwt prune
check_output 'prune says why it cannot determine merge state' 'prune needs gh' clwt prune
check_fails 'prune --yes also exits non-zero when gh is unavailable' clwt prune --yes
check 'prune removed nothing while gh was unavailable' test -d "$MANAGED/feat-merged-b"
rm -f "$CLWT_GH_UNAVAILABLE"

check_fails 'prune rejects a positional argument' clwt prune something
check_fails 'prune rejects an unknown flag' clwt prune --force

# prune's containment, primary-checkout, and symlink guards were previously
# unreachable: candidacy needs a MERGED state, and only feat/merged-* ever had a
# state file, so every guarded case was filtered out by the *state* check long
# before the guard mattered. Deleting any of the three left the suite green.
# These put each guarded case into the merged-and-clean state — the only state
# from which prune would actually delete — and assert survival.
pr_state feat/stray MERGED
primary_branch_now=$(cd "$PRIMARY" && git symbolic-ref --short HEAD)
pr_state "$primary_branch_now" MERGED

git -C "$PRIMARY" worktree add -q -b feat/link-target "$MANAGED/feat-link-target" 2>/dev/null
git -C "$PRIMARY" worktree add -q -b feat/symlink-prune "$MANAGED/feat-symlink-prune" 2>/dev/null
rm -rf "$MANAGED/feat-symlink-prune"
ln -s "$MANAGED/feat-link-target" "$MANAGED/feat-symlink-prune"
pr_state feat/symlink-prune MERGED

clwt prune --yes >/dev/null 2>&1

check 'prune never removes an unmanaged worktree even when its PR is merged' \
  test -d "$UNMANAGED"
check 'prune never removes the primary checkout even when its branch is merged' \
  test -d "$PRIMARY"
check 'prune never removes a symlinked worktree path even when its PR is merged' \
  test -L "$MANAGED/feat-symlink-prune"
check 'the symlink target survives too' test -d "$MANAGED/feat-link-target"

rm -f "$MANAGED/feat-symlink-prune"
rm -f "$CLWT_GH_STATES/feat-stray" "$CLWT_GH_STATES/feat-symlink-prune" \
  "$CLWT_GH_STATES/$(printf '%s' "$primary_branch_now" | tr '/' '-')"

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

# --- completion install ---

COMP_DIR="$HOME/.local/share/bash-completion/completions"
COMP_LINK="$COMP_DIR/clwt"
EXPECTED_COMPLETION="$REPO_ROOT/.claude/scripts/clwt-completion.bash"

reset_install
rm -rf "$HOME/.local/share/bash-completion"
install_out=$(clwt install 2>&1)

check 'install creates the per-user bash-completion directory' test -d "$COMP_DIR"
check 'install symlinks the completion into the per-user completions directory' \
  test -L "$COMP_LINK"
check_equals 'the completion symlink points at the repo completion script' \
  "$EXPECTED_COMPLETION" "$(readlink "$COMP_LINK" 2>/dev/null)"
check_equals 'the completion symlink is named after the command so bash autoloads it' \
  'clwt' "$(basename "$COMP_LINK")"

if printf '%s\n' "$install_out" | grep -qF "$COMP_LINK" &&
  printf '%s\n' "$install_out" | grep -qF "$LOCAL_BIN/clwt"; then
  ok 'install reports both the binary and completion symlinks'
else
  not_ok 'install reports both the binary and completion symlinks'
fi

check 'installing again is idempotent for the completion too' clwt install

# A real file there is someone else's; do not clobber it.
rm -f "$COMP_LINK"
printf 'someone elses completion\n' >"$COMP_LINK"
check_fails 'install refuses to clobber a non-symlink completion file' clwt install
check 'the pre-existing completion file survives' \
  grep -q 'someone elses' "$COMP_LINK"
rm -f "$COMP_LINK"

section 'pr'

pr_meta 101 feat/from-pr false
pr_meta 202 feat/forked true

# The copy hook must run for pr too, or a PR worktree cannot run the project.
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
PATTERNS
printf 'SECRET=1\n' >"$PRIMARY/.env"

launch_reset
pr_out=$(clwt pr 101 2>&1)
check 'pr checks out the pull request into a managed worktree' \
  test -d "$MANAGED/feat-from-pr"
check_equals 'pr names the worktree from the pull request head ref' \
  "$MANAGED/feat-from-pr" "$(launched pwd)"
check 'pr launches claude in that worktree' test -n "$(launched pwd)"
check 'pr runs the worktreeinclude copy in the new worktree' \
  test -f "$MANAGED/feat-from-pr/.env"
check_equals 'the pr worktree is on the head ref branch' \
  'feat/from-pr' "$(cd "$MANAGED/feat-from-pr" && git symbolic-ref --short HEAD 2>/dev/null)"
if printf '%s\n' "$pr_out" | grep -qi 'fork'; then
  not_ok 'pr does not warn for a same-repo pull request'
else
  ok 'pr does not warn for a same-repo pull request'
fi

launch_reset
fork_out=$(clwt pr 202 2>&1)
check 'pr checks out a fork pull request too' test -d "$MANAGED/feat-forked"
if printf '%s\n' "$fork_out" | grep -qi 'fork'; then
  ok 'pr warns before launching when the pull request head is a fork'
else
  not_ok 'pr warns before launching when the pull request head is a fork'
fi
check_equals 'pr still launches after warning about a fork' \
  "$MANAGED/feat-forked" "$(launched pwd)"

launch_reset
clwt pr 101 --yolo >/dev/null 2>&1
check_equals '--yolo works on pr as well' \
  '--dangerously-skip-permissions' "$(launched args)"

# A merged pull request whose head branch has since been deleted — `gh pr
# checkout` fails after the worktree already exists. Found by running `clwt pr`
# against a real merged PR, which left an orphaned worktree behind.
pr_meta 303 feat/deleted-head false
printf 'checkoutFails=true\n' >>"$CLWT_GH_PRS/303"
check_fails 'pr exits non-zero when gh cannot check the pull request out' clwt pr 303
check 'pr leaves no worktree behind when checkout fails' \
  test ! -e "$MANAGED/feat-deleted-head"
if git -C "$PRIMARY" worktree list --porcelain | grep -qF 'feat-deleted-head'; then
  not_ok 'pr unregisters the worktree it made when checkout fails'
else
  ok 'pr unregisters the worktree it made when checkout fails'
fi
check_fails 'a retry after a failed checkout still fails cleanly' clwt pr 303

check_fails 'pr exits non-zero when the pull request number does not exist' clwt pr 999
check_output 'pr names the number it could not resolve' '999' clwt pr 999
check_fails 'pr requires a pull request number' clwt pr
check_fails 'pr rejects a non-numeric argument' clwt pr not-a-number

touch "$CLWT_GH_UNAVAILABLE"
check_fails 'pr exits non-zero when gh is unavailable' clwt pr 101
check_output 'pr says it needs gh' 'pr needs gh' clwt pr 101
rm -f "$CLWT_GH_UNAVAILABLE"
rm -f "$PRIMARY/.worktreeinclude"

section 'bash completion'

COMPLETION="$REPO_ROOT/.claude/scripts/clwt-completion.bash"

check 'the completion script exists' test -f "$COMPLETION"
check 'the completion script parses as valid bash' bash -n "$COMPLETION"

# A completion that reaches the network freezes the terminal on Tab. Hard rule.
# Comments are stripped first — the file explains at length *why* it avoids `gh`,
# and matching that prose would fail the check for saying the right thing.
if sed 's/#.*//' "$COMPLETION" | grep -qE '\b(gh|curl|wget|nc)\b'; then
  not_ok 'the completion script makes no network calls'
else
  ok 'the completion script makes no network calls'
fi

if [ -f "$COMPLETION" ]; then
  # Drive the completion function the way bash would: set COMP_WORDS/COMP_CWORD,
  # call it, read COMPREPLY back.
  # shellcheck disable=SC1090
  . "$COMPLETION"

  # COMPREPLY is set by _clwt in the current shell, so the call cannot be
  # subshelled — the caller cd's to the directory it wants completions from.
  complete_for() {
    COMP_WORDS=("$@")
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    COMPREPLY=()
    _clwt >/dev/null 2>&1 || true
    printf '%s\n' "${COMPREPLY[@]-}"
  }

  # Run completions from inside the sandbox repo so branch lookups have something
  # to find.
  cd "$PRIMARY" || exit 1

  subs=$(complete_for clwt '')
  missing=''
  for sub in new branch open pr root list remove prune install help; do
    printf '%s\n' "$subs" | grep -qx "$sub" || missing="$missing $sub"
  done
  if [ -z "$missing" ]; then
    ok 'completion offers all ten subcommands for a bare clwt'
  else
    not_ok "completion offers all ten subcommands for a bare clwt (missing:$missing)"
  fi

  filtered=$(complete_for clwt 'pr')
  if printf '%s\n' "$filtered" | grep -qx 'prune' && printf '%s\n' "$filtered" | grep -qx 'pr' &&
    ! printf '%s\n' "$filtered" | grep -qx 'new'; then
    ok 'completion filters subcommands by typed prefix'
  else
    not_ok 'completion filters subcommands by typed prefix'
  fi

  # new offers type prefixes, never branch names — it creates a branch that does
  # not exist yet, and offering an existing one completes into new's own error.
  types=$(complete_for clwt new '')
  if printf '%s\n' "$types" | grep -qx 'feat/' && printf '%s\n' "$types" | grep -qx 'fix/'; then
    ok 'completion offers conventional-commit type prefixes for new'
  else
    not_ok 'completion offers conventional-commit type prefixes for new'
  fi
  if printf '%s\n' "$types" | grep -q 'feat/alpha'; then
    not_ok 'completion offers no existing branch names for new'
  else
    ok 'completion offers no existing branch names for new'
  fi

  branches=$(complete_for clwt branch '')
  if printf '%s\n' "$branches" | grep -qx 'feat/alpha'; then
    ok 'completion offers local branches for branch'
  else
    not_ok 'completion offers local branches for branch'
  fi
  if printf '%s\n' "$branches" | grep -qx 'feat/remote-only'; then
    ok 'completion offers origin branches for branch'
  else
    not_ok 'completion offers origin branches for branch'
  fi

  opens=$(complete_for clwt open '')
  if printf '%s\n' "$opens" | grep -qx 'feat/alpha'; then
    ok 'completion offers managed worktree branches for open'
  else
    not_ok 'completion offers managed worktree branches for open'
  fi
  if printf '%s\n' "$opens" | grep -qx 'feat/stray'; then
    not_ok 'completion does not offer an unmanaged worktree branch for open'
  else
    ok 'completion does not offer an unmanaged worktree branch for open'
  fi

  removes=$(complete_for clwt remove '')
  if printf '%s\n' "$removes" | grep -qx 'feat/alpha'; then
    ok 'completion offers managed worktree branches for remove'
  else
    not_ok 'completion offers managed worktree branches for remove'
  fi

  prs=$(complete_for clwt pr '')
  if [ -z "$(printf '%s' "$prs" | tr -d '[:space:]')" ]; then
    ok 'completion offers nothing for pr'
  else
    not_ok 'completion offers nothing for pr'
  fi

  yolo=$(complete_for clwt new feat/x '--')
  if printf '%s\n' "$yolo" | grep -qx -- '--yolo'; then
    ok 'completion offers --yolo for a launching subcommand'
  else
    not_ok 'completion offers --yolo for a launching subcommand'
  fi
  del=$(complete_for clwt remove feat/alpha '--')
  if printf '%s\n' "$del" | grep -qx -- '--delete-branch'; then
    ok 'completion offers --delete-branch for remove'
  else
    not_ok 'completion offers --delete-branch for remove'
  fi
  yes=$(complete_for clwt prune '--')
  if printf '%s\n' "$yes" | grep -qx -- '--yes'; then
    ok 'completion offers --yes for prune'
  else
    not_ok 'completion offers --yes for prune'
  fi

  # Outside a repo: subcommands still complete, branch lookups just come back empty.
  cd "$TMP/not-a-repo" || exit 1
  outside=$(complete_for clwt '')
  if printf '%s\n' "$outside" | grep -qx 'new'; then
    ok 'completion does not error outside a git repository'
  else
    not_ok 'completion does not error outside a git repository'
  fi
  outside_branches=$(complete_for clwt open '')
  if [ -z "$(printf '%s' "$outside_branches" | tr -d '[:space:]')" ]; then
    ok 'completion returns no branches outside a git repository'
  else
    not_ok 'completion returns no branches outside a git repository'
  fi
  cd "$TMP" || exit 1
fi

# ------------------------------------------------- claude integration

# These assert against the real repository, not the sandbox: the skill, the
# permission rule, and the reground update are repo artifacts, not runtime
# behavior.
section 'claude integration'

SKILL="$REPO_ROOT/.claude/skills/clwt/SKILL.md"
SETTINGS="$REPO_ROOT/.claude/settings.json"
REGROUND="$REPO_ROOT/.claude/skills/reground/SKILL.md"

check 'the clwt skill exists' test -f "$SKILL"
check 'the clwt skill instructs against git -C' grep -qF 'git -C' "$SKILL"
check 'the clwt skill cross-links reground' grep -qF 'reground' "$SKILL"
check 'the clwt skill cross-links the beads reference' grep -qF 'references/beads.md' "$SKILL"
check 'the clwt skill states Claude cannot run the launching subcommands' \
  grep -qiE 'cannot (relaunch|run)' "$SKILL"
check 'the clwt skill has a When NOT to use section' grep -qi 'when not to use' "$SKILL"
check 'the clwt skill description is triggers-led' \
  grep -qE '^description: Use when' "$SKILL"

# Every relative markdown link in the skill must resolve.
dead=''
while IFS= read -r target; do
  case $target in
    http*) continue ;;
  esac
  resolved="$REPO_ROOT/.claude/skills/clwt/${target%%#*}"
  [ -e "$resolved" ] || dead="$dead $target"
done < <(sed -n 's/.*](\([^)]*\)).*/\1/p' "$SKILL" 2>/dev/null)
if [ -z "$dead" ]; then
  ok 'every file the clwt skill links to exists'
else
  not_ok "every file the clwt skill links to exists (dead:$dead)"
fi

check 'settings.json is valid json' python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$SETTINGS"
if python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if 'Bash(git -C *)' in d.get('permissions', {}).get('deny', []) else 1)
" "$SETTINGS" 2>/dev/null; then
  ok 'settings.json deny contains Bash(git -C *)'
else
  not_ok 'settings.json deny contains Bash(git -C *)'
fi
if python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
allow = d.get('permissions', {}).get('allow', [])
sys.exit(0 if 'Bash(git add *)' in allow and len(allow) >= 20 else 1)
" "$SETTINGS" 2>/dev/null; then
  ok 'settings.json keeps its existing allow list intact'
else
  not_ok 'settings.json keeps its existing allow list intact'
fi
if python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get('hooks', {}).get('SessionStart') and d.get('statusLine') else 1)
" "$SETTINGS" 2>/dev/null; then
  ok 'settings.json keeps its hooks and statusLine intact'
else
  not_ok 'settings.json keeps its hooks and statusLine intact'
fi

README="$REPO_ROOT/README.md"
check 'the README has a clwt section' grep -qiE '^#+ .*clwt' "$README"

# The clwt section was originally inserted *inside* an existing ```markdown fence,
# so it rendered as a code sample and unbalanced every fence after it — while all
# the line-based greps below passed happily. Count fences, and confirm the section
# heading is not swallowed by one.
fences=$(grep -c '^```' "$README")
if [ $((fences % 2)) -eq 0 ]; then
  ok 'the README code fences are balanced'
else
  not_ok "the README code fences are balanced (found $fences)"
fi
if python3 - "$README" <<'PY'
import sys
inside = False
for line in open(sys.argv[1]):
    if line.startswith('```'):
        inside = not inside
    elif line.startswith('## `clwt`') and inside:
        sys.exit(1)
sys.exit(0)
PY
then
  ok 'the clwt section is a real heading, not inside a code fence'
else
  not_ok 'the clwt section is a real heading, not inside a code fence'
fi

readme_missing=''
for sub in new branch open pr root list remove prune install help; do
  grep -qE "clwt $sub" "$README" || readme_missing="$readme_missing $sub"
done
if [ -z "$readme_missing" ]; then
  ok 'the README documents all ten subcommands'
else
  not_ok "the README documents all ten subcommands (missing:$readme_missing)"
fi

check 'the README documents the managed root layout' \
  grep -qF '.worktrees' "$README"
check 'the README documents CLWT_REPO_ROOT' grep -qF 'CLWT_REPO_ROOT' "$README"
check 'the README documents the --yolo shorthand' grep -qF -- '--yolo' "$README"
check 'the README says what --yolo bypasses' \
  grep -qF -- '--dangerously-skip-permissions' "$README"
check 'the README documents the worktreeinclude and beads behavior' \
  grep -qF '.worktreeinclude' "$README"
check 'the README documents how to run the test suite' \
  grep -qF 'clwt-test.sh' "$README"
# Newlines collapsed first: the claim spans a line break in the prose, and grep is
# line-based. The assertion is about what the document says, not how it wraps.
if tr '\n' ' ' <"$README" | grep -qiE 'cannot relaunch *itself|must be run by'; then
  ok 'the README says launching subcommands are run by the developer'
else
  not_ok 'the README says launching subcommands are run by the developer'
fi

check 'the reground skill recommends clwt' grep -qF 'clwt' "$REGROUND"
if grep -qE '^\s*-.*`git worktree add <path>' "$REGROUND"; then
  not_ok 'the reground skill no longer recommends raw git worktree add as the default'
else
  ok 'the reground skill no longer recommends raw git worktree add as the default'
fi

# -------------------------------------------------------------------- summary

section "results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
