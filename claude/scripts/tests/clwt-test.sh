#!/usr/bin/env bash
# clwt-test.sh — self-contained test suite for claude/scripts/clwt
#
# Builds a throwaway world under a fake $HOME: a bare "remote", a primary clone,
# and stub `claude` / `gh` binaries on PATH that log how they were invoked. That
# stub-logs-its-environment trick is what lets us assert the thing that matters
# most — that a launched session really does inherit the worktree as its cwd.
#
# Usage:  bash claude/scripts/tests/clwt-test.sh
# Exits non-zero if any check fails.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
CLWT="$REPO_ROOT/claude/scripts/clwt"

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

# check_contains <label> <needle> <captured-text> — like check_output, but
# against text the caller already captured, so a side-effecting command can be
# asserted on twice (e.g. exit code and output) without running it twice.
check_contains() {
  local label=$1 needle=$2 text=$3
  if printf '%s\n' "$text" | grep -qF -- "$needle"; then ok "$label"; else not_ok "$label"; fi
}

# check_not_contains <label> <needle> <captured-text> — the inverse of check_contains.
check_not_contains() {
  local label=$1 needle=$2 text=$3
  if printf '%s\n' "$text" | grep -qF -- "$needle"; then not_ok "$label"; else ok "$label"; fi
}

section() { printf '\n%s\n' "$1"; }

# ---------------------------------------------------------------- world setup

TMP=$(mktemp -d "${TMPDIR:-/tmp}/clwt-test.XXXXXX")
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
      sed -n 's/^headRepositoryOwner=//p' "$meta"
      sed -n 's/^headRepository=//p' "$meta"
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
  number=$3
  meta="$CLWT_GH_PRS/$number"
  if [ ! -f "$meta" ]; then
    echo "could not resolve to a pull request with the number of $number" >&2
    exit 1
  fi
  if grep -q '^checkoutFails=true$' "$meta"; then
    # What really happens when a merged PR's head branch has been deleted.
    echo "fatal: couldn't find remote ref" >&2
    exit 1
  fi
  head_ref=$(sed -n 's/^headRefName=//p' "$meta")

  force=0
  shift 3
  for arg in "$@"; do
    [ "$arg" = "--force" ] && force=1
  done

  # This stub models the SAME-REPO checkout only: fetch the PR head and update
  # the origin tracking ref as a side effect, for every fixture. Real gh fetches
  # a fork PR from refs/pull/N/head into a <login>-<branch> local name and never
  # updates refs/remotes/origin/<head> — so cross-repo fixtures here exercise
  # clwt's pre-checkout decision, not gh's fork mechanics. The `+` forces the
  # tracking-ref update even when it would not itself be a fast-forward, since a
  # force-pushed PR is exactly the case under test.
  if ! git fetch -q origin "+refs/heads/$head_ref:refs/remotes/origin/$head_ref" 2>/dev/null; then
    echo "fatal: couldn't find remote ref $head_ref" >&2
    exit 1
  fi

  if ! git show-ref --verify --quiet "refs/heads/$head_ref"; then
    # No local branch: create it at the PR head, tracking origin.
    git checkout -q -b "$head_ref" "refs/remotes/origin/$head_ref"
    exit $?
  fi

  git checkout -q "$head_ref" || exit 1

  if [ "$force" = 1 ]; then
    git reset -q --hard "refs/remotes/origin/$head_ref"
    exit $?
  fi

  # `merge --ff-only` natively succeeds in both directions (fast-forward when
  # behind, "Already up to date." when ahead) and emits the real
  # "Not possible to fast-forward" fatal on divergence — no pre-check needed,
  # and its stderr must reach the caller because tests assert on that message.
  git merge --ff-only "refs/remotes/origin/$head_ref" >/dev/null
  exit $?
fi
exit 0
STUB
chmod +x "$BIN/gh"
export CLWT_GH_UNAVAILABLE="$TMP/gh-unavailable"
export CLWT_GH_STATES="$TMP/gh-states"
export CLWT_GH_PRS="$TMP/gh-prs"
mkdir -p "$CLWT_GH_STATES" "$CLWT_GH_PRS"
pr_state() { printf '%s\n' "$2" >"$CLWT_GH_STATES/$(printf '%s' "$1" | tr '/' '-')"; }
# pr_meta <number> <head-ref> <is-cross-repository> [head-owner] [head-repo] —
# owner/repo default to the identity clwt derives from $REMOTE
# ($HOME/remotes/owner/project.git), i.e. "origin is the pull request's own
# repository". Override them for a pull request whose head lives somewhere else,
# which is what a fork-workflow clone (origin=fork, upstream=base) looks like.
pr_meta() {
  printf 'headRefName=%s\nisCrossRepository=%s\nheadRepositoryOwner=%s\nheadRepository=%s\n' \
    "$2" "$3" "${4:-owner}" "${5:-project}" >"$CLWT_GH_PRS/$1"
  push_pr_head "$2"
}

# ensure_scratch_push — a clone of $REMOTE used exclusively for creating and
# pushing PR-head commits. `git push` opportunistically updates the PUSHING
# repo's own remote-tracking ref for whatever it just pushed (confirmed
# empirically) — so if $PRIMARY did the pushing, every fixture branch would
# look "already fetched" before the gh stub ever ran, and the whole point of
# these fixtures (a stub that must fetch to learn the real head) would be
# defeated silently.
SCRATCH_PUSH="$TMP/scratch-push"
ensure_scratch_push() {
  [ -d "$SCRATCH_PUSH" ] || git clone -q "$REMOTE" "$SCRATCH_PUSH" >/dev/null 2>&1
}

# cached_object <branch> — fetches <branch>'s current head from $REMOTE into
# $PRIMARY's object database under a throwaway ref outside refs/heads and
# refs/remotes/origin, so a LOCAL commit can be built on top of it (parent
# objects must exist locally). This does NOT leave the origin tracking ref
# untouched: fetching by branch NAME also updates refs/remotes/origin/<branch>
# opportunistically, via $PRIMARY's own default fetch refspec, regardless of
# the explicit destination given here. That side effect is what fixtures 707
# and 709 rely on (they need the tracking ref populated before the probe
# runs); fixture 711, which needs it genuinely absent, fetches the raw SHA
# instead of the branch name specifically to avoid triggering it. Prints the
# fetched commit's sha.
cached_object() {
  local branch=$1
  git -C "$PRIMARY" fetch -q origin "refs/heads/$branch:refs/pr-fixture-cache/$branch" 2>/dev/null || return 1
  git -C "$PRIMARY" rev-parse "refs/pr-fixture-cache/$branch"
}

# push_pr_head <branch> — gives a pr_meta fixture a REAL head branch on
# $REMOTE, pushed from the scratch clone (never $PRIMARY — see
# ensure_scratch_push) so $PRIMARY's own origin tracking ref for it stays
# genuinely absent until the gh stub fetches it.
push_pr_head() {
  local branch=$1 sha
  ensure_scratch_push
  sha=$(git -C "$SCRATCH_PUSH" commit-tree "$(git -C "$SCRATCH_PUSH" rev-parse HEAD^{tree})" \
    -p HEAD -m "initial head for $branch ($RANDOM$RANDOM)")
  git -C "$SCRATCH_PUSH" push -q -f origin "$sha:refs/heads/$branch"
}

# force_advance_pr_head <branch> — force-moves an EXISTING PR head on $REMOTE
# to a brand-new commit, pushed from the scratch clone, so "the PR was
# force-pushed" is a real fact on $REMOTE rather than assumed, and $PRIMARY's
# own tracking ref for it stays stale (or absent) until fetched.
force_advance_pr_head() {
  local branch=$1 old_tip new_sha
  ensure_scratch_push
  git -C "$SCRATCH_PUSH" fetch -q origin "refs/heads/$branch" >/dev/null 2>&1
  old_tip=$(git -C "$SCRATCH_PUSH" ls-remote origin "refs/heads/$branch" | cut -f1)
  if [ -z "$old_tip" ]; then
    echo "force_advance_pr_head: $branch has no existing head on \$REMOTE" >&2
    return 1
  fi
  new_sha=$(git -C "$SCRATCH_PUSH" commit-tree "$(git -C "$SCRATCH_PUSH" rev-parse "$old_tip^{tree}")" \
    -p "$old_tip" -m "force-push $branch ($RANDOM$RANDOM)")
  git -C "$SCRATCH_PUSH" push -q -f origin "$new_sha:refs/heads/$branch"
  printf '%s\n' "$new_sha"
}

# rewrite_pr_head <branch> [<base>] — force-pushes a head parented on
# <base>'s OWN parent, i.e. a SIBLING of <base> rather than a descendant of
# it: a genuine history rewrite. force_advance_pr_head's commits are always
# additive children of the old tip, so the local branch in a fixture built
# purely from it never stops being an ancestor of the real remote head — gh's
# own `merge --ff-only` then succeeds on its own, with or without --force,
# and the fixture never actually exercises the auto-force path it's meant to.
#
# <base> defaults to the CURRENT remote tip (mirroring force_advance_pr_head),
# which is enough to sever a fixture that has made no other advance yet (the
# "equal" fixture: rewriting the ONE tip that exists severs it outright). A
# fixture that must first advance past that tip to establish a relationship
# (the "behind" fixture, which needs a strictly-behind stale tracking ref)
# cannot rely on the default: rewinding one hop from whatever the remote has
# since advanced to always lands back on a commit still descended from the
# local branch's tip, because every force_advance_pr_head hop in between
# preserves that ancestry — no single one-hop rewind from further down the
# chain can ever undo it. Passing the ORIGINAL tip explicitly severs the local
# branch's own ancestry directly, regardless of how far the remote advanced
# past it since.
rewrite_pr_head() {
  local branch=$1 base=${2:-} new_sha
  ensure_scratch_push
  if [ -z "$base" ]; then
    git -C "$SCRATCH_PUSH" fetch -q origin "refs/heads/$branch" >/dev/null 2>&1
    base=$(git -C "$SCRATCH_PUSH" ls-remote origin "refs/heads/$branch" | cut -f1)
  fi
  if [ -z "$base" ]; then
    echo "rewrite_pr_head: $branch has no existing head on \$REMOTE" >&2
    return 1
  fi
  new_sha=$(git -C "$SCRATCH_PUSH" commit-tree "$(git -C "$SCRATCH_PUSH" rev-parse "$base^{tree}")" \
    -p "$base^" -m "rewrite $branch ($RANDOM$RANDOM)")
  if [ -z "$new_sha" ]; then
    # A root commit has no $base^; an empty $new_sha would turn the push below
    # into ":refs/heads/$branch" — a branch DELETION, not a rewrite.
    echo "rewrite_pr_head: cannot rewind $branch past a root commit" >&2
    return 1
  fi
  git -C "$SCRATCH_PUSH" push -q -f origin "$new_sha:refs/heads/$branch"
  printf '%s\n' "$new_sha"
}

# new_commit_on <parent-sha> <label> — a new LOCAL commit in $PRIMARY on top of
# <parent-sha>, same tree, unique message. Built with plumbing so it never
# touches any checkout; a branch pointed at it stays held nowhere until
# something checks it out. <parent-sha> must already exist in $PRIMARY's
# object database (see cached_object).
new_commit_on() {
  git -C "$PRIMARY" commit-tree "$(git -C "$PRIMARY" rev-parse "$1^{tree}")" \
    -p "$1" -m "seed: $2 ($RANDOM$RANDOM)"
}

# seed_leftover_branch <branch> <ahead|diverged> — seeds a LOCAL branch in
# $PRIMARY, held nowhere, at the given relationship to the PR head that will
# exist on $REMOTE once the gh stub fetches it. For "diverged" the remote head
# is force-advanced first, so the relationship under test is to the branch
# AFTER a force-push — the scenario the probe exists to catch. The equal and
# behind relationships are NOT offered here: the probe judges them against a
# STALE tracking ref that must be fetched mid-fixture (see fixtures 705/706,
# which interleave fetch_stale_tracking_ref with rewrite_pr_head) — a helper
# arm judging against the live head would test a different, easier property.
seed_leftover_branch() {
  local branch=$1 relation=$2 base new_head local_sha

  # ENFORCED, not assumed: a branch already registered to a worktree elsewhere in
  # the suite would route a later `clwt pr` through reuse_or_refuse — exit 0, no
  # probe at all — and any test built on this helper would pass for the wrong
  # reason. Checked first, not left to `git branch -f`'s own worktree guard, so
  # this assertion is the one that actually fires and can be tested on its own.
  if git -C "$PRIMARY" worktree list --porcelain | grep -qxF "branch refs/heads/$branch"; then
    echo "seed_leftover_branch: $branch is already checked out somewhere" >&2
    return 1
  fi

  base=$(cached_object "$branch") || {
    echo "seed_leftover_branch: $branch has no PR head on \$REMOTE yet (call pr_meta first)" >&2
    return 1
  }

  case "$relation" in
    ahead)
      local_sha=$(new_commit_on "$base" "ahead of $branch")
      git -C "$PRIMARY" branch -f "$branch" "$local_sha" >/dev/null
      ;;
    diverged)
      force_advance_pr_head "$branch" >/dev/null || return 1
      local_sha=$(new_commit_on "$base" "diverged from $branch")
      git -C "$PRIMARY" branch -f "$branch" "$local_sha" >/dev/null
      ;;
    *)
      echo "seed_leftover_branch: unknown relation: $relation (want ahead|diverged)" >&2
      return 1
      ;;
  esac
}

# fetch_stale_tracking_ref <branch> — fetches <branch>'s CURRENT $REMOTE head
# into $PRIMARY's refs/remotes/origin/<branch> right now, simulating a
# tracking ref clwt already knows about from an earlier session. Call this
# BEFORE any later force_advance_pr_head call whose relation should be judged
# against exactly this value — the auto-force probe under test reads this ref
# before gh's OWN (later) fetch can move it again, and that "before" is the
# entire point: seed_leftover_branch alone never populates this ref at all, so
# without a call like this the probe would only ever see it as absent.
fetch_stale_tracking_ref() {
  local branch=$1
  git -C "$PRIMARY" fetch -q origin "refs/heads/$branch:refs/remotes/origin/$branch"
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
#
# `[^[:space:]]`, never `[^\t ]`: BSD sed does not read `\t` as a tab inside a
# bracket expression, so that class excludes the LETTER t and truncates the
# branch name it is meant to capture — `stable` came back as `s`, and the guard
# reported a fixture mismatch that did not exist. The parse is deliberately its
# own copy rather than a call into clwt: a fixture guard that reused the code
# under test would go quiet exactly when that code broke.
check_equals 'the clone origin/HEAD is stale relative to the remote default' \
  'refs/heads/main|stable' \
  "$(git -C "$PRIMARY" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/|refs/heads/|')|$(git -C "$PRIMARY" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p')"

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

help_text=$(clwt help)
check_equals 'clwt --help prints the same usage as clwt help' "$help_text" "$(clwt --help)"
check_equals 'clwt -h prints the same usage as clwt help' "$help_text" "$(clwt -h)"
check_equals 'clwt new --help prints the usage' "$help_text" "$(clwt new --help)"
check_equals 'clwt remove --help prints the usage' "$help_text" "$(clwt remove --help)"
check_equals 'clwt prune --help prints the usage' "$help_text" "$(clwt prune --help)"

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
# These pass `git check-ref-format --branch` but must still be refused, because
# they become a path segment. Without one of these, validate_worktree_name's own
# character-class guard is never the thing that fires and can be deleted silently.
check 'the semicolon branch name is accepted by git itself' \
  git -C "$PRIMARY" check-ref-format --branch 'feat/a;b'
check_fails 'new rejects a ref-valid name that is unsafe as a path segment' \
  clwt new 'feat/a;b'
check_fails 'new rejects a ref-valid name containing a shell metacharacter' \
  clwt new 'feat/a$b'
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

# A hostile branch can commit a .worktreeinclude-matched path as a tracked symlink
# pointing anywhere. git materializes it in the worktree, and cp then writes
# THROUGH it — out of the managed root entirely. Confirmed writing to ~/.bashrc
# before the guard existed. `clwt pr` makes this reachable from a fork.
(
  cd "$TMP/seed"
  git checkout -q stable
  ln -s "$TMP/victim-file" evil-link
  ln -s "$TMP/victim-dir" nested-link
  mkdir -p dir-dst
  ln -s "$TMP/victim-dir/dir-dst" dir-dst/dir-dst
  git add evil-link nested-link dir-dst
  git commit -qm 'branch carrying symlinks where copied files would land'
  git push -q origin stable
)
printf 'ORIGINAL\n' >"$TMP/victim-file"
mkdir -p "$TMP/victim-dir"
printf 'SECRET=1\n' >"$PRIMARY/evil-link"
mkdir -p "$PRIMARY/nested-link/sub"
printf 'SECRET=1\n' >"$PRIMARY/nested-link/sub/config"
printf 'SECRET=1\n' >"$PRIMARY/dir-dst"

# Shape 1 — the destination itself is a committed symlink.
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
evil-link
PATTERNS
launch_reset
symlink_out=$(clwt new feat/symlink-escape 2>&1 || true)
check_equals 'a symlinked copy destination does not launch claude' '' "$(launched pwd)"
check_equals 'the file outside the worktree is untouched' \
  'ORIGINAL' "$(cat "$TMP/victim-file" 2>/dev/null)"
check 'the worktree is abandoned when a copy destination is a symlink' \
  test ! -e "$MANAGED/feat-symlink-escape"
if printf '%s\n' "$symlink_out" | grep -qiF 'symlink'; then
  ok 'the refusal says the destination was a symlink'
else
  not_ok "the refusal says the destination was a symlink (got: $(printf '%s' "$symlink_out" | tr '\n' '|'))"
fi

# Shape 2 — an *intermediate* directory is a committed symlink. Previously
# untested: the suite passed with the parent-containment guard deleted, while a
# PoC still escaped through it.
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
nested-link/sub/config
PATTERNS
launch_reset
nested_out=$(clwt new feat/nested-escape 2>&1 || true)
check_equals 'a symlinked intermediate directory does not launch claude' '' "$(launched pwd)"
check 'nothing was written through the symlinked intermediate directory' \
  test ! -e "$TMP/victim-dir/sub/config"
# The parent must be validated BEFORE mkdir -p, or a hostile branch gets an
# arbitrary empty-directory-creation primitive on the far side of the symlink.
check 'no directory is created outside the worktree' test ! -e "$TMP/victim-dir/sub"
check 'the worktree is abandoned when the destination parent escapes' \
  test ! -e "$MANAGED/feat-nested-escape"
if printf '%s\n' "$nested_out" | grep -qiF 'resolves outside the worktree'; then
  ok 'the refusal says the destination resolved outside the worktree'
else
  not_ok "the refusal says the destination resolved outside the worktree (got: $(printf '%s' "$nested_out" | tr '\n' '|'))"
fi

# Shape 3 — the destination is a *directory* holding a symlink of the same name.
# `cp` copies into a directory as $dst/$(basename $src), and src/dst share a
# basename here, so the write lands on that symlink — past both other guards.
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
dir-dst
PATTERNS
launch_reset
dir_out=$(clwt new feat/dir-escape 2>&1 || true)
check_equals 'a directory at the copy destination does not launch claude' '' "$(launched pwd)"
check 'nothing was written through the directory-at-destination shape' \
  test ! -e "$TMP/victim-dir/dir-dst"
check 'the worktree is abandoned when the destination is a directory' \
  test ! -e "$MANAGED/feat-dir-escape"
if printf '%s\n' "$dir_out" | grep -qiF 'non-regular destination'; then
  ok 'the refusal says the destination was not a regular file'
else
  not_ok "the refusal says the destination was not a regular file (got: $(printf '%s' "$dir_out" | tr '\n' '|'))"
fi

rm -rf "$PRIMARY/evil-link" "$PRIMARY/nested-link" "$PRIMARY/dir-dst" "$PRIMARY/.worktreeinclude"

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

# Must be a function, not `env …`: env execs a binary and cannot invoke a shell
# function, so `env PATH=… clwt_in …` fails for that reason alone and any
# check_fails around it passes vacuously.
clwt_with_failing_git() {
  PATH="$FAILGIT:$PATH" clwt_in "$PRIMARY" "$@"
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
  clwt_with_failing_git remove feat/failing-git

make_failing_git 'status'
check_fails 'remove exits non-zero when git status fails' \
  clwt_with_failing_git remove feat/failing-git
check_output 'remove says it cannot determine cleanliness when git status fails' \
  'cannot determine whether' \
  clwt_with_failing_git remove feat/failing-git
check 'remove refuses when git cannot report status' \
  test -d "$MANAGED/feat-failing-git"
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

# gh genuinely absent from PATH, not merely unauthenticated. The spec requires
# these be distinguishable rather than misreported.
NOGH="$TMP/nogh"
mkdir -p "$NOGH"
for b in git bash sed awk grep cat cp rm mkdir mktemp ln readlink dirname basename env; do
  [ -e "$NOGH/$b" ] || ln -s "$(command -v "$b")" "$NOGH/$b" 2>/dev/null
done
clwt_without_gh() { PATH="$NOGH" clwt_in "$PRIMARY" "$@"; }

check_fails 'prune exits non-zero when gh is not on PATH at all' \
  clwt_without_gh prune
check_output 'prune distinguishes gh missing from gh unauthenticated' \
  'not on PATH' clwt_without_gh prune
check_output 'pr also reports gh missing from PATH' \
  'not on PATH' clwt_without_gh pr 101

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
EXPECTED_COMPLETION="$REPO_ROOT/claude/scripts/clwt-completion.bash"

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

section 'pr --force'

# Fresh PR numbers throughout this section — 101/202/303's managed worktrees
# linger from the tests above, so reusing them would route through
# reuse_or_refuse instead of the fresh-checkout path these tests target.

pr_meta 701 feat/pr-force-diverged false
seed_leftover_branch feat/pr-force-diverged diverged
launch_reset
check 'pr --force resets a diverged leftover branch to the pull request head' \
  clwt pr 701 --force
check_equals 'the --force reset branch tip matches the pull request head exactly' \
  "$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/pr-force-diverged | cut -f1)" \
  "$(git -C "$PRIMARY" rev-parse feat/pr-force-diverged)"

pr_meta 702 feat/pr-force-fresh false
launch_reset
check 'pr --force succeeds when no leftover local branch exists' \
  clwt pr 702 --force
check_equals 'pr --force still launches claude in the new worktree' \
  "$MANAGED/feat-pr-force-fresh" "$(launched pwd)"

# "ahead" so the plain (non-forced) checkout the gh stub performs here succeeds
# on its own — the point is to prove --force after `--` never reaches gh at
# all, not to also exercise a forced reset.
pr_meta 703 feat/pr-force-passthrough false
seed_leftover_branch feat/pr-force-passthrough ahead
passthrough_before=$(git -C "$PRIMARY" rev-parse feat/pr-force-passthrough)
launch_reset
check 'pr passes --force after -- through to claude untouched' \
  clwt pr 703 -- --force
check_equals 'the literal --force argument reaches claude' \
  '--force' "$(launched args)"
check_equals 'a --force after -- never reaches gh, so the branch tip is unchanged' \
  "$passthrough_before" "$(git -C "$PRIMARY" rev-parse feat/pr-force-passthrough)"

# Reuses PR 303 (feat/deleted-head, checkoutFails=true) from the plain-pr
# checks above: the failure is unconditional in the gh stub, so it also
# exercises the --force branch of the same checkout call.
launch_reset
check_fails 'a failed --force checkout leaves no worktree behind' clwt pr 303 --force
check 'a failed --force checkout leaves no directory behind' \
  test ! -e "$MANAGED/feat-deleted-head"
if git -C "$PRIMARY" worktree list --porcelain | grep -qF 'feat-deleted-head'; then
  not_ok 'a failed --force checkout unregisters the worktree it made'
else
  ok 'a failed --force checkout unregisters the worktree it made'
fi

pr_meta 704 feat/pr-force-reuse false
launch_reset
clwt pr 704 >/dev/null 2>&1
reuse_before=$(git -C "$PRIMARY" rev-parse feat/pr-force-reuse)
launch_reset
check_output 'pr --force on a reused worktree notes the branch was not reset' \
  'not reset' clwt pr 704 --force
check_equals 'a reused worktree leaves the branch tip untouched by --force' \
  "$reuse_before" "$(git -C "$PRIMARY" rev-parse feat/pr-force-reuse)"
check_equals 'pr --force on a reused worktree still relaunches claude there' \
  "$MANAGED/feat-pr-force-reuse" "$(launched pwd)"

check_fails 'branch rejects --force as an unknown option' clwt branch --force
check_fails 'root rejects --force as an unknown option' clwt root --force

# A phrase from the explanatory paragraph, not the bare flag: the synopsis line
# alone would keep this green with the whole paragraph deleted.
check_output 'help documents --force' 'resetting a leftover' clwt help
check_output 'help documents the no-flag auto-reset' 'provably contained' clwt help

section 'pr auto-force safety probe'

# Fresh PR numbers throughout this section too — see the note above the
# 'pr --force' section for why reusing an earlier number would route through
# reuse_or_refuse instead of the path each test actually targets.

# The "equal" scenario: a tracking ref clwt already fetched once (established
# here via fetch_stale_tracking_ref, BEFORE the force-push moves $REMOTE
# again) exactly matches the leftover local branch. That stale ref is what
# "the pre-fetch origin tip" means — gh's own fetch, later, moves it again.
#
# The force-push uses rewrite_pr_head, not force_advance_pr_head: the latter's
# commits are always children of the old tip, so the local branch (still at
# that old tip) would stay its ancestor — gh's own `merge --ff-only` would then
# succeed on its own, and this fixture would never actually need --force to
# pass, silently defeating the whole point of testing the auto-force path.
pr_meta 705 feat/pr-auto-equal false
old_705=$(cached_object feat/pr-auto-equal)
fetch_stale_tracking_ref feat/pr-auto-equal
git -C "$PRIMARY" branch feat/pr-auto-equal "$old_705" >/dev/null
rewrite_pr_head feat/pr-auto-equal >/dev/null
new_head_705=$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/pr-auto-equal | cut -f1)
# Pins the property the fixture depends on: if this ever starts passing, the
# fixture is fast-forwardable again and the auto-reset checks below would pass
# even with auto_force hard-coded to 0 (see the equivalent mutation check).
# Runs in $SCRATCH_PUSH, which authored both commits — $PRIMARY never fetched
# the rewritten head, so merge-base there exits 128 (missing object) and
# check_fails would read that as a pass no matter what the fixture's shape is.
check_fails 'the equal-tip fixture is genuinely non-fast-forwardable' \
  git -C "$SCRATCH_PUSH" merge-base --is-ancestor "$old_705" "$new_head_705"
launch_reset
equal_out=$(clwt pr 705 2>&1)
equal_rc=$?
check_equals 'pr auto-resets a leftover branch equal to the pre-fetch origin tip' '0' "$equal_rc"
check_equals 'the equal-branch auto-reset lands at the pull request head' \
  "$new_head_705" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-equal)"
check_contains 'the auto-reset prints a note naming the branch' \
  'resetting feat/pr-auto-equal' "$equal_out"

# "Strictly behind": the stale tracking ref (fetched once, at commit1) sits
# BETWEEN the leftover local branch (commit0, older) and $REMOTE's real
# current head (a rewrite, discarding commit1, forced again after the stale
# fetch).
#
# The final advance passes $old_706 explicitly rather than relying on
# rewrite_pr_head's live-tip default — see that helper's doc for why a one-hop
# rewind from the already-advanced tip cannot sever old_706's own ancestry.
pr_meta 706 feat/pr-auto-behind false
old_706=$(cached_object feat/pr-auto-behind)
force_advance_pr_head feat/pr-auto-behind >/dev/null
fetch_stale_tracking_ref feat/pr-auto-behind
rewrite_pr_head feat/pr-auto-behind "$old_706" >/dev/null
git -C "$PRIMARY" branch feat/pr-auto-behind "$old_706" >/dev/null
new_head_706=$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/pr-auto-behind | cut -f1)
check_fails 'the behind fixture is genuinely non-fast-forwardable' \
  git -C "$SCRATCH_PUSH" merge-base --is-ancestor "$old_706" "$new_head_706"
launch_reset
check 'pr auto-resets a leftover branch strictly behind origin' clwt pr 706
check_equals 'the behind-branch auto-reset lands at the pull request head' \
  "$new_head_706" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-behind)"

# Diverged: a genuine local-only commit off the same base $REMOTE force-pushed
# from, so it is provably NOT contained no matter which tip the probe reads.
pr_meta 707 feat/pr-auto-diverged false
seed_leftover_branch feat/pr-auto-diverged diverged
diverged_before_707=$(git -C "$PRIMARY" rev-parse feat/pr-auto-diverged)
launch_reset
check_fails 'pr refuses a leftover branch carrying a local-only commit' clwt pr 707
check_output 'that refusal suggests clwt pr N --force' 'clwt pr 707 --force' clwt pr 707
check 'that refusal leaves no worktree behind' test ! -e "$MANAGED/feat-pr-auto-diverged"
check_equals 'the refused diverged branch keeps its tip untouched' \
  "$diverged_before_707" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-diverged)"

# Cross-repository: the local branch IS contained in a same-named origin
# branch (same construction as the "equal" case above), so this is the test
# that fails if the $cross gate is ever dropped — the only thing standing
# between this fixture and an auto-reset is isCrossRepository=true.
pr_meta 708 feat/pr-auto-cross true
old_708=$(cached_object feat/pr-auto-cross)
fetch_stale_tracking_ref feat/pr-auto-cross
git -C "$PRIMARY" branch feat/pr-auto-cross "$old_708" >/dev/null
launch_reset
cross_out=$(clwt pr 708 2>&1)
cross_rc=$?
check_equals 'a cross-repository pull request with a contained local branch still succeeds' \
  '0' "$cross_rc"
check_not_contains 'pr never auto-resets for a cross-repository pull request' \
  'resetting feat/pr-auto-cross' "$cross_out"

# Same shape as 708 but isCrossRepository=false — the head simply lives in a
# repository that is not origin, which is what a fork-workflow clone looks like
# (origin=your fork, upstream=base). gh resolves the pull request against
# upstream, so refs/remotes/origin/<branch> is a same-named branch in a
# DIFFERENT repository and containment against it proves nothing. Only the
# owner/repo identity check separates this fixture from an auto-reset.
pr_meta 716 feat/pr-auto-elsewhere false other-owner project
old_716=$(cached_object feat/pr-auto-elsewhere)
fetch_stale_tracking_ref feat/pr-auto-elsewhere
git -C "$PRIMARY" branch feat/pr-auto-elsewhere "$old_716" >/dev/null
launch_reset
elsewhere_out=$(clwt pr 716 2>&1)
elsewhere_rc=$?
check_equals 'a pull request whose head lives outside origin still succeeds' \
  '0' "$elsewhere_rc"
check_not_contains 'pr never auto-resets when origin is not the head repository' \
  'resetting feat/pr-auto-elsewhere' "$elsewhere_out"

# Same identity, different spelling: GitHub reports the canonical case while the
# clone URL keeps whatever was typed. Without folding, the identity check would
# withhold auto-force from every such developer permanently, and the plain path
# would give no hint why. No force-push needed — an equal tip is contained, which
# is all the probe requires to reach its note.
pr_meta 717 feat/pr-auto-case false Owner Project
old_717=$(cached_object feat/pr-auto-case)
fetch_stale_tracking_ref feat/pr-auto-case
git -C "$PRIMARY" branch feat/pr-auto-case "$old_717" >/dev/null
launch_reset
case_out=$(clwt pr 717 2>&1)
check_contains 'pr auto-resets when the head repository differs only by case' \
  'resetting feat/pr-auto-case' "$case_out"

# Ahead: gh's plain ff-only checkout is a no-op success on its own — the
# point is proving the fresh-worktree path ran (not reuse_or_refuse) and the
# tip never moved, pinning AC 9's accepted pass-through.
pr_meta 709 feat/pr-auto-ahead false
seed_leftover_branch feat/pr-auto-ahead ahead
ahead_before_709=$(git -C "$PRIMARY" rev-parse feat/pr-auto-ahead)
launch_reset
ahead_out=$(clwt pr 709 2>&1)
ahead_rc=$?
check_equals 'pr passes through a leftover branch ahead of the pull request head' \
  '0' "$ahead_rc"
check_equals 'the ahead branch tip is unchanged by the pass-through path' \
  "$ahead_before_709" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-ahead)"
check_not_contains 'the ahead pass-through takes the fresh-worktree path, not reuse_or_refuse' \
  'reusing existing worktree' "$ahead_out"

# Cross-repository, checkout fails outright (the fork's real head is gone):
# branch_existed must still have been captured before the $cross gate, or the
# hint below would go silent on exactly the failure it exists to serve.
pr_meta 710 feat/pr-auto-cross-fail true
printf 'checkoutFails=true\n' >>"$CLWT_GH_PRS/710"
git -C "$PRIMARY" branch feat/pr-auto-cross-fail >/dev/null
launch_reset
check_fails 'a failed cross-repository checkout still exits non-zero' clwt pr 710
check_output 'a failed checkout on a cross-repository pull request still suggests --force when a local branch exists' \
  'clwt pr 710 --force' clwt pr 710

# Missing tracking ref, same-repo — distinct from the fork case above: nobody
# has ever fetched this branch, so refs/remotes/origin/<branch> is simply
# absent. The probe must fall through to a plain checkout without crashing,
# and without ever handing merge-base a ref that doesn't exist (which is what
# the guard being dropped would do, spilling git's own fatal onto stderr).
pr_meta 711 feat/pr-auto-missing-ref false
# Fetched by raw SHA rather than through cached_object/seed_leftover_branch:
# fetching a branch BY NAME opportunistically populates
# refs/remotes/origin/<branch> as a side effect (real git behavior, confirmed
# independently of any refspec configured), which would defeat the one thing
# this fixture needs — that the tracking ref is genuinely absent. Fetching
# the raw object id instead pulls the commit with no branch name attached, so
# nothing gets auto-tracked.
sha_711=$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/pr-auto-missing-ref | cut -f1)
git -C "$PRIMARY" fetch -q origin "$sha_711"
git -C "$PRIMARY" branch feat/pr-auto-missing-ref "$sha_711" >/dev/null
check_fails 'the origin tracking ref does not exist yet for this branch' \
  git -C "$PRIMARY" rev-parse -q --verify refs/remotes/origin/feat/pr-auto-missing-ref
launch_reset
missing_ref_out=$(clwt pr 711 2>&1)
missing_ref_rc=$?
# Exit 0 alone is not enough: a merge-base fail-closed catch-all would ALSO
# exit 0 here even if it were handed a ref that does not exist yet — the only
# way to tell "the guard skipped calling merge-base" from "merge-base was
# called and happened to fail closed" is git's own noisy fatal on stderr,
# which the guard exists specifically to keep this path from ever producing.
if ((missing_ref_rc == 0)); then
  check_not_contains 'pr with a missing origin tracking ref falls through to a plain checkout' \
    'Not a valid object name' "$missing_ref_out"
else
  not_ok 'pr with a missing origin tracking ref falls through to a plain checkout'
fi

# No leftover branch at all — branch_existed stays 0 and the probe never
# runs; the plain, pre-Task-3 path is unaffected.
pr_meta 712 feat/pr-auto-none false
launch_reset
check 'pr with no leftover branch is unaffected by the probe' clwt pr 712
check_equals 'pr with no leftover branch still names the worktree from the head ref' \
  "$MANAGED/feat-pr-auto-none" "$(launched pwd)"

# A failed --force checkout already means the reset it suggests just failed to
# help — re-suggesting the identical command would be circular. checkoutFails
# makes gh's own checkout fail unconditionally; the seeded local branch is what
# would make the old, branch_existed-only gate print the hint anyway.
pr_meta 713 feat/pr-force-hint-fail false
printf 'checkoutFails=true\n' >>"$CLWT_GH_PRS/713"
git -C "$PRIMARY" branch feat/pr-force-hint-fail >/dev/null
launch_reset
force_hint_out=$(clwt pr 713 --force 2>&1)
force_hint_rc=$?
check 'a failed --force checkout still exits non-zero' \
  test "$force_hint_rc" -ne 0
check_not_contains 'a failed --force checkout does not re-suggest --force' \
  "--force' to reset it" "$force_hint_out"

# Metadata fixture seeded through pr_meta first (so a REAL head exists on
# $REMOTE), then overwritten with an empty isCrossRepository — a
# malformed/absent value from gh that the old `!= true` gate would admit into
# the auto-force decision as "not cross-repository". The real head is what
# makes the exit-code check load-bearing: with the validation deleted, the
# checkout would simply SUCCEED (fresh branch, no divergence), so rc=0 — not
# fail for the unrelated missing-remote-ref reason.
pr_meta 714 feat/pr-cross-empty false
printf 'headRefName=feat/pr-cross-empty\nisCrossRepository=\n' >"$CLWT_GH_PRS/714"
launch_reset
cross_empty_out=$(clwt pr 714 2>&1)
cross_empty_rc=$?
check 'pr dies when isCrossRepository is empty rather than admitting it to the auto-force decision' \
  test "$cross_empty_rc" -ne 0
check_contains 'that refusal explains it cannot determine fork status' \
  'cannot determine whether pull request #714 comes from a fork' "$cross_empty_out"
check_not_contains 'that refusal never reaches the auto-reset note' \
  'resetting' "$cross_empty_out"

# An adversarial head ref: a leading dash is valid PR metadata content but an
# invalid branch name, and unquoted would be read as a flag by anything it's
# passed to. No PR head can be pushed for it ($REMOTE refuses the ref name), so
# the exit-code check alone would pass via the stub's fetch failure — the
# message assertion below is the load-bearing one for validate_branch.
printf 'headRefName=-dash\nisCrossRepository=false\n' >"$CLWT_GH_PRS/715"
launch_reset
adversarial_out=$(clwt pr 715 2>&1)
adversarial_rc=$?
check 'pr rejects an adversarial head ref before any git plumbing runs' \
  test "$adversarial_rc" -ne 0
check_contains 'that refusal names the invalid branch name' \
  'invalid branch name: -dash' "$adversarial_out"

section 'gh stub self-checks'

# stub_checkout <pr-number> [gh-args...] — invokes the gh stub's `pr checkout`
# exactly the way `clwt pr` does: from inside a fresh detached worktree of
# $PRIMARY, so a leftover local branch (which shares $PRIMARY's ref namespace)
# behaves exactly as it would under the real command. These self-checks pin the
# stub directly — ahead of and independent from any clwt-side behavior — so later
# probe tests can trust that a checkout failing (or succeeding) means what it
# says.
stub_checkout() {
  local number=$1
  shift
  local wt="$TMP/stub-checkout-$number"
  rm -rf "$wt"
  git -C "$PRIMARY" worktree add --detach --quiet "$wt" HEAD >/dev/null 2>&1
  (cd "$wt" && gh pr checkout "$number" "$@")
  local rc=$?
  git -C "$PRIMARY" worktree remove --force "$wt" >/dev/null 2>&1
  return $rc
}

pr_meta 601 feat/stub-tracking-ref false
# Force-advance the PR head before checkout, so this exercises the exact
# real-world case: $PRIMARY has never fetched this branch at all, and the head
# it eventually sees is not even the one pr_meta originally pushed.
force_advance_pr_head feat/stub-tracking-ref >/dev/null
new_head_601=$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/stub-tracking-ref | cut -f1)
check_fails 'the origin tracking ref does not exist before the first checkout' \
  git -C "$PRIMARY" rev-parse -q --verify refs/remotes/origin/feat/stub-tracking-ref
check 'gh stub checkout succeeds for a fresh pull request fixture' stub_checkout 601
check_equals 'gh stub updates the origin tracking ref as a side effect of checkout' \
  "$new_head_601" "$(git -C "$PRIMARY" rev-parse -q --verify refs/remotes/origin/feat/stub-tracking-ref)"

pr_meta 602 feat/stub-diverged false
seed_leftover_branch feat/stub-diverged diverged
diverged_before=$(git -C "$PRIMARY" rev-parse feat/stub-diverged)
check_fails 'gh stub refuses a plain checkout over a diverged local branch' \
  stub_checkout 602
check_equals 'a refused diverged checkout leaves the local branch tip untouched' \
  "$diverged_before" "$(git -C "$PRIMARY" rev-parse feat/stub-diverged)"

pr_meta 603 feat/stub-force false
seed_leftover_branch feat/stub-force diverged
check 'gh stub resets a diverged local branch when given --force' \
  stub_checkout 603 --force
check_equals 'the force-reset local branch now matches the pull request head exactly' \
  "$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/stub-force | cut -f1)" \
  "$(git -C "$PRIMARY" rev-parse feat/stub-force)"

# A fixture written without going through pr_meta/push_pr_head — the metadata
# names a head branch that was never pushed to $REMOTE.
printf 'headRefName=feat/stub-never-pushed\nisCrossRepository=false\n' >"$CLWT_GH_PRS/604"
check_fails 'gh stub fails loudly when the fixture has no head branch on the remote' \
  stub_checkout 604
check_output 'the fail-loudly message names the missing remote ref' \
  "couldn't find remote ref" stub_checkout 604
check_fails 'a missing remote head is never papered over by creating the branch at HEAD' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/stub-never-pushed

pr_meta 605 feat/stub-ahead false
seed_leftover_branch feat/stub-ahead ahead
ahead_before=$(git -C "$PRIMARY" rev-parse feat/stub-ahead)
check 'gh stub allows a plain checkout over a branch ahead of the pull request head' \
  stub_checkout 605
check_equals 'a checkout over an ahead branch does not move its tip' \
  "$ahead_before" "$(git -C "$PRIMARY" rev-parse feat/stub-ahead)"

section 'seed_leftover_branch fixture helper'

# Both relationships, confirmed independently of the gh stub via rev-parse /
# merge-base, so a bug in the helper itself cannot hide behind a bug in the stub.
# cached_object, not a bare ls-remote: merge-base needs the remote tip's commit
# OBJECT present in $PRIMARY, and "diverged" force-advances the remote without
# fetching the new tip anywhere. A raw SHA string from ls-remote would make
# merge-base error on an unknown object — which check_fails below would then
# pass on for the wrong reason, masking a missing fetch entirely.
pr_meta 613 feat/relation-ahead false
seed_leftover_branch feat/relation-ahead ahead
ahead_head=$(cached_object feat/relation-ahead)
check 'seed_leftover_branch ahead: the pull request head is a strict ancestor of the local tip' \
  git -C "$PRIMARY" merge-base --is-ancestor "$ahead_head" feat/relation-ahead
check_fails 'seed_leftover_branch ahead: the local tip is not itself an ancestor of the pull request head' \
  git -C "$PRIMARY" merge-base --is-ancestor feat/relation-ahead "$ahead_head"

pr_meta 614 feat/relation-diverged false
seed_leftover_branch feat/relation-diverged diverged
diverged_head=$(cached_object feat/relation-diverged)
check_fails 'seed_leftover_branch diverged: neither tip is an ancestor of the other (local to remote)' \
  git -C "$PRIMARY" merge-base --is-ancestor feat/relation-diverged "$diverged_head"
check_fails 'seed_leftover_branch diverged: neither tip is an ancestor of the other (remote to local)' \
  git -C "$PRIMARY" merge-base --is-ancestor "$diverged_head" feat/relation-diverged

# The "held nowhere" contract: a branch checked out elsewhere must be refused,
# not silently rewritten. git's own worktree-branch protection would also block
# the eventual `git branch -f` here, so a bare exit-code check would pass even
# with our guard deleted — passing for the wrong reason. The side-effect check
# below is the one that actually depends on our guard: without it,
# force_advance_pr_head would already have force-pushed to $REMOTE before
# git's own protection ever got a chance to refuse the branch move.
pr_meta 615 feat/relation-held false
initial_head_615=$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/relation-held | cut -f1)
git -C "$PRIMARY" worktree add -q -b feat/relation-held "$MANAGED/feat-relation-held" >/dev/null 2>&1
check_fails 'seed_leftover_branch refuses a branch that is already checked out somewhere' \
  seed_leftover_branch feat/relation-held diverged
check_equals 'that refusal happens before any $REMOTE mutation, not after a failed git branch -f' \
  "$initial_head_615" "$(git -C "$PRIMARY" ls-remote origin refs/heads/feat/relation-held | cut -f1)"
git -C "$PRIMARY" worktree remove --force "$MANAGED/feat-relation-held" >/dev/null 2>&1

section 'bash completion'

COMPLETION="$REPO_ROOT/claude/scripts/clwt-completion.bash"

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

# macOS ships bash 3.2, where `mapfile` does not exist: it leaves COMPREPLY empty
# and every completion assertion below then passes or fails for that reason
# instead of the one under test. A static check, because the behavioral checks
# cannot catch this — reintroducing mapfile keeps them green on a bash 4 machine
# and silently blinds them on a stock Mac, which is how 10 of them sat unrunnable
# here for months.
if sed 's/#.*//' "$COMPLETION" | grep -qE '\b(mapfile|readarray)\b'; then
  not_ok 'the completion script avoids bash 4-only builtins'
else
  ok 'the completion script avoids bash 4-only builtins'
fi

# Source-level assertions, because these two mitigations cannot be exercised
# through the COMP_WORDS harness — `compopt` errors outside a real completion,
# and `compgen -W` re-expansion is a generation-time property. Without them the
# suite stays green with either mitigation deleted, which is exactly the
# untested-guard failure this suite has already been bitten by.
if sed 's/#.*//' "$COMPLETION" | grep -q 'compgen -W "\$('; then
  not_ok 'no untrusted command output is passed to compgen -W'
else
  ok 'no untrusted command output is passed to compgen -W'
fi

# readline inserts an accepted match unquoted, so on a unique match Tab rewrites
# the line and Enter expands it. `-o filenames` makes the insertion literal.
untrusted_arms=$(sed 's/#.*//' "$COMPLETION" |
  grep -c '_clwt_add_matches "\$cur"')
quoted_arms=$(sed 's/#.*//' "$COMPLETION" | grep -c 'compopt -o filenames')
if [ "$untrusted_arms" -gt 0 ] && [ "$quoted_arms" -ge "$untrusted_arms" ]; then
  ok 'every untrusted completion arm quotes its insertion with -o filenames'
else
  not_ok "every untrusted completion arm quotes its insertion with -o filenames ($quoted_arms quoted / $untrusted_arms untrusted)"
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

  # `compgen -W` performs full word expansion — including command substitution —
  # on its word list, and `git check-ref-format` accepts a branch named
  # `feat/x$(...)`. Passing branch names through it is remote code execution on
  # Tab, with no subcommand run and no confirmation. Verified live before the fix.
  # The payload writes a RELATIVE path deliberately. An absolute one embeds $TMP
  # in a git ref name, and refs reject what paths allow: a `//` — which is what
  # $TMP becomes whenever $TMPDIR carries a trailing slash, as macOS's default
  # /var/folders/.../T/ always does — makes `git branch` refuse the name. The
  # branch then never exists, so this test failed with an empty `got:` while the
  # two "does not execute it" checks passed vacuously, having no payload to run.
  # Completions below run with cwd $PRIMARY, so an executed payload lands there.
  RCE_MARKER="$PRIMARY/rce-marker"
  rm -f "$RCE_MARKER"
  HOSTILE_BRANCH='feat/x$(touch${IFS}rce-marker)'
  hostile_branch_err=$(git -C "$PRIMARY" branch "$HOSTILE_BRANCH" 2>&1)
  # Asserted, not assumed: every check below this point is meaningless if the
  # fixture is absent, and two of them are negatives that go quiet rather than red.
  if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$HOSTILE_BRANCH"; then
    ok 'the hostile branch fixture exists'
  else
    not_ok "the hostile branch fixture exists ($hostile_branch_err)"
  fi

  hostile_completions=$(complete_for clwt branch 'feat/x')
  if [ -e "$RCE_MARKER" ]; then
    not_ok 'completing a hostile branch name does not execute it'
  else
    ok 'completing a hostile branch name does not execute it'
  fi
  if printf '%s\n' "$hostile_completions" | grep -qF 'touch'; then
    ok 'the hostile branch name is offered verbatim as inert text'
  else
    not_ok "the hostile branch name is offered verbatim as inert text (got: $hostile_completions)"
  fi

  rm -f "$RCE_MARKER"
  managed_hostile=$(complete_for clwt open 'feat/x')
  if [ -e "$RCE_MARKER" ]; then
    not_ok 'completing a hostile managed branch name does not execute it'
  else
    ok 'completing a hostile managed branch name does not execute it'
  fi
  git -C "$PRIMARY" branch -D "$HOSTILE_BRANCH" >/dev/null 2>&1

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

  # pr was split out of the shared --yolo arm to also offer --force, without
  # the parser rejecting --force on the other four subcommands.
  pr_flags=$(complete_for clwt pr 701 '--')
  if printf '%s\n' "$pr_flags" | grep -qx -- '--force'; then
    ok 'completion offers --force for pr'
  else
    not_ok 'completion offers --force for pr'
  fi
  if printf '%s\n' "$pr_flags" | grep -qx -- '--yolo'; then
    ok 'completion still offers --yolo for pr'
  else
    not_ok 'completion still offers --yolo for pr'
  fi
  # Positive control first: an empty completion result (e.g. mapfile missing on
  # bash 3.2) would satisfy the bare negative no matter what the flags arm
  # contains — the assertion must prove completion WORKS before proving --force
  # is absent from it.
  branch_flags=$(complete_for clwt branch feat/alpha '--')
  if printf '%s\n' "$branch_flags" | grep -qx -- '--yolo' &&
    ! printf '%s\n' "$branch_flags" | grep -qx -- '--force'; then
    ok 'completion does not offer --force for branch'
  else
    not_ok 'completion does not offer --force for branch'
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

SKILL="$REPO_ROOT/claude/skills/clwt/SKILL.md"
SETTINGS="$REPO_ROOT/claude/settings.json"
REGROUND="$REPO_ROOT/claude/skills/reground/SKILL.md"

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
  resolved="$REPO_ROOT/claude/skills/clwt/${target%%#*}"
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
check 'the README documents the pr --force flag' grep -qF -- '--force' "$README"
check 'the clwt skill documents the pr --force flag' grep -qF -- '--force' "$SKILL"
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
