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
  state_file="$CLWT_GH_STATES/$(printf '%s' "$3" | tr '/' '-')"
  if [ ! -f "$state_file" ]; then
    echo "no pull requests found for branch \"$3\"" >&2
    exit 1
  fi
  cat "$state_file"
  exit 0
fi
exit 0
STUB
chmod +x "$BIN/gh"
export CLWT_GH_UNAVAILABLE="$TMP/gh-unavailable"
export CLWT_GH_STATES="$TMP/gh-states"
mkdir -p "$CLWT_GH_STATES"
pr_state() { printf '%s\n' "$2" >"$CLWT_GH_STATES/$(printf '%s' "$1" | tr '/' '-')"; }

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

# Uses whichever subcommand is still unbuilt. When the last one lands this
# assertion has nothing left to check and should be deleted, not retargeted.
check_output 'an unimplemented subcommand reports not yet implemented rather than unknown command' \
  'not yet implemented' clwt pr
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
check_output 'prune says why it cannot determine merge state' 'gh' clwt prune
check_fails 'prune --yes also exits non-zero when gh is unavailable' clwt prune --yes
check 'prune removed nothing while gh was unavailable' test -d "$MANAGED/feat-merged-b"
rm -f "$CLWT_GH_UNAVAILABLE"

check_fails 'prune rejects a positional argument' clwt prune something
check_fails 'prune rejects an unknown flag' clwt prune --force

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
