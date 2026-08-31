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

check_ref_absent() {
  local label=$1 ref=$2
  if "$PWT_TEST_REAL_GIT" -C "$PRIMARY" show-ref --verify --quiet "$ref"; then
    not_ok "$label"
  else
    ok "$label"
  fi
}

worktree_registered_at() {
  git -C "$PRIMARY" worktree list --porcelain |
    grep -qF "worktree $1"
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

export PWT_TEST_REAL_GIT PWT_TEST_REAL_MKDIR PWT_TEST_REAL_CP
PWT_TEST_REAL_GIT=$(command -v git)
PWT_TEST_REAL_MKDIR=$(command -v mkdir)
PWT_TEST_REAL_CP=$(command -v cp)

# Git boundary stub: normal calls delegate unchanged. A named failure mode lets
# the suite prove pwt distinguishes Git errors from ordinary missing records.
cat >"$BIN/git" <<'STUB'
#!/usr/bin/env bash
args=" $* "
case ${PWT_TEST_GIT_FAIL:-} in
  worktree-list)
    case $args in *' worktree list --porcelain '*) exit 70 ;; esac
    ;;
  worktree-list-after-first)
    case $args in
      *' worktree list --porcelain '*)
        count=0
        if [ -f "$PWT_TEST_GIT_COUNT" ]; then
          IFS= read -r count <"$PWT_TEST_GIT_COUNT"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$PWT_TEST_GIT_COUNT"
        [ "$count" -le 1 ] || exit 70
        ;;
    esac
    ;;
  show-ref)
    case $args in *' show-ref --verify --quiet refs/heads/'*) exit 70 ;; esac
    ;;
  ls-remote)
    case $args in *' ls-remote --symref origin HEAD '*) exit 70 ;; esac
    ;;
  include-ls-files)
    case $args in
      *' ls-files --others --ignored --exclude-from='*) exit 70 ;;
    esac
    ;;
  include-escaping-path)
    case $args in
      *' ls-files --others --ignored --exclude-from='*)
        printf '../outside\0'
        exit 0
        ;;
    esac
    ;;
  worktree-remove)
    case $args in *' worktree remove --force '*) exit 70 ;; esac
    ;;
  worktree-add-after-create)
    case $args in
      *' worktree add '*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        exit 70
        ;;
    esac
    ;;
  hold-worktree-add)
    case $args in
      *' worktree add '*)
        : >"$PWT_TEST_ADD_READY"
        attempts=0
        while [ ! -e "$PWT_TEST_ADD_RELEASE" ]; do
          attempts=$((attempts + 1))
          [ "$attempts" -lt 200 ] || exit 75
          sleep 0.05
        done
        ;;
    esac
    ;;
  inject-target-symlink)
    case $args in
      *' fetch --quiet origin '*)
        rm -rf "$PWT_TEST_INJECT_TARGET"
        ln -s "$PWT_TEST_INJECT_OUTSIDE" "$PWT_TEST_INJECT_TARGET"
        ;;
    esac
    ;;
esac
exec "$PWT_TEST_REAL_GIT" "$@"
STUB
chmod +x "$BIN/git"

# Filesystem boundary stubs delegate by default. Focused modes let the suite
# deterministically exercise a post-mkdir substitution race and a copy error.
cat >"$BIN/mkdir" <<'STUB'
#!/usr/bin/env bash
if [ -n "${PWT_TEST_MKDIR_FAIL:-}" ] &&
  [ "$#" -eq 1 ] && [ "$1" = "$PWT_TEST_MKDIR_FAIL" ]; then
  exit 73
fi
if [ -n "${PWT_TEST_MKDIR_SWAP:-}" ] &&
  [ "$#" -eq 2 ] && [ "$1" = -p ] && [ "$2" = "$PWT_TEST_MKDIR_SWAP" ]; then
  "$PWT_TEST_REAL_MKDIR" "$@" || exit
  rm -rf "$PWT_TEST_MKDIR_SWAP"
  ln -s "$PWT_TEST_MKDIR_OUTSIDE" "$PWT_TEST_MKDIR_SWAP"
  exit
fi
exec "$PWT_TEST_REAL_MKDIR" "$@"
STUB
chmod +x "$BIN/mkdir"

cat >"$BIN/cp" <<'STUB'
#!/usr/bin/env bash
[ "${PWT_TEST_CP_FAIL:-}" != 1 ] || exit 74
exec "$PWT_TEST_REAL_CP" "$@"
STUB
chmod +x "$BIN/cp"

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

# Stub `gh`: PR metadata and checkout behavior come from files the tests own.
# Checkout uses real Git so branch relationships, fetch side effects, and
# failures remain observable instead of being mocked inside pwt.
export PWT_GH_UNAVAILABLE="$TMP/gh-unavailable"
export PWT_GH_PRS="$TMP/gh-prs"
export PWT_GH_LOG="$TMP/gh.log"
mkdir -p "$PWT_GH_PRS"
: >"$PWT_GH_LOG"
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
if [ -f "$PWT_GH_UNAVAILABLE" ]; then
  printf 'gh: could not authenticate\n' >&2
  exit 1
fi
if [ "$1" = auth ] && [ "$2" = status ]; then
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ]; then
  meta="$PWT_GH_PRS/$3"
  if [ ! -f "$meta" ]; then
    printf 'could not resolve pull request %s\n' "$3" >&2
    exit 1
  fi
  sed -n 's/^headRefName=//p' "$meta"
  sed -n 's/^isCrossRepository=//p' "$meta"
  sed -n 's/^headRepositoryOwner=//p' "$meta"
  sed -n 's/^headRepository=//p' "$meta"
  sed -n 's/^url=//p' "$meta"
  sed -n 's/^headRefOid=//p' "$meta"
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = checkout ]; then
  printf '%s\n' "$*" >>"$PWT_GH_LOG"
  number=$3
  meta="$PWT_GH_PRS/$number"
  if [ ! -f "$meta" ]; then
    printf 'could not resolve pull request %s\n' "$number" >&2
    exit 1
  fi
  if grep -q '^checkoutFails=true$' "$meta"; then
    printf "fatal: couldn't find remote ref\n" >&2
    exit 1
  fi
  head_ref=$(sed -n 's/^headRefName=//p' "$meta")
  force=0
  detach=0
  shift 3
  for arg in "$@"; do
    [ "$arg" = --force ] && force=1
    [ "$arg" = --detach ] && detach=1
  done
  if ! git fetch -q origin \
    "+refs/heads/$head_ref:refs/remotes/origin/$head_ref" 2>/dev/null; then
    printf "fatal: couldn't find remote ref %s\n" "$head_ref" >&2
    exit 1
  fi
  if [ "$detach" = 1 ]; then
    if grep -q '^checkoutOidMismatch=true$' "$meta"; then
      git checkout -q --detach HEAD
    else
      git checkout -q --detach "refs/remotes/origin/$head_ref"
    fi
    exit $?
  fi
  if grep -q '^checkoutOidMismatch=true$' "$meta"; then
    if git show-ref --verify --quiet "refs/heads/$head_ref"; then
      git checkout -q "$head_ref"
    else
      git checkout -q -b "$head_ref" HEAD
    fi
    exit $?
  fi
  if grep -q '^checkoutWrongBranch=true$' "$meta"; then
    git checkout -q -b "wrong-$head_ref" "refs/remotes/origin/$head_ref"
    exit $?
  fi
  if ! git show-ref --verify --quiet "refs/heads/$head_ref"; then
    git checkout -q -b "$head_ref" "refs/remotes/origin/$head_ref"
    exit $?
  fi
  git checkout -q "$head_ref" || exit 1
  if [ "$force" = 1 ]; then
    git reset -q --hard "refs/remotes/origin/$head_ref"
    exit $?
  fi
  git merge --ff-only "refs/remotes/origin/$head_ref" >/dev/null
  exit $?
fi
exit 0
STUB
chmod +x "$BIN/gh"

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

# Move the remote default after the clone. The clone's cached origin/HEAD stays
# on main, so a later `pwt new` only sees stable.txt when it asks origin for the
# current default instead of trusting stale local metadata.
(
  cd "$TMP/seed" || exit 1
  git checkout -q -b stable
  printf 'stable\n' >stable.txt
  git add stable.txt
  git commit -qm 'add stable branch'
  git push -q origin stable
)
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/stable

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

# PR metadata always points at a real remote branch. The scratch clone pushes
# heads without warming the primary checkout's tracking refs.
SCRATCH_PUSH="$TMP/scratch-push"
ensure_scratch_push() {
  [ -d "$SCRATCH_PUSH" ] || git clone -q "$REMOTE" "$SCRATCH_PUSH" >/dev/null 2>&1
}
push_pr_head() {
  local branch=$1 sha
  ensure_scratch_push
  sha=$(git -C "$SCRATCH_PUSH" commit-tree \
    "$(git -C "$SCRATCH_PUSH" rev-parse HEAD^{tree})" \
    -p HEAD -m "initial head for $branch ($RANDOM$RANDOM)") || return 1
  git -C "$SCRATCH_PUSH" push -q -f origin "$sha:refs/heads/$branch" || return 1
  printf '%s\n' "$sha"
}
pr_meta() {
  local oid
  oid=$(push_pr_head "$2") || return 1
  printf 'headRefName=%s\nisCrossRepository=%s\nheadRepositoryOwner=%s\nheadRepository=%s\nurl=%s\nheadRefOid=%s\n' \
    "$2" "$3" "${4:-owner}" "${5:-project}" \
    "https://github.com/owner/project/pull/$1" "$oid" >"$PWT_GH_PRS/$1"
}

sync_pr_metadata_oid() {
  local branch=$1 oid=$2 meta tmp
  for meta in "$PWT_GH_PRS"/*; do
    [ -f "$meta" ] || continue
    [ "$(sed -n 's/^headRefName=//p' "$meta")" = "$branch" ] || continue
    tmp="$meta.tmp"
    sed "s/^headRefOid=.*/headRefOid=$oid/" "$meta" >"$tmp" || return 1
    mv "$tmp" "$meta" || return 1
  done
}

cached_object() {
  local branch=$1
  git -C "$PRIMARY" fetch -q origin \
    "refs/heads/$branch:refs/pr-fixture-cache/$branch" 2>/dev/null || return 1
  git -C "$PRIMARY" rev-parse "refs/pr-fixture-cache/$branch"
}

force_advance_pr_head() {
  local branch=$1 old_tip new_sha
  ensure_scratch_push
  git -C "$SCRATCH_PUSH" fetch -q origin "refs/heads/$branch" >/dev/null 2>&1
  old_tip=$(git -C "$SCRATCH_PUSH" ls-remote origin \
    "refs/heads/$branch" | cut -f1)
  [ -n "$old_tip" ] || return 1
  new_sha=$(git -C "$SCRATCH_PUSH" commit-tree \
    "$(git -C "$SCRATCH_PUSH" rev-parse "$old_tip^{tree}")" \
    -p "$old_tip" -m "advance $branch ($RANDOM$RANDOM)") || return 1
  git -C "$SCRATCH_PUSH" push -q -f origin \
    "$new_sha:refs/heads/$branch" || return 1
  sync_pr_metadata_oid "$branch" "$new_sha" || return 1
  printf '%s\n' "$new_sha"
}

# Creates a sibling of the selected base commit, making the new PR head
# genuinely non-fast-forwardable from that base.
rewrite_pr_head() {
  local branch=$1 base=${2:-} new_sha
  ensure_scratch_push
  if [ -z "$base" ]; then
    git -C "$SCRATCH_PUSH" fetch -q origin \
      "refs/heads/$branch" >/dev/null 2>&1
    base=$(git -C "$SCRATCH_PUSH" ls-remote origin \
      "refs/heads/$branch" | cut -f1)
  fi
  [ -n "$base" ] || return 1
  new_sha=$(git -C "$SCRATCH_PUSH" commit-tree \
    "$(git -C "$SCRATCH_PUSH" rev-parse "$base^{tree}")" \
    -p "$base^" -m "rewrite $branch ($RANDOM$RANDOM)") || return 1
  [ -n "$new_sha" ] || return 1
  git -C "$SCRATCH_PUSH" push -q -f origin \
    "$new_sha:refs/heads/$branch" || return 1
  sync_pr_metadata_oid "$branch" "$new_sha" || return 1
  printf '%s\n' "$new_sha"
}

new_commit_on() {
  git -C "$PRIMARY" commit-tree \
    "$(git -C "$PRIMARY" rev-parse "$1^{tree}")" \
    -p "$1" -m "seed: $2 ($RANDOM$RANDOM)"
}

seed_leftover_branch() {
  local branch=$1 relation=$2 base local_sha
  if git -C "$PRIMARY" worktree list --porcelain |
    grep -qxF "branch refs/heads/$branch"; then
    return 1
  fi
  base=$(cached_object "$branch") || return 1
  case $relation in
    ahead)
      local_sha=$(new_commit_on "$base" "ahead of $branch") || return 1
      ;;
    diverged)
      force_advance_pr_head "$branch" >/dev/null || return 1
      local_sha=$(new_commit_on "$base" "diverged from $branch") || return 1
      ;;
    *) return 1 ;;
  esac
  git -C "$PRIMARY" branch -f "$branch" "$local_sha" >/dev/null
}

fetch_stale_tracking_ref() {
  local branch=$1
  git -C "$PRIMARY" fetch -q origin \
    "refs/heads/$branch:refs/remotes/origin/$branch"
}

assert_pr_oid_matches_remote() {
  local number=$1 branch expected actual
  branch=$(sed -n 's/^headRefName=//p' "$PWT_GH_PRS/$number")
  expected=$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/$number")
  actual=$(git -C "$PRIMARY" ls-remote origin "refs/heads/$branch" | cut -f1)
  check_equals "fixture PR #$number metadata OID matches its remote head" \
    "$actual" "$expected"
}

# Replace a PR head with a tracked .env shape that collides with an ignored
# local path. A throwaway clone keeps the fixture out of the primary checkout.
push_pr_tree_shape() {
  local number=$1 branch=$2 shape=$3 clone oid
  clone="$TMP/tree-shape-$number"
  git clone -q "$REMOTE" "$clone" >/dev/null 2>&1 || return 1
  git -C "$clone" fetch -q origin "refs/heads/$branch" || return 1
  git -C "$clone" checkout -q --detach FETCH_HEAD || return 1
  case $shape in
    exact-file | file-ancestor)
      printf 'tracked by pull request\n' >"$clone/.env"
      git -C "$clone" add -f .env || return 1
      ;;
    symlink-ancestor)
      ln -s tracked-target "$clone/.env"
      git -C "$clone" add -f .env || return 1
      ;;
    directory)
      mkdir -p "$clone/.env"
      printf 'tracked by pull request\n' >"$clone/.env/child"
      git -C "$clone" add -f .env/child || return 1
      ;;
    *) return 1 ;;
  esac
  git -C "$clone" -c commit.gpgsign=false commit -qm \
    "change .env tree shape for $branch" || return 1
  oid=$(git -C "$clone" rev-parse HEAD) || return 1
  git -C "$clone" push -q -f origin \
    "$oid:refs/heads/$branch" || return 1
  sync_pr_metadata_oid "$branch" "$oid" || return 1
  printf '%s\n' "$oid"
}

# A moderately wide target tree makes the old ignored-path x tree-entry nested
# scan miss the five-second budget while the batched implementation stays fast.
push_pr_wide_tree() {
  local number=$1 branch=$2 clone oid i=0
  clone="$TMP/wide-tree-$number"
  git clone -q "$REMOTE" "$clone" >/dev/null 2>&1 || return 1
  git -C "$clone" fetch -q origin "refs/heads/$branch" || return 1
  git -C "$clone" checkout -q --detach FETCH_HEAD || return 1
  mkdir -p "$clone/tracked-perf"
  while [ "$i" -lt 250 ]; do
    printf 'tracked by pull request\n' >"$clone/tracked-perf/file-$i"
    i=$((i + 1))
  done
  git -C "$clone" add tracked-perf || return 1
  git -C "$clone" -c commit.gpgsign=false commit -qm \
    "add wide tree for $branch" || return 1
  oid=$(git -C "$clone" rev-parse HEAD) || return 1
  git -C "$clone" push -q -f origin \
    "$oid:refs/heads/$branch" || return 1
  sync_pr_metadata_oid "$branch" "$oid" || return 1
  printf '%s\n' "$oid"
}

within_scan_budget() {
  local directory=$1 command_pid watchdog_pid rc
  shift
  (
    cd "$directory" || exit 1
    exec "$@"
  ) &
  command_pid=$!
  (
    sleep 5
    kill -TERM "$command_pid" >/dev/null 2>&1 || true
  ) &
  watchdog_pid=$!
  wait "$command_pid"
  rc=$?
  kill "$watchdog_pid" >/dev/null 2>&1 || true
  wait "$watchdog_pid" >/dev/null 2>&1 || true
  return "$rc"
}

FAILGIT="$TMP/failgit"
mkdir -p "$FAILGIT"
make_failing_git() {
  local failed_command=$1 real_git
  real_git=$(command -v git)
  cat >"$FAILGIT/git" <<STUB
#!/usr/bin/env bash
for argument in "\$@"; do
  if [ "\$argument" = "$failed_command" ]; then
    echo "fatal: simulated git failure" >&2
    exit 128
  fi
done
exec "$real_git" "\$@"
STUB
  chmod +x "$FAILGIT/git"
}

pwt_with_failing_git() {
  PATH="$FAILGIT:$PATH" pwt "$@"
}

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
pwt_git_fail() {
  local failure=$1
  shift
  (export PWT_TEST_GIT_FAIL="$failure"; pwt "$@")
}
pwt_git_fail_after_first_worktree_list() {
  local counter="$TMP/git-worktree-list-count"
  : >"$counter"
  (
    export PWT_TEST_GIT_FAIL=worktree-list-after-first
    export PWT_TEST_GIT_COUNT="$counter"
    pwt "$@"
  )
}
pwt_inject_target_symlink() {
  local target=$1 outside=$2
  shift 2
  (
    export PWT_TEST_GIT_FAIL=inject-target-symlink
    export PWT_TEST_INJECT_TARGET="$target"
    export PWT_TEST_INJECT_OUTSIDE="$outside"
    pwt "$@"
  )
}
pwt_swap_after_mkdir() {
  local destination=$1 outside=$2
  shift 2
  (
    export PWT_TEST_MKDIR_SWAP="$destination"
    export PWT_TEST_MKDIR_OUTSIDE="$outside"
    pwt "$@"
  )
}
pwt_cp_fail() {
  (export PWT_TEST_CP_FAIL=1; pwt "$@")
}
pwt_mkdir_fail() {
  local path=$1
  shift
  (export PWT_TEST_MKDIR_FAIL="$path"; pwt "$@")
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
if grep -Eq '(^|[[:space:]])(mapfile|readarray|declare[[:space:]]+-A)([[:space:]]|$)' \
  "$PWT" 2>/dev/null; then
  not_ok 'the pwt script avoids Bash 4-only array features'
else
  ok 'the pwt script avoids Bash 4-only array features'
fi
check_equals 'the clone origin/HEAD is stale relative to the remote default' \
  'refs/heads/main|stable' \
  "$(git -C "$PRIMARY" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/|refs/heads/|')|$(git -C "$PRIMARY" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p')"

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

# ----------------------------------------------------------------------- list

section 'list'

# probe/roots is managed. Add a second worktree outside the shared root so list
# must show it without claiming ownership of it.
UNMANAGED="$HOME/elsewhere/stray"
mkdir -p "$HOME/elsewhere"
git -C "$PRIMARY" worktree add -q -b feat/stray "$UNMANAGED" 2>/dev/null
UNMANAGED=$(cd "$UNMANAGED" && pwd -P)

check_output 'list shows a managed worktree by branch name' 'probe/roots' pwt list
check_output 'list shows the managed worktree path' "$WORKTREE" pwt list
check_output 'list marks a worktree outside the shared managed root as unmanaged' \
  'unmanaged' pwt list
check_output 'list shows the unmanaged branch' 'feat/stray' pwt list
LIST_SYMLINK="$MANAGED/feat-list-symlink"
git -C "$PRIMARY" worktree add -q -b feat/list-symlink "$LIST_SYMLINK" 2>/dev/null
rm -rf "$LIST_SYMLINK"
ln -s "$UNMANAGED" "$LIST_SYMLINK"
list_symlink_line=$(pwt list 2>&1 | grep -F 'feat/list-symlink' || true)
check_contains 'list marks a physically escaped symlinked registration as unmanaged' \
  'unmanaged' "$list_symlink_line"
rm -f "$LIST_SYMLINK"

check_equals 'pwt with no arguments prints the worktree list' \
  "$(pwt list 2>&1)" "$(pwt 2>&1)"
check_fails 'list rejects extra arguments' pwt list nonsense
check_fails 'list fails closed when Git cannot enumerate worktrees' \
  pwt_git_fail worktree-list list
check_output 'list reports the Git enumeration failure instead of an empty state' \
  'cannot list repository worktrees' pwt_git_fail worktree-list list

if pwt list 2>&1 | grep -qF "$PRIMARY "; then
  not_ok 'list does not present the primary checkout as a managed worktree'
else
  ok 'list does not present the primary checkout as a managed worktree'
fi

git clone -q "$REMOTE" "$HOME/github/owner/lonely"
check_output 'list reports plainly when the repository has no linked worktrees' \
  'No managed worktrees' pwt_in "$HOME/github/owner/lonely" list

# ----------------------------------------------------------------------- open

section 'open'

launch_reset
pwt open probe/roots -- --model 'open space' '' >/dev/null 2>&1
check_equals 'open launches Pi only from the registered managed physical worktree' \
  "$WORKTREE" "$(launched pwd)"
check_equals 'open exports the physical primary checkout' \
  "$PRIMARY" "$(launched PWT_REPO_ROOT)"
check_equals 'open preserves the forwarded argument count' '3' "$(launched argc)"
check_arg_equals 'open preserves a forwarded argument containing spaces' 1 'open space'
check_arg_equals 'open preserves a forwarded empty argument' 2 ''

check_fails 'open refuses a registered worktree outside the managed root' \
  pwt open feat/stray
check_output 'open explains that the unmanaged worktree is outside pwt ownership' \
  'manage' pwt open feat/stray
check_fails 'open refuses a branch with no registered worktree' \
  pwt open feat/never-existed
check_fails 'open requires exactly one branch' pwt open
check_fails 'open rejects an invalid branch name' pwt open 'not a branch'

launch_reset
check_fails 'open fails closed when Git cannot enumerate registered worktrees' \
  pwt_git_fail worktree-list open probe/roots
check_output 'open reports the Git enumeration failure' \
  'cannot list repository worktrees' pwt_git_fail worktree-list open probe/roots
check_equals 'a failed open lookup never launches Pi' '' "$(launched pwd)"

# Registration metadata alone is not ownership proof. Replacing the registered
# path with a plain directory or another worktree's .git link must fail identity
# validation before Pi is launched.
REPLACED="$MANAGED/feat-replaced"
git -C "$PRIMARY" worktree add -q -b feat/replaced "$REPLACED" 2>/dev/null
rm -rf "$REPLACED"
mkdir -p "$REPLACED"
launch_reset
check_fails 'open refuses a registered path replaced by an ordinary directory' \
  pwt open feat/replaced
check_equals 'ordinary-directory replacement never launches Pi' '' "$(launched pwd)"

WRONG_IDENTITY="$MANAGED/feat-wrong-identity"
git -C "$PRIMARY" worktree add -q -b feat/wrong-identity "$WRONG_IDENTITY" 2>/dev/null
rm -rf "$WRONG_IDENTITY"
mkdir -p "$WRONG_IDENTITY"
cp "$WORKTREE/.git" "$WRONG_IDENTITY/.git"
launch_reset
check_fails 'open refuses a registered path replaced by the wrong worktree identity' \
  pwt open feat/wrong-identity
check_equals 'wrong-worktree replacement never launches Pi' '' "$(launched pwd)"

# The link points to a sibling inside the managed root. Containment alone would
# accept it, so this proves the symlink guard itself decides the rejection.
SYMLINKED="$MANAGED/feat-symlinked"
git -C "$PRIMARY" worktree add -q -b feat/symlinked "$SYMLINKED" 2>/dev/null
rm -rf "$SYMLINKED"
ln -s "$WORKTREE" "$SYMLINKED"
check_fails 'open refuses a symlink substituted for a registered managed worktree' \
  pwt open feat/symlinked
check_output 'open reports its managed-path symlink guard' \
  'must not be a symlink' pwt open feat/symlinked
rm -f "$SYMLINKED"

# ------------------------------------------------------------------------ new

section 'new'

launch_reset
pwt new feat/alpha -- --model 'space value' >/dev/null 2>&1
check 'new creates a typed branch in the managed root' \
  test -d "$MANAGED/feat-alpha"
check_equals 'new launches Pi from the physical worktree it created' \
  "$MANAGED/feat-alpha" "$(launched pwd)"
check 'new bases the branch on the current origin default, not cached origin/HEAD' \
  test -f "$MANAGED/feat-alpha/stable.txt"
check_equals 'new forwards normal Pi arguments after -- unchanged' \
  '2' "$(launched argc)"
check_arg_equals 'new preserves a forwarded argument containing spaces' \
  1 'space value'

alpha_before=$(git -C "$MANAGED/feat-alpha" rev-parse HEAD)
launch_reset
pwt new feat/alpha >/dev/null 2>&1
check_equals 'new reuses an existing managed worktree' \
  "$MANAGED/feat-alpha" "$(launched pwd)"
check_equals 'new reuse preserves the checked-out branch head' \
  "$alpha_before" "$(git -C "$MANAGED/feat-alpha" rev-parse HEAD)"

check_fails 'new rejects a branch without a type prefix' pwt new noprefix
check_output 'new explains that a typed branch is required' 'feat/' pwt new noprefix
check_fails 'new rejects an invalid git branch name' pwt new 'feat/bad..name'
check_output 'new reports its branch-validation guard for an invalid git ref' \
  'invalid branch name' pwt new 'feat/bad..name'
check_fails 'new rejects a path-traversing branch name' pwt new 'feat/../../evil'
check_fails 'new rejects whitespace in a branch name' pwt new 'feat/a b'
check 'git accepts the semicolon branch used to isolate the path-segment guard' \
  git -C "$PRIMARY" check-ref-format --branch 'feat/a;b'
check_fails 'new rejects a ref-valid branch unsafe as a path segment' \
  pwt new 'feat/a;b'
check_output 'new reports its safe path-segment guard' \
  'safe directory name' pwt new 'feat/a;b'
check_fails 'new requires exactly one branch' pwt new
check 'branch validation cannot escape the managed root' \
  test ! -e "$HOME/github/.worktrees/owner/evil"

mkdir -p "$MANAGED/feat-occupied"
check_fails 'new refuses an unregistered directory occupying its target path' \
  pwt new feat/occupied
check_output 'new names the unregistered target-path problem' \
  'not a registered worktree' pwt new feat/occupied
rmdir "$MANAGED/feat-occupied"

ln -s "$MANAGED/feat-alpha" "$MANAGED/feat-symlink-target"
check_fails 'new refuses a symlink at its target path' \
  pwt new feat/symlink-target
check_output 'new reports its target-path symlink guard' \
  'target path must not be a symlink' pwt new feat/symlink-target
rm -f "$MANAGED/feat-symlink-target"

# An existing local branch belongs to `branch`, not `new`. Pin its object ID so
# the rejection cannot silently reset or otherwise mutate it.
git -C "$PRIMARY" branch feat/dormant >/dev/null 2>&1
dormant_before=$(git -C "$PRIMARY" rev-parse refs/heads/feat/dormant)
launch_reset
check_fails 'new rejects an existing unchecked local branch' \
  pwt new feat/dormant
check_output 'new directs an existing local branch to pwt branch' \
  'pwt branch' pwt new feat/dormant
check_equals 'new preserves the existing local branch head' \
  "$dormant_before" "$(git -C "$PRIMARY" rev-parse refs/heads/feat/dormant)"
check_equals 'new does not launch Pi after rejecting an existing local branch' \
  '' "$(launched pwd)"

launch_reset
check_fails 'new fails closed when Git cannot enumerate existing worktrees' \
  pwt_git_fail worktree-list new feat/worktree-query-failure
check_output 'new reports its failed worktree query' \
  'cannot list repository worktrees' \
  pwt_git_fail worktree-list new feat/worktree-query-failure
check_ref_absent 'a failed new worktree query leaves the requested branch absent' \
  refs/heads/feat/worktree-query-failure
check_equals 'a failed new worktree query never launches Pi' '' "$(launched pwd)"

launch_reset
check_fails 'new fails closed when the target-registration query fails' \
  pwt_git_fail_after_first_worktree_list new feat/late-worktree-query-failure
check_output 'new reports the failed target-registration query' \
  'cannot list repository worktrees' \
  pwt_git_fail_after_first_worktree_list new feat/late-worktree-query-failure
check_ref_absent 'a failed target-registration query leaves the branch absent' \
  refs/heads/feat/late-worktree-query-failure
check_equals 'a failed target-registration query never launches Pi' \
  '' "$(launched pwd)"

launch_reset
check_fails 'new fails closed when Git cannot inspect the local branch ref' \
  pwt_git_fail show-ref new feat/ref-query-failure
check_output 'new reports its failed local-ref query' \
  'cannot inspect local branch' pwt_git_fail show-ref new feat/ref-query-failure
check_equals 'a failed local-ref query never launches Pi' '' "$(launched pwd)"

launch_reset
check_fails 'new fails closed when Git cannot resolve the remote default' \
  pwt_git_fail ls-remote new feat/default-query-failure
check_output 'new reports its failed remote-default query' \
  'cannot determine the current origin default branch' \
  pwt_git_fail ls-remote new feat/default-query-failure
check_equals 'a failed remote-default query never launches Pi' '' "$(launched pwd)"

# Inject the target symlink during fetch, after the first availability check.
# A second check at the mutation boundary must stop Git from populating outside.
RACE_TARGET="$MANAGED/feat-race"
RACE_OUTSIDE="$TMP/race-outside"
mkdir -p "$RACE_OUTSIDE"
launch_reset
race_status=0
race_output=$(pwt_inject_target_symlink \
  "$RACE_TARGET" "$RACE_OUTSIDE" new feat/race 2>&1) || race_status=$?
if [ "$race_status" -ne 0 ]; then
  ok 'new fails closed when its target is substituted during fetch'
else
  not_ok 'new fails closed when its target is substituted during fetch'
fi
# The exact pre-write guard matters: the post-add identity check also refuses
# the launch, but only after Git has already populated the substituted target.
check_contains 'new revalidates the target immediately before Git writes' \
  'target path must not be a symlink' "$race_output"
check 'pre-write revalidation keeps Git from populating the outside directory' \
  test ! -e "$RACE_OUTSIDE/.git"
check_equals 'target substitution never launches Pi' '' "$(launched pwd)"

# --------------------------------------------------------------------- branch

section 'branch'

launch_reset
pwt branch feat/dormant -- --model 'local space' '' >/dev/null 2>&1
check 'branch checks out an existing local branch in the managed root' \
  test -d "$MANAGED/feat-dormant"
check_equals 'branch launches Pi from the local branch worktree' \
  "$MANAGED/feat-dormant" "$(launched pwd)"
check_equals 'local branch launch preserves the forwarded argument count' \
  '3' "$(launched argc)"
check_arg_equals 'local branch launch preserves an argument containing spaces' \
  1 'local space'
check_arg_equals 'local branch launch preserves an empty argument' 2 ''

(
  cd "$TMP/seed" || exit 1
  git checkout -q -b feat/remote-only
  printf 'remote only\n' >remote-only.txt
  git add remote-only.txt
  git commit -qm 'add remote-only branch'
  git push -q origin feat/remote-only
)
launch_reset
pwt branch feat/remote-only -- --model 'remote space' '' >/dev/null 2>&1
check 'branch checks out a branch that exists only on origin' \
  test -f "$MANAGED/feat-remote-only/remote-only.txt"
check_equals 'branch launches Pi from the origin branch worktree' \
  "$MANAGED/feat-remote-only" "$(launched pwd)"
check_equals 'origin branch launch preserves the forwarded argument count' \
  '3' "$(launched argc)"
check_arg_equals 'origin branch launch preserves an argument containing spaces' \
  1 'remote space'
check_arg_equals 'origin branch launch preserves an empty argument' 2 ''

# The origin-only path has its own fetch-to-write boundary. Keep its regression
# separate from `new` so deleting either duplicate guard is observable.
(
  cd "$TMP/seed" || exit 1
  git checkout -q -b feat/branch-race stable
  printf 'branch race\n' >branch-race.txt
  git add branch-race.txt
  git commit -qm 'add branch race branch'
  git push -q origin feat/branch-race
)
BRANCH_RACE_TARGET="$MANAGED/feat-branch-race"
BRANCH_RACE_OUTSIDE="$TMP/branch-race-outside"
mkdir -p "$BRANCH_RACE_OUTSIDE"
launch_reset
branch_race_status=0
branch_race_output=$(pwt_inject_target_symlink \
  "$BRANCH_RACE_TARGET" "$BRANCH_RACE_OUTSIDE" \
  branch feat/branch-race 2>&1) || branch_race_status=$?
if [ "$branch_race_status" -ne 0 ]; then
  ok 'branch fails closed when its target is substituted during fetch'
else
  not_ok 'branch fails closed when its target is substituted during fetch'
fi
check_contains 'branch revalidates the target immediately before Git writes' \
  'target path must not be a symlink' "$branch_race_output"
check 'branch pre-write revalidation keeps Git from populating outside' \
  test ! -e "$BRANCH_RACE_OUTSIDE/.git"
check_ref_absent 'target substitution leaves the requested local branch absent' \
  refs/heads/feat/branch-race
check_equals 'branch target substitution never launches Pi' '' "$(launched pwd)"

launch_reset
check_fails 'branch fails closed for a branch absent locally and on origin' \
  pwt branch feat/nonexistent
check_equals 'a missing branch never launches Pi' '' "$(launched pwd)"
check_fails 'branch requires exactly one branch' pwt branch
check_fails 'branch rejects an invalid branch name' pwt branch 'feat/a b'

launch_reset
check_fails 'branch fails closed when Git cannot enumerate existing worktrees' \
  pwt_git_fail worktree-list branch feat/branch-worktree-query-failure
check_output 'branch reports its failed worktree query' \
  'cannot list repository worktrees' \
  pwt_git_fail worktree-list branch feat/branch-worktree-query-failure
check_ref_absent 'a failed branch worktree query leaves the local ref absent' \
  refs/heads/feat/branch-worktree-query-failure
check_equals 'a failed branch worktree query never launches Pi' '' "$(launched pwd)"

launch_reset
check_fails 'branch fails closed when Git cannot inspect the local branch ref' \
  pwt_git_fail show-ref branch feat/branch-ref-query-failure
check_output 'branch reports its failed local-ref query' \
  'cannot inspect local branch' \
  pwt_git_fail show-ref branch feat/branch-ref-query-failure
check_equals 'a failed branch local-ref query never launches Pi' '' "$(launched pwd)"

# A registered worktree already under the managed root is safe to reuse.
launch_reset
pwt branch feat/alpha >/dev/null 2>&1
check_equals 'branch reuses an existing managed worktree' \
  "$MANAGED/feat-alpha" "$(launched pwd)"

# Git permits each branch in only one worktree. The primary checkout and an
# unmanaged linked worktree need distinct, useful refusal paths.
primary_branch=$(git -C "$PRIMARY" symbolic-ref --short HEAD)
check_fails 'branch refuses a branch checked out in the primary checkout' \
  pwt branch "$primary_branch"
check_output 'the primary-checkout refusal suggests pwt root' \
  'pwt root' pwt branch "$primary_branch"
check_fails 'branch refuses a branch checked out in an unmanaged worktree' \
  pwt branch feat/stray
check_output 'the unmanaged-worktree refusal names its physical path' \
  "$UNMANAGED" pwt branch feat/stray
check_output 'the unmanaged-worktree refusal identifies the checked-out branch location' \
  'is checked out at' pwt branch feat/stray

# feat/a-b and feat/a/b flatten to the same directory. The second `new` must
# fail before `git worktree add -b` can leak the requested local branch.
launch_reset
pwt new feat/a-b >/dev/null 2>&1
launch_reset
check_fails 'slash-flattened branch names fail closed on a target collision' \
  pwt new feat/a/b
check_equals 'the target collision preserves the original checked-out branch' \
  'feat/a-b' "$(git -C "$MANAGED/feat-a-b" symbolic-ref --short HEAD)"
check_ref_absent 'the new target collision does not leak a local branch' \
  refs/heads/feat/a/b
check_equals 'the target collision never launches Pi' '' "$(launched pwd)"

# A missing registered directory does not trip the ordinary filesystem
# occupancy check. Only the registration guard can prevent `worktree add -b`
# from creating the flattened branch before Git reports the stale record.
pwt new feat/stale-base >/dev/null 2>&1
rm -rf "$MANAGED/feat-stale-base"
launch_reset
check_fails 'a stale registered target fails closed on a flattened collision' \
  pwt new feat/stale/base
check_output 'the stale target collision reports its registration conflict' \
  'already registered' pwt new feat/stale/base
check_ref_absent 'the stale target collision does not leak a local branch' \
  refs/heads/feat/stale/base
check_equals 'the stale target collision never launches Pi' '' "$(launched pwd)"

# The same collision must be caught before an origin-only branch is fetched and
# materialized locally.
pwt new feat/origin-collision >/dev/null 2>&1
(
  cd "$TMP/seed" || exit 1
  git checkout -q -b feat/origin/collision
  printf 'origin collision\n' >origin-collision.txt
  git add origin-collision.txt
  git commit -qm 'add origin collision branch'
  git push -q origin feat/origin/collision
)
launch_reset
check_fails 'origin-only slash-flattened collision fails before checkout' \
  pwt branch feat/origin/collision
check_ref_absent 'the origin-only target collision does not leak a local branch' \
  refs/heads/feat/origin/collision
check_equals 'the origin-only target collision never launches Pi' '' "$(launched pwd)"

# A Git transport failure must leave neither a partial worktree nor a launched
# session. Keep the remote identity shape valid so the fetch is the failing seam.
git -C "$PRIMARY" remote set-url origin "$TMP/missing/owner/project.git"
launch_reset
check_fails 'branch fails closed when Git cannot fetch the requested branch' \
  pwt branch feat/git-failure
check_output 'branch reports the failed remote lookup without continuing' \
  'no such branch locally or on origin' pwt branch feat/git-failure
check 'a failed fetch leaves no target worktree behind' \
  test ! -e "$MANAGED/feat-git-failure"
check_equals 'a failed fetch never launches Pi' '' "$(launched pwd)"
git -C "$PRIMARY" remote set-url origin "$REMOTE"

# ------------------------------------------------------- pull request checkout

section 'pr-checkout'

pr_meta 101 feat/from-pr false
pr_meta 102 feat/forked true fork-owner project
printf '.env\n' >"$PRIMARY/.worktreeinclude"
printf 'PR_SECRET=1\n' >"$PRIMARY/.env"

launch_reset
pr_out=$(pwt pr 101 2>&1)
check 'pr checks out the pull request into a managed worktree' \
  test -d "$MANAGED/feat-from-pr"
check_equals 'pr names the worktree from the pull request head ref' \
  "$MANAGED/feat-from-pr" "$(launched pwd)"
check 'pr launches Pi in the pull request worktree' test -n "$(launched pwd)"
check 'pr prepares worktreeinclude files before launch' \
  test -f "$MANAGED/feat-from-pr/.env"
check_equals 'the PR worktree is on the expected head branch' \
  'feat/from-pr' \
  "$(git -C "$MANAGED/feat-from-pr" symbolic-ref --short HEAD 2>/dev/null)"
check_equals 'the PR worktree matches the advertised head object' \
  "$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/101")" \
  "$(git -C "$MANAGED/feat-from-pr" rev-parse HEAD 2>/dev/null)"
check_not_contains 'a same-repository pull request prints no fork warning' \
  'comes from a fork' "$pr_out"
check_equals 'fresh PR checkout invokes gh checkout exactly once' \
  '1' "$(grep -c '^pr checkout 101' "$PWT_GH_LOG")"
check_equals 'fresh PR checkout records its canonical URL marker' \
  'https://github.com/owner/project/pull/101' \
  "$(git -C "$PRIMARY" config --get branch.feat/from-pr.worktree-pr-url 2>/dev/null)"
check_equals 'fresh PR checkout records its exact head marker' \
  "$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/101")" \
  "$(git -C "$PRIMARY" config --get branch.feat/from-pr.worktree-pr-head 2>/dev/null)"
check 'fresh PR checkout clears its preparation marker' \
  test ! -e "$PRIMARY/.git/pwt/preparing-feat-from-pr"

launch_reset
fork_out=$(pwt pr 102 2>&1)
check_contains 'pr warns before launching a fork pull request' \
  'pull request #102 comes from a fork' "$fork_out"
check_equals 'pr still launches after the fork warning' \
  "$MANAGED/feat-forked" "$(launched pwd)"

pr_meta 103 feat/pr-passthrough false
launch_reset
pwt pr 103 -- --force --model 'space value' '' >/dev/null 2>&1
check_equals 'arguments after -- are forwarded to Pi unchanged' '4' "$(launched argc)"
check_arg_equals 'a post-separator --force reaches Pi literally' 0 '--force'
check_arg_equals 'a forwarded Pi option remains unchanged' 1 '--model'
check_arg_equals 'a forwarded value preserves spaces' 2 'space value'
check_arg_equals 'a forwarded empty argument remains present' 3 ''

# gh can fail after the detached worktree already exists. The partial tree and
# its preparation ownership must both be cleared so an explicit retry is clean.
pr_meta 104 feat/deleted-pr-head false
printf 'checkoutFails=true\n' >>"$PWT_GH_PRS/104"
launch_reset
check_fails 'pr exits non-zero when gh cannot check the pull request out' pwt pr 104
check 'failed PR checkout leaves no worktree directory behind' \
  test ! -e "$MANAGED/feat-deleted-pr-head"
check_fails 'failed PR checkout unregisters its partial worktree' \
  worktree_registered_at "$MANAGED/feat-deleted-pr-head"
check 'failed PR checkout clears its preparation marker after cleanup' \
  test ! -e "$PRIMARY/.git/pwt/preparing-feat-deleted-pr-head"
check_equals 'failed PR checkout never launches Pi' '' "$(launched pwd)"
check_fails 'retry after failed PR checkout fails cleanly again' pwt pr 104

pr_meta 105 feat/pr-copy-failure false
launch_reset
check_fails 'include-copy failure aborts PR worktree preparation' \
  pwt_cp_fail pr 105
check 'include-copy failure removes the PR worktree directory' \
  test ! -e "$MANAGED/feat-pr-copy-failure"
check_fails 'include-copy failure unregisters the PR worktree' \
  worktree_registered_at "$MANAGED/feat-pr-copy-failure"
check_equals 'include-copy failure never launches Pi' '' "$(launched pwd)"

check_fails 'pr requires a pull request number' pwt pr
check_fails 'pr rejects a non-numeric pull request number' pwt pr not-a-number
check_fails 'pr rejects an unknown option before the separator' pwt pr 101 --wat
check_fails 'pr exits non-zero when the pull request does not exist' pwt pr 999
check_output 'pr names the unresolved pull request number' '999' pwt pr 999

touch "$PWT_GH_UNAVAILABLE"
check_fails 'pr exits non-zero when gh is unavailable' pwt pr 101
check_output 'pr explains that authenticated gh is required' 'pr needs gh' pwt pr 101
rm -f "$PWT_GH_UNAVAILABLE"

pr_meta 106 feat/pr-invalid-oid false
sed 's/^headRefOid=.*/headRefOid=not-an-object/' "$PWT_GH_PRS/106" \
  >"$PWT_GH_PRS/106.tmp"
mv "$PWT_GH_PRS/106.tmp" "$PWT_GH_PRS/106"
launch_reset
check_fails 'pr rejects malformed head object metadata' pwt pr 106
check_equals 'malformed head object metadata never launches Pi' '' "$(launched pwd)"

pr_meta 107 feat/pr-invalid-url false
sed 's#^url=.*#url=not-a-canonical-pr-url#' "$PWT_GH_PRS/107" \
  >"$PWT_GH_PRS/107.tmp"
mv "$PWT_GH_PRS/107.tmp" "$PWT_GH_PRS/107"
launch_reset
check_fails 'pr rejects malformed canonical URL metadata' pwt pr 107
check_equals 'malformed canonical URL metadata never launches Pi' '' "$(launched pwd)"

pr_meta 108 feat/pr-cross-empty false
sed 's/^isCrossRepository=.*/isCrossRepository=/' "$PWT_GH_PRS/108" \
  >"$PWT_GH_PRS/108.tmp"
mv "$PWT_GH_PRS/108.tmp" "$PWT_GH_PRS/108"
launch_reset
check_fails 'pr rejects missing fork-status metadata' pwt pr 108
check_equals 'missing fork-status metadata never launches Pi' '' "$(launched pwd)"

printf 'headRefName=-dash\nisCrossRepository=false\n' >"$PWT_GH_PRS/109"
launch_reset
check_output 'pr rejects a hostile head ref before Git plumbing' \
  'invalid branch name: -dash' pwt pr 109
check_equals 'a hostile head ref never launches Pi' '' "$(launched pwd)"

pr_meta 110 feat/pr-oid-mismatch false
printf 'checkoutOidMismatch=true\n' >>"$PWT_GH_PRS/110"
launch_reset
check_fails 'pr refuses checkout when HEAD differs from metadata' pwt pr 110
check 'checkout object mismatch leaves no worktree behind' \
  test ! -e "$MANAGED/feat-pr-oid-mismatch"
check_equals 'checkout object mismatch never launches Pi' '' "$(launched pwd)"

pr_meta 111 feat/pr-wrong-branch false
printf 'checkoutWrongBranch=true\n' >>"$PWT_GH_PRS/111"
launch_reset
check_fails 'pr refuses checkout under the wrong local branch' pwt pr 111
check 'wrong-branch checkout leaves no worktree behind' \
  test ! -e "$MANAGED/feat-pr-wrong-branch"
check_equals 'wrong-branch checkout never launches Pi' '' "$(launched pwd)"

rm -f "$PRIMARY/.worktreeinclude" "$PRIMARY/.env"

# ---------------------------------------------------------- PR force decisions

section 'pr-force'

pr_meta 201 feat/pr-force-diverged false
seed_leftover_branch feat/pr-force-diverged diverged
launch_reset
check 'pr --force resets a diverged leftover branch to the PR head' \
  pwt pr 201 --force
check_equals 'explicit force lands exactly on the advertised PR head' \
  "$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/201")" \
  "$(git -C "$PRIMARY" rev-parse feat/pr-force-diverged)"

pr_meta 202 feat/pr-force-fresh false
launch_reset
check 'pr --force also works without a leftover local branch' pwt pr 202 --force
check_equals 'fresh explicit force launches Pi in the PR worktree' \
  "$MANAGED/feat-pr-force-fresh" "$(launched pwd)"

# Equal to the stale origin tip, followed by a genuine history rewrite. Plain
# gh checkout cannot fast-forward this fixture; only safe auto-force can pass.
pr_meta 203 feat/pr-auto-equal false
old_203=$(cached_object feat/pr-auto-equal)
fetch_stale_tracking_ref feat/pr-auto-equal
git -C "$PRIMARY" branch feat/pr-auto-equal "$old_203" >/dev/null
rewrite_pr_head feat/pr-auto-equal >/dev/null
new_203=$(git -C "$PRIMARY" ls-remote origin \
  refs/heads/feat/pr-auto-equal | cut -f1)
check_fails 'the equal-tip fixture is genuinely non-fast-forwardable' \
  git -C "$SCRATCH_PUSH" merge-base --is-ancestor "$old_203" "$new_203"
launch_reset
equal_status=0
equal_out=$(pwt pr 203 2>&1) || equal_status=$?
check_equals 'pr auto-resets a leftover branch equal to pre-fetch origin' \
  '0' "$equal_status"
check_equals 'the equal-tip auto-reset lands at the PR head' \
  "$new_203" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-equal)"
check_contains 'auto-reset reports the branch it safely resets' \
  'resetting feat/pr-auto-equal' "$equal_out"

# Strictly behind the stale tracking ref, then rewritten away from both.
pr_meta 204 feat/pr-auto-behind false
old_204=$(cached_object feat/pr-auto-behind)
force_advance_pr_head feat/pr-auto-behind >/dev/null
fetch_stale_tracking_ref feat/pr-auto-behind
rewrite_pr_head feat/pr-auto-behind "$old_204" >/dev/null
git -C "$PRIMARY" branch feat/pr-auto-behind "$old_204" >/dev/null
new_204=$(git -C "$PRIMARY" ls-remote origin \
  refs/heads/feat/pr-auto-behind | cut -f1)
check_fails 'the behind fixture is genuinely non-fast-forwardable' \
  git -C "$SCRATCH_PUSH" merge-base --is-ancestor "$old_204" "$new_204"
launch_reset
check 'pr auto-resets a leftover branch strictly behind origin' pwt pr 204
check_equals 'the behind auto-reset lands at the PR head' \
  "$new_204" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-behind)"

pr_meta 205 feat/pr-auto-diverged false
seed_leftover_branch feat/pr-auto-diverged diverged
diverged_before=$(git -C "$PRIMARY" rev-parse feat/pr-auto-diverged)
launch_reset
diverged_status=0
diverged_out=$(pwt pr 205 2>&1) || diverged_status=$?
check 'pr refuses a leftover branch with local-only commits' \
  test "$diverged_status" -ne 0
check_contains 'diverged refusal suggests explicit force' \
  'pwt pr 205 --force' "$diverged_out"
check_equals 'diverged refusal preserves the local branch tip' \
  "$diverged_before" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-diverged)"
check 'diverged refusal leaves no managed worktree behind' \
  test ! -e "$MANAGED/feat-pr-auto-diverged"
check_equals 'diverged refusal never launches Pi' '' "$(launched pwd)"

# These branches are contained, so dropping either repository-identity gate
# would visibly take the auto-reset path.
pr_meta 206 feat/pr-auto-fork true Owner Project
old_206=$(cached_object feat/pr-auto-fork)
fetch_stale_tracking_ref feat/pr-auto-fork
git -C "$PRIMARY" branch feat/pr-auto-fork "$old_206" >/dev/null
launch_reset
fork_force_out=$(pwt pr 206 2>&1)
check_not_contains 'pr never auto-resets a cross-repository pull request' \
  'resetting feat/pr-auto-fork' "$fork_force_out"

pr_meta 207 feat/pr-auto-elsewhere false other-owner project
old_207=$(cached_object feat/pr-auto-elsewhere)
fetch_stale_tracking_ref feat/pr-auto-elsewhere
git -C "$PRIMARY" branch feat/pr-auto-elsewhere "$old_207" >/dev/null
launch_reset
elsewhere_out=$(pwt pr 207 2>&1)
check_not_contains 'pr never auto-resets when origin is not the head repository' \
  'resetting feat/pr-auto-elsewhere' "$elsewhere_out"

pr_meta 208 feat/pr-auto-case false Owner Project
old_208=$(cached_object feat/pr-auto-case)
fetch_stale_tracking_ref feat/pr-auto-case
git -C "$PRIMARY" branch feat/pr-auto-case "$old_208" >/dev/null
launch_reset
case_out=$(pwt pr 208 2>&1)
check_contains 'repository identity comparison is case-insensitive' \
  'resetting feat/pr-auto-case' "$case_out"

# A local branch ahead of the PR makes gh's ff-only operation a no-op success.
# Exact-head verification must still refuse launch and preserve the branch.
pr_meta 209 feat/pr-auto-ahead false
seed_leftover_branch feat/pr-auto-ahead ahead
ahead_before=$(git -C "$PRIMARY" rev-parse feat/pr-auto-ahead)
launch_reset
ahead_status=0
ahead_out=$(pwt pr 209 2>&1) || ahead_status=$?
check 'pr refuses a leftover branch ahead of the PR head' \
  test "$ahead_status" -ne 0
check_equals 'ahead refusal preserves the local branch tip' \
  "$ahead_before" "$(git -C "$PRIMARY" rev-parse feat/pr-auto-ahead)"
check 'ahead refusal removes the temporary managed worktree' \
  test ! -e "$MANAGED/feat-pr-auto-ahead"
check_contains 'ahead refusal reports the exact-head mismatch' \
  'changed while it was being checked out' "$ahead_out"
check_equals 'ahead refusal never launches Pi' '' "$(launched pwd)"

# The missing tracking ref is normal for a never-fetched PR branch. The safety
# probe must skip merge-base cleanly, then let gh fetch and check it out.
pr_meta 210 feat/pr-auto-missing-ref false
sha_210=$(git -C "$PRIMARY" ls-remote origin \
  refs/heads/feat/pr-auto-missing-ref | cut -f1)
git -C "$PRIMARY" fetch -q origin "$sha_210"
git -C "$PRIMARY" branch feat/pr-auto-missing-ref "$sha_210" >/dev/null
check_fails 'the missing-ref fixture has no origin tracking ref' \
  git -C "$PRIMARY" rev-parse -q --verify \
    refs/remotes/origin/feat/pr-auto-missing-ref
launch_reset
missing_ref_status=0
missing_ref_out=$(pwt pr 210 2>&1) || missing_ref_status=$?
check_equals 'a missing origin tracking ref falls through safely' \
  '0' "$missing_ref_status"
check_not_contains 'missing tracking refs never reach noisy merge-base input' \
  'Not a valid object name' "$missing_ref_out"

pr_meta 211 feat/pr-auto-none false
launch_reset
check 'pr with no leftover branch remains a plain checkout' pwt pr 211
check_equals 'plain PR checkout still uses the head-ref worktree name' \
  "$MANAGED/feat-pr-auto-none" "$(launched pwd)"

pr_meta 212 feat/pr-force-hint-fail false
printf 'checkoutFails=true\n' >>"$PWT_GH_PRS/212"
git -C "$PRIMARY" branch feat/pr-force-hint-fail >/dev/null
launch_reset
force_failure_status=0
force_failure_out=$(pwt pr 212 --force 2>&1) || force_failure_status=$?
check 'failed explicit-force checkout exits non-zero' \
  test "$force_failure_status" -ne 0
check_not_contains 'failed explicit force does not suggest force again' \
  "--force' to reset it" "$force_failure_out"

pr_meta 213 feat/pr-cross-hint true fork-owner project
printf 'checkoutFails=true\n' >>"$PWT_GH_PRS/213"
git -C "$PRIMARY" branch feat/pr-cross-hint >/dev/null
launch_reset
cross_failure_out=$(pwt pr 213 2>&1 || true)
check_contains 'failed fork checkout still suggests force for a leftover branch' \
  'pwt pr 213 --force' "$cross_failure_out"

check_fails 'branch rejects --force as an unknown option' pwt branch --force
check_fails 'root rejects --force as an unknown option' pwt root --force
check_output 'help documents explicit PR force behavior' \
  'resetting a leftover' pwt help
check_output 'help documents the safe automatic reset' \
  'provably contained' pwt help

# ------------------------------------------------------ reused PR refresh safety

section 'pr-reuse'

pr_marker() {
  git -C "$PRIMARY" config --get "branch.$1.$2" 2>/dev/null || true
}

# Reused worktrees may contain intentionally local ignored configuration.
exclude_file="$PRIMARY/.git/info/exclude"
printf '.env\n' >>"$exclude_file"

printf '.env\n' >"$PRIMARY/.worktreeinclude"
printf 'REUSE_SECRET=keep-me\n' >"$PRIMARY/.env"
pr_meta 301 feat/pr-reuse-refresh false
assert_pr_oid_matches_remote 301
launch_reset
check 'initial PR checkout succeeds before reuse refresh tests' pwt pr 301
check_equals 'initial PR checkout records its canonical URL marker' \
  'https://github.com/owner/project/pull/301' \
  "$(pr_marker feat/pr-reuse-refresh worktree-pr-url)"
check_equals 'initial PR checkout records its exact head marker' \
  "$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/301")" \
  "$(pr_marker feat/pr-reuse-refresh worktree-pr-head)"
check_equals 'initial PR checkout copied the ignored local file' \
  'REUSE_SECRET=keep-me' "$(cat "$MANAGED/feat-pr-reuse-refresh/.env")"
rm -f "$PRIMARY/.worktreeinclude"

force_advance_pr_head feat/pr-reuse-refresh >/dev/null
assert_pr_oid_matches_remote 301
launch_reset
check 'pr refreshes a clean reused worktree after a fast-forward' pwt pr 301
check_equals 'fast-forward reuse launches the exact current PR head' \
  "$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/301")" \
  "$(git -C "$MANAGED/feat-pr-reuse-refresh" rev-parse HEAD)"
check_equals 'fast-forward reuse preserves ignored local content' \
  'REUSE_SECRET=keep-me' "$(cat "$MANAGED/feat-pr-reuse-refresh/.env")"

rewrite_pr_head feat/pr-reuse-refresh >/dev/null
assert_pr_oid_matches_remote 301
launch_reset
check 'pr refreshes a rewritten head from its last verified commit' pwt pr 301
check_equals 'rewritten reuse launches the exact current PR head' \
  "$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/301")" \
  "$(git -C "$MANAGED/feat-pr-reuse-refresh" rev-parse HEAD)"
check_equals 'rewritten reuse preserves ignored local content' \
  'REUSE_SECRET=keep-me' "$(cat "$MANAGED/feat-pr-reuse-refresh/.env")"
launch_reset
check 'reused PR launches still accept forwarded Pi arguments' \
  pwt pr 301 -- --model 'review value'
check_arg_equals 'reused PR preserves a forwarded Pi argument unchanged' \
  1 'review value'

pr_meta 302 feat/pr-reuse-dirty false
pwt pr 302 >/dev/null 2>&1
dirty_head=$(git -C "$MANAGED/feat-pr-reuse-dirty" rev-parse HEAD)
dirty_tracking_head=$(git -C "$PRIMARY" rev-parse \
  refs/remotes/origin/feat/pr-reuse-dirty)
printf 'dirty\n' >>"$MANAGED/feat-pr-reuse-dirty/README.md"
force_advance_pr_head feat/pr-reuse-dirty >/dev/null
launch_reset
check_fails 'pr refuses a dirty reused worktree before refresh' pwt pr 302
check_equals 'dirty refusal preserves the worktree head' "$dirty_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-dirty" rev-parse HEAD)"
check_equals 'dirty refusal preserves the last verified head marker' "$dirty_head" \
  "$(pr_marker feat/pr-reuse-dirty worktree-pr-head)"
check_equals 'dirty refusal happens before the disposable PR fetch' "$dirty_tracking_head" \
  "$(git -C "$PRIMARY" rev-parse refs/remotes/origin/feat/pr-reuse-dirty)"
check_equals 'dirty refusal never launches Pi' '' "$(launched pwd)"

pr_meta 303 feat/pr-reuse-local-commit false
pwt pr 303 >/dev/null 2>&1
printf 'local\n' >"$MANAGED/feat-pr-reuse-local-commit/local.txt"
git -C "$MANAGED/feat-pr-reuse-local-commit" add local.txt
git -C "$MANAGED/feat-pr-reuse-local-commit" -c commit.gpgsign=false \
  commit -qm 'local work'
local_head=$(git -C "$MANAGED/feat-pr-reuse-local-commit" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-local-commit >/dev/null
launch_reset
check_fails 'pr refuses local commits in a reused worktree even with --force' \
  pwt pr 303 --force
check_equals 'local-commit refusal preserves the branch head' "$local_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-local-commit" rev-parse HEAD)"
check 'local-commit refusal preserves the committed file' \
  test -f "$MANAGED/feat-pr-reuse-local-commit/local.txt"
check_equals 'local-commit refusal never launches Pi' '' "$(launched pwd)"

pr_meta 304 feat/pr-reuse-fork-name true fork-one project
pwt pr 304 >/dev/null 2>&1
pr_meta 305 feat/pr-reuse-fork-name true fork-two project
fork_head=$(git -C "$MANAGED/feat-pr-reuse-fork-name" rev-parse HEAD)
launch_reset
check_fails 'pr refuses a same-named reused branch from a different fork PR' pwt pr 305
check_equals 'wrong-fork refusal preserves the original branch head' "$fork_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-fork-name" rev-parse HEAD)"
check_equals 'wrong-fork refusal preserves the original PR URL marker' \
  'https://github.com/owner/project/pull/304' \
  "$(pr_marker feat/pr-reuse-fork-name worktree-pr-url)"
check_equals 'wrong-fork refusal never launches Pi' '' "$(launched pwd)"

pr_meta 306 feat/pr-reuse-unverified false
unverified_oid=$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/306")
git -C "$PRIMARY" fetch -q origin "$unverified_oid"
git -C "$PRIMARY" branch feat/pr-reuse-unverified "$unverified_oid" >/dev/null
git -C "$PRIMARY" worktree add -q "$MANAGED/feat-pr-reuse-unverified" \
  feat/pr-reuse-unverified
launch_reset
check_fails 'pr refuses a markerless reused worktree with no tracking identity' pwt pr 306
check_equals 'unverified identity refusal never launches Pi' '' "$(launched pwd)"

pr_meta 307 feat/pr-reuse-partial-marker false
pwt pr 307 >/dev/null 2>&1
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-partial-marker.worktree-pr-head
launch_reset
check_fails 'pr refuses a reused worktree with only half its identity markers' pwt pr 307
check_equals 'partial-marker refusal never launches Pi' '' "$(launched pwd)"

pr_meta 308 feat/pr-reuse-malformed-marker false
pwt pr 308 >/dev/null 2>&1
git -C "$PRIMARY" config \
  branch.feat/pr-reuse-malformed-marker.worktree-pr-head not-an-object
launch_reset
check_fails 'pr refuses a malformed last-verified head marker' pwt pr 308
check_equals 'malformed-marker refusal never launches Pi' '' "$(launched pwd)"

# Markerless worktrees from older versions can migrate only from native Git
# tracking evidence. Rewrites require a recorded last-verified head.
pr_meta 309 feat/pr-reuse-legacy-ff false
pwt pr 309 >/dev/null 2>&1
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-legacy-ff.worktree-pr-url
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-legacy-ff.worktree-pr-head
force_advance_pr_head feat/pr-reuse-legacy-ff >/dev/null
legacy_ff_head=$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/309")
launch_reset
check 'markerless tracked PR worktree may refresh by fast-forward' pwt pr 309
check_equals 'successful legacy refresh backfills its canonical URL marker' \
  'https://github.com/owner/project/pull/309' \
  "$(pr_marker feat/pr-reuse-legacy-ff worktree-pr-url)"
check_equals 'successful legacy refresh backfills its verified head marker' \
  "$legacy_ff_head" "$(pr_marker feat/pr-reuse-legacy-ff worktree-pr-head)"

pr_meta 310 feat/pr-reuse-legacy-rewrite false
pwt pr 310 >/dev/null 2>&1
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-legacy-rewrite.worktree-pr-url
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-legacy-rewrite.worktree-pr-head
legacy_rewrite_before=$(git -C "$MANAGED/feat-pr-reuse-legacy-rewrite" rev-parse HEAD)
rewrite_pr_head feat/pr-reuse-legacy-rewrite >/dev/null
launch_reset
check_fails 'markerless tracked PR worktree refuses a rewritten head' pwt pr 310
check_equals 'legacy rewrite refusal preserves the branch head' "$legacy_rewrite_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-legacy-rewrite" rev-parse HEAD)"
check_equals 'legacy rewrite refusal does not invent a head marker' '' \
  "$(pr_marker feat/pr-reuse-legacy-rewrite worktree-pr-head)"

# Exact objects and both parent/child tree-shape conflicts must be refused
# before reset --hard can delete ignored local content.
printf '.env\n' >"$PRIMARY/.worktreeinclude"
printf 'keep exact ignored file\n' >"$PRIMARY/.env"
pr_meta 311 feat/pr-reuse-collision-exact false
pwt pr 311 >/dev/null 2>&1
rm -f "$PRIMARY/.worktreeinclude"
collision_exact_before=$(git -C "$MANAGED/feat-pr-reuse-collision-exact" rev-parse HEAD)
push_pr_tree_shape 311 feat/pr-reuse-collision-exact exact-file >/dev/null
launch_reset
check_fails 'refresh refuses a target object at an exact ignored path' pwt pr 311
check_equals 'exact collision preserves local content' 'keep exact ignored file' \
  "$(cat "$MANAGED/feat-pr-reuse-collision-exact/.env")"
check_equals 'exact collision preserves the branch head' "$collision_exact_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-collision-exact" rev-parse HEAD)"
check_equals 'exact collision preserves the verified marker' "$collision_exact_before" \
  "$(pr_marker feat/pr-reuse-collision-exact worktree-pr-head)"

rm -rf "$PRIMARY/.env"
mkdir -p "$PRIMARY/.env"
printf 'keep ignored descendant\n' >"$PRIMARY/.env/local"
printf '.env/local\n' >"$PRIMARY/.worktreeinclude"
pr_meta 312 feat/pr-reuse-collision-ancestor false
pwt pr 312 >/dev/null 2>&1
rm -f "$PRIMARY/.worktreeinclude"
collision_ancestor_before=$(git -C "$MANAGED/feat-pr-reuse-collision-ancestor" rev-parse HEAD)
push_pr_tree_shape 312 feat/pr-reuse-collision-ancestor file-ancestor >/dev/null
launch_reset
check_fails 'refresh refuses a target file replacing an ignored directory' pwt pr 312
check_equals 'file-ancestor collision preserves ignored content' \
  'keep ignored descendant' \
  "$(cat "$MANAGED/feat-pr-reuse-collision-ancestor/.env/local")"
check_equals 'file-ancestor collision preserves the branch head' "$collision_ancestor_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-collision-ancestor" rev-parse HEAD)"

rm -rf "$PRIMARY/.env"
mkdir -p "$PRIMARY/.env"
printf 'keep under target symlink\n' >"$PRIMARY/.env/local"
printf '.env/local\n' >"$PRIMARY/.worktreeinclude"
pr_meta 313 feat/pr-reuse-collision-symlink false
pwt pr 313 >/dev/null 2>&1
rm -f "$PRIMARY/.worktreeinclude"
collision_symlink_before=$(git -C "$MANAGED/feat-pr-reuse-collision-symlink" rev-parse HEAD)
push_pr_tree_shape 313 feat/pr-reuse-collision-symlink symlink-ancestor >/dev/null
launch_reset
check_fails 'refresh refuses a target symlink replacing an ignored directory' pwt pr 313
check_equals 'symlink-ancestor collision preserves ignored content' \
  'keep under target symlink' \
  "$(cat "$MANAGED/feat-pr-reuse-collision-symlink/.env/local")"
check_equals 'symlink collision preserves the branch head' "$collision_symlink_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-collision-symlink" rev-parse HEAD)"

rm -rf "$PRIMARY/.env"
printf 'keep ignored blocking file\n' >"$PRIMARY/.env"
printf '.env\n' >"$PRIMARY/.worktreeinclude"
pr_meta 314 feat/pr-reuse-collision-directory false
pwt pr 314 >/dev/null 2>&1
rm -f "$PRIMARY/.worktreeinclude"
collision_directory_before=$(git -C "$MANAGED/feat-pr-reuse-collision-directory" rev-parse HEAD)
push_pr_tree_shape 314 feat/pr-reuse-collision-directory directory >/dev/null
launch_reset
check_fails 'refresh refuses an ignored file blocking a target directory' pwt pr 314
check_equals 'directory collision preserves ignored blocking file' \
  'keep ignored blocking file' \
  "$(cat "$MANAGED/feat-pr-reuse-collision-directory/.env")"
check_equals 'directory collision preserves the branch head' "$collision_directory_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-collision-directory" rev-parse HEAD)"
rm -f "$PRIMARY/.env"

# Regression: the old nested Bash scan multiplied ignored paths by target-tree
# entries. This fixture is small enough for the suite but large enough to time
# that implementation out.
pr_meta 315 feat/pr-reuse-many-ignored false
pwt pr 315 >/dev/null 2>&1
printf '.pwt-perf/\n' >>"$exclude_file"
mkdir -p "$MANAGED/feat-pr-reuse-many-ignored/.pwt-perf"
perf_i=0
while [ "$perf_i" -lt 8000 ]; do
  printf 'ignored local content\n' \
    >"$MANAGED/feat-pr-reuse-many-ignored/.pwt-perf/file-$perf_i"
  perf_i=$((perf_i + 1))
done
push_pr_wide_tree 315 feat/pr-reuse-many-ignored >/dev/null
launch_reset
check 'reused PR launch stays within budget with thousands of ignored files' \
  within_scan_budget "$PRIMARY" "$PWT" pr 315
check_equals 'large ignored-file refresh still launches Pi' \
  "$MANAGED/feat-pr-reuse-many-ignored" "$(launched pwd)"

pr_meta 316 feat/pr-reuse-primary false
primary_pr_oid=$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/316")
git -C "$PRIMARY" fetch -q origin "$primary_pr_oid"
git -C "$PRIMARY" checkout -q -b feat/pr-reuse-primary "$primary_pr_oid"
launch_reset
check_fails 'pr refuses reuse from the primary checkout' pwt pr 316
check_equals 'primary-checkout refusal never launches Pi' '' "$(launched pwd)"
git -C "$PRIMARY" checkout -q main

pr_meta 317 feat/pr-reuse-unmanaged false
unmanaged_pr_oid=$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/317")
git -C "$PRIMARY" fetch -q origin "$unmanaged_pr_oid"
git -C "$PRIMARY" branch feat/pr-reuse-unmanaged "$unmanaged_pr_oid" >/dev/null
git -C "$PRIMARY" worktree add -q "$TMP/unmanaged-pr-reuse" \
  feat/pr-reuse-unmanaged
launch_reset
check_fails 'pr refuses reuse from an unmanaged worktree' pwt pr 317
check_equals 'unmanaged-worktree refusal never launches Pi' '' "$(launched pwd)"

# Disposable checkout failures must preserve the real worktree and clean up the
# scratch worktree used to authenticate and fetch through gh.
pr_meta 318 feat/pr-reuse-fetch-failure false
pwt pr 318 >/dev/null 2>&1
fetch_failure_before=$(git -C "$MANAGED/feat-pr-reuse-fetch-failure" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-fetch-failure >/dev/null
printf 'checkoutFails=true\n' >>"$PWT_GH_PRS/318"
launch_reset
check_fails 'reused PR refuses when the disposable fetch fails' pwt pr 318
check_equals 'failed disposable fetch preserves the real branch head' "$fetch_failure_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-fetch-failure" rev-parse HEAD)"

pr_meta 319 feat/pr-reuse-fetch-mismatch false
pwt pr 319 >/dev/null 2>&1
fetch_mismatch_before=$(git -C "$MANAGED/feat-pr-reuse-fetch-mismatch" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-fetch-mismatch >/dev/null
printf 'checkoutOidMismatch=true\n' >>"$PWT_GH_PRS/319"
launch_reset
check_fails 'reused PR refuses when fetched HEAD differs from metadata' pwt pr 319
check_equals 'mismatched disposable fetch preserves the real branch head' \
  "$fetch_mismatch_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-fetch-mismatch" rev-parse HEAD)"

pr_meta 320 feat/pr-reuse-tree-inspection-failure false
pwt pr 320 >/dev/null 2>&1
tree_inspection_before=$(git -C "$MANAGED/feat-pr-reuse-tree-inspection-failure" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-tree-inspection-failure >/dev/null
make_failing_git ls-tree
launch_reset
check_fails 'reused PR fails closed when the target tree cannot be inspected' \
  pwt_with_failing_git pr 320
check_equals 'tree inspection failure preserves the real branch head' \
  "$tree_inspection_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-tree-inspection-failure" rev-parse HEAD)"
check_equals 'tree inspection failure never launches Pi' '' "$(launched pwd)"
rm -f "$FAILGIT/git"

if git -C "$PRIMARY" worktree list --porcelain | grep -q 'pwt-pr-fetch'; then
  not_ok 'temporary PR fetch worktrees are cleaned up'
else
  ok 'temporary PR fetch worktrees are cleaned up'
fi
fetch_scratch_left=0
for candidate in "$MANAGED"/.pwt-pr-fetch.*; do
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    fetch_scratch_left=1
  fi
done
check_equals 'temporary PR fetch directories are cleaned up' '0' "$fetch_scratch_left"

# ---------------------------------------------------------- worktree includes

section 'worktreeinclude'

# Nothing configured yet: creation must remain a no-op.
launch_reset
pwt new feat/no-include >/dev/null 2>&1
check 'creation succeeds when worktreeinclude is absent' \
  test -d "$MANAGED/feat-no-include"

printf '# nothing matches this\nnever-matches-anything\n' \
  >"$PRIMARY/.worktreeinclude"
launch_reset
pwt new feat/empty-include >/dev/null 2>&1
check 'creation succeeds when worktreeinclude matches nothing' \
  test -d "$MANAGED/feat-empty-include"

# Real patterns cover nested paths, spaces, and a literal newline. The wildcard
# is independent of the unusual filename, so the assertion can disagree with a
# newline-flattening implementation rather than recreating its parsing logic.
newline_name=$'line\nbreak.local'
mkdir -p "$PRIMARY/config"
printf 'SECRET=1\n' >"$PRIMARY/.env"
printf '{"local":true}\n' >"$PRIMARY/config/local.json"
printf 'spaced\n' >"$PRIMARY/with space.txt"
printf 'newline\n' >"$PRIMARY/$newline_name"
printf 'adjacent dots\n' >"$PRIMARY/valid..local"
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
config/local.json
with space.txt
*.local
PATTERNS

launch_reset
copy_out=$(pwt new feat/copied 2>&1)
check 'a worktreeinclude match is copied into the new worktree' \
  test -f "$MANAGED/feat-copied/.env"
check 'a nested worktreeinclude match keeps its relative path' \
  test -f "$MANAGED/feat-copied/config/local.json"
check 'a worktreeinclude match containing a space is copied' \
  test -f "$MANAGED/feat-copied/with space.txt"
check 'NUL-safe listing preserves a newline in a matched filename' \
  test -f "$MANAGED/feat-copied/$newline_name"
check 'adjacent dots in a filename do not read as path traversal' \
  test -f "$MANAGED/feat-copied/valid..local"
check_contains 'copying reports the number of files copied' \
  'copied 5 file(s)' "$copy_out"
check_equals 'the copied file has the same contents as the original' \
  'SECRET=1' "$(sed -n '1p' "$MANAGED/feat-copied/.env" 2>/dev/null)"

# Worktrees must share the primary checkout's single beads database. Even an
# explicit include pattern cannot create a private, divergent copy.
mkdir -p "$PRIMARY/.beads/backup"
printf '{"id":"x"}\n' >"$PRIMARY/.beads/issues.jsonl"
printf 'blob\n' >"$PRIMARY/.beads/backup/snap.darc"
cat >"$PRIMARY/.worktreeinclude" <<'PATTERNS'
.env
.beads/
PATTERNS

launch_reset
beads_out=$(pwt new feat/beads-guard 2>&1)
check 'the beads directory is never copied when a pattern matches it' \
  test ! -e "$MANAGED/feat-beads-guard/.beads"
check 'no file below the beads directory is copied' \
  test ! -e "$MANAGED/feat-beads-guard/.beads/issues.jsonl"
check 'a non-beads match is still copied alongside the refusal' \
  test -f "$MANAGED/feat-beads-guard/.env"
check_contains 'skipping the beads directory prints a clear warning' \
  'refusing to copy .beads/' "$beads_out"

# Both the pattern file and sources come from the physical primary checkout,
# even when pwt itself is invoked from a linked worktree.
printf '.env\n' >"$PRIMARY/.worktreeinclude"
launch_reset
pwt_in "$MANAGED/feat-alpha" new feat/from-inside >/dev/null 2>&1
check 'worktreeinclude uses the primary checkout from inside a worktree' \
  test -f "$MANAGED/feat-from-inside/.env"

git -C "$PRIMARY" branch feat/copy-on-branch >/dev/null 2>&1
launch_reset
pwt branch feat/copy-on-branch >/dev/null 2>&1
check 'branch also copies worktreeinclude matches' \
  test -f "$MANAGED/feat-copy-on-branch/.env"

# Git can report failure after creating and registering a worktree (for example,
# when a checkout hook fails). The retained registration must be abandoned
# before preparation state is cleared.
launch_reset
late_add_status=0
late_add_out=$(pwt_git_fail worktree-add-after-create \
  new feat/late-add-failure 2>&1) || late_add_status=$?
if [ "$late_add_status" -ne 0 ]; then
  ok 'a late worktree-add error exits non-zero'
else
  not_ok 'a late worktree-add error exits non-zero'
fi
check_contains 'a late worktree-add error reports creation failure' \
  'could not create the worktree' "$late_add_out"
check 'a late worktree-add error removes the created directory' \
  test ! -e "$MANAGED/feat-late-add-failure"
check_fails 'a late worktree-add error unregisters the created worktree' \
  worktree_registered_at "$MANAGED/feat-late-add-failure"
check_equals 'a late worktree-add error never launches Pi' '' "$(launched pwd)"
launch_reset
pwt branch feat/late-add-failure >/dev/null 2>&1
check 'a cleaned late worktree-add failure can be retried safely' \
  test -f "$MANAGED/feat-late-add-failure/.env"
check_equals 'the late-add retry launches from the prepared worktree' \
  "$MANAGED/feat-late-add-failure" "$(launched pwd)"

# An include entry names a repository path, but the source itself can still be
# an untracked symlink. Do not dereference it and import outside data.
printf 'OUTSIDE SOURCE\n' >"$TMP/outside-source"
ln -s "$TMP/outside-source" "$PRIMARY/external-source"
printf 'external-source\n' >"$PRIMARY/.worktreeinclude"
launch_reset
source_link_status=0
source_link_out=$(pwt new feat/source-link 2>&1) || source_link_status=$?
if [ "$source_link_status" -ne 0 ]; then
  ok 'a symlink source aborts worktree preparation'
else
  not_ok 'a symlink source aborts worktree preparation'
fi
check_contains 'the source refusal names the symlink' \
  'symlink from the primary checkout' "$source_link_out"
check 'a symlink source causes complete worktree abandonment' \
  test ! -e "$MANAGED/feat-source-link"
check_equals 'a symlink source never launches Pi' '' "$(launched pwd)"

printf '.env\n' >"$PRIMARY/.worktreeinclude"

# A Git error must not be interpreted as an empty include set. The worktree is
# abandoned and Pi never starts, while the newly created branch remains for an
# explicit retry through `pwt branch`.
launch_reset
include_list_status=0
include_list_out=$(pwt_git_fail include-ls-files \
  new feat/include-list-failure 2>&1) || include_list_status=$?
if [ "$include_list_status" -ne 0 ]; then
  ok 'Git listing failure aborts worktree preparation'
else
  not_ok 'Git listing failure aborts worktree preparation'
fi
check_contains 'Git listing failure is reported instead of reading as empty' \
  'cannot list .worktreeinclude matches' "$include_list_out"
check 'Git listing failure removes the new worktree directory' \
  test ! -e "$MANAGED/feat-include-list-failure"
check_fails 'Git listing failure unregisters the new worktree' \
  worktree_registered_at "$MANAGED/feat-include-list-failure"
check_equals 'Git listing failure never launches Pi' '' "$(launched pwd)"
launch_reset
pwt branch feat/include-list-failure >/dev/null 2>&1
check 'successful abandonment leaves the branch ready for explicit retry' \
  test -f "$MANAGED/feat-include-list-failure/.env"
check_equals 'the explicit retry launches from its fully prepared worktree' \
  "$MANAGED/feat-include-list-failure" "$(launched pwd)"

# A fabricated Git result reaches the traversal assertion directly. This keeps
# the guard behavioral even though honest `git ls-files` normalizes its output.
launch_reset
escape_status=0
escape_out=$(pwt_git_fail include-escaping-path \
  new feat/escaping-source-path 2>&1) || escape_status=$?
if [ "$escape_status" -ne 0 ]; then
  ok 'an escaping listed path aborts worktree preparation'
else
  not_ok 'an escaping listed path aborts worktree preparation'
fi
check_contains 'the escaping listed path is reported' \
  'path that escapes the worktree' "$escape_out"
check 'an escaping listed path causes complete worktree abandonment' \
  test ! -e "$MANAGED/feat-escaping-source-path"
check_equals 'an escaping listed path never launches Pi' '' "$(launched pwd)"

# A copy error is a preparation error, not permission to launch a partially
# populated worktree.
launch_reset
copy_failure_status=0
copy_failure_out=$(pwt_cp_fail new feat/copy-failure 2>&1) || copy_failure_status=$?
if [ "$copy_failure_status" -ne 0 ]; then
  ok 'a copy error aborts worktree preparation'
else
  not_ok 'a copy error aborts worktree preparation'
fi
check_contains 'a copy error names the file it could not copy' \
  'cannot copy .env into the worktree' "$copy_failure_out"
check_not_contains 'a copy error does not report preparation success' \
  'copied 1 file(s)' "$copy_failure_out"
check 'a copy error removes the new worktree directory' \
  test ! -e "$MANAGED/feat-copy-failure"
check_fails 'a copy error unregisters the new worktree' \
  worktree_registered_at "$MANAGED/feat-copy-failure"
check_equals 'a copy error never launches Pi' '' "$(launched pwd)"

# If Git itself cannot remove a failed worktree, its private preparation marker
# must block every later launch until the retained tree is removed explicitly.
launch_reset
cleanup_failure_status=0
cleanup_failure_out=$(
  PWT_TEST_CP_FAIL=1 PWT_TEST_GIT_FAIL=worktree-remove \
    pwt new feat/cleanup-failure 2>&1
) || cleanup_failure_status=$?
if [ "$cleanup_failure_status" -ne 0 ]; then
  ok 'a cleanup error still exits non-zero'
else
  not_ok 'a cleanup error still exits non-zero'
fi
check_contains 'a cleanup error reports the retained blocked worktree' \
  'cleanup failed and the worktree remains blocked' "$cleanup_failure_out"
check 'a cleanup error leaves its worktree registered for explicit recovery' \
  worktree_registered_at "$MANAGED/feat-cleanup-failure"
launch_reset
retry_status=0
retry_out=$(pwt branch feat/cleanup-failure 2>&1) || retry_status=$?
if [ "$retry_status" -ne 0 ]; then
  ok 'an incomplete retained worktree cannot be reused'
else
  not_ok 'an incomplete retained worktree cannot be reused'
fi
check_contains 'retry explains that retained preparation is incomplete' \
  'worktree preparation is incomplete' "$retry_out"
check_equals 'retrying an incomplete retained worktree never launches Pi' \
  '' "$(launched pwd)"
git -C "$PRIMARY" worktree remove --force \
  "$MANAGED/feat-cleanup-failure" >/dev/null 2>&1

# Preparation state is recorded before Git creates anything. A state-write
# failure therefore leaves no worktree that would need fallible cleanup.
launch_reset
marker_failure_status=0
marker_failure_out=$(pwt_mkdir_fail \
  "$PRIMARY/.git/pwt/preparing-feat-marker-failure" \
  new feat/marker-failure 2>&1) || marker_failure_status=$?
if [ "$marker_failure_status" -ne 0 ]; then
  ok 'a preparation-marker error still exits non-zero'
else
  not_ok 'a preparation-marker error still exits non-zero'
fi
check_contains 'a preparation-marker error reports the state-write failure' \
  'cannot record worktree preparation state' "$marker_failure_out"
check 'a preparation-marker error leaves no worktree directory' \
  test ! -e "$MANAGED/feat-marker-failure"
check_fails 'a preparation-marker error leaves no worktree registration' \
  worktree_registered_at "$MANAGED/feat-marker-failure"
check_ref_absent 'a preparation-marker error leaves no branch' \
  refs/heads/feat/marker-failure
check_equals 'a preparation-marker error never launches Pi' '' "$(launched pwd)"

# Marker acquisition must be atomic. Hold the first invocation after it acquires
# state but before Git creates the worktree, then race a second invocation for
# the same target.
add_ready="$TMP/concurrent-add-ready"
add_release="$TMP/concurrent-add-release"
first_add_out="$TMP/concurrent-first.out"
launch_reset
(
  export PWT_TEST_GIT_FAIL=hold-worktree-add
  export PWT_TEST_ADD_READY="$add_ready"
  export PWT_TEST_ADD_RELEASE="$add_release"
  pwt new feat/concurrent-preparation >"$first_add_out" 2>&1
) &
first_add_pid=$!
barrier_attempts=0
while [ ! -e "$add_ready" ] && [ "$barrier_attempts" -lt 200 ]; do
  barrier_attempts=$((barrier_attempts + 1))
  sleep 0.05
done
check 'the first concurrent invocation acquires preparation state' \
  test -e "$add_ready"
second_add_status=0
second_add_out=$(pwt new feat/concurrent-preparation 2>&1) || second_add_status=$?
if [ "$second_add_status" -ne 0 ]; then
  ok 'a concurrent invocation cannot acquire the same preparation state'
else
  not_ok 'a concurrent invocation cannot acquire the same preparation state'
fi
check_contains 'the concurrent refusal names existing preparation state' \
  'stale worktree preparation state' "$second_add_out"
check_equals 'the refused concurrent invocation never launches Pi' '' "$(launched pwd)"
: >"$add_release"
first_add_status=0
wait "$first_add_pid" || first_add_status=$?
if [ "$first_add_status" -eq 0 ]; then
  ok 'the preparation-state owner completes after the race'
else
  not_ok 'the preparation-state owner completes after the race'
fi
check 'the preparation-state owner copies its include' \
  test -f "$MANAGED/feat-concurrent-preparation/.env"
check_equals 'the preparation-state owner launches from its completed worktree' \
  "$MANAGED/feat-concurrent-preparation" "$(launched pwd)"
check 'completed concurrent preparation clears its marker directory' \
  test ! -e "$PRIMARY/.git/pwt/preparing-feat-concurrent-preparation"

# A hostile branch can commit each unsafe destination shape. The copy source in
# the trusted primary checkout is regular; only the fresh target is hostile.
(
  cd "$TMP/seed" || exit 1
  git checkout -q stable
  ln -s "$TMP/victim-file" evil-link
  ln -s "$TMP/victim-dir" nested-link
  mkdir -p dir-dst
  ln -s "$TMP/victim-dir/dir-dst" dir-dst/dir-dst
  printf 'tracked placeholder\n' >.env
  git add .env evil-link nested-link dir-dst
  git commit -qm 'add hostile include destinations'
  git push -q origin stable
)
printf 'ORIGINAL\n' >"$TMP/victim-file"
mkdir -p "$TMP/victim-dir"
printf 'SECRET=1\n' >"$PRIMARY/evil-link"
mkdir -p "$PRIMARY/nested-link/sub"
printf 'SECRET=1\n' >"$PRIMARY/nested-link/sub/config"
printf 'SECRET=1\n' >"$PRIMARY/dir-dst"

printf '.env\n' >"$PRIMARY/.worktreeinclude"
launch_reset
tracked_status=0
tracked_out=$(pwt new feat/tracked-destination 2>&1) || tracked_status=$?
if [ "$tracked_status" -ne 0 ]; then
  ok 'a tracked destination aborts worktree preparation'
else
  not_ok 'a tracked destination aborts worktree preparation'
fi
check_contains 'the tracked destination refusal names the existing file' \
  'overwrite an existing file' "$tracked_out"
check 'a tracked destination causes complete worktree abandonment' \
  test ! -e "$MANAGED/feat-tracked-destination"
check_equals 'a tracked destination never launches Pi' '' "$(launched pwd)"

printf 'evil-link\n' >"$PRIMARY/.worktreeinclude"
launch_reset
symlink_status=0
symlink_out=$(pwt new feat/symlink-escape 2>&1) || symlink_status=$?
if [ "$symlink_status" -ne 0 ]; then
  ok 'a symlinked destination exits non-zero'
else
  not_ok 'a symlinked destination exits non-zero'
fi
check_equals 'a symlinked copy destination never launches Pi' '' "$(launched pwd)"
check_equals 'a file outside the worktree remains untouched' \
  'ORIGINAL' "$(sed -n '1p' "$TMP/victim-file" 2>/dev/null)"
check 'a symlinked destination causes complete worktree abandonment' \
  test ! -e "$MANAGED/feat-symlink-escape"
check_fails 'the symlinked destination is unregistered after abandonment' \
  worktree_registered_at "$MANAGED/feat-symlink-escape"
check_contains 'the refusal names the symlinked destination' \
  'symlink inside the worktree' "$symlink_out"

printf 'nested-link/sub/config\n' >"$PRIMARY/.worktreeinclude"
launch_reset
nested_status=0
nested_out=$(pwt new feat/nested-escape 2>&1) || nested_status=$?
if [ "$nested_status" -ne 0 ]; then
  ok 'an escaping intermediate directory exits non-zero'
else
  not_ok 'an escaping intermediate directory exits non-zero'
fi
check_equals 'an escaping intermediate directory never launches Pi' '' "$(launched pwd)"
check 'nothing is copied through an escaping intermediate directory' \
  test ! -e "$TMP/victim-dir/sub/config"
# This assertion isolates the PRE-mkdir guard. A post-mkdir refusal alone is too
# late: it would leave this attacker-chosen directory behind outside the target.
check 'the pre-mkdir guard prevents creating a directory outside the worktree' \
  test ! -e "$TMP/victim-dir/sub"
check 'an escaping parent causes complete worktree abandonment' \
  test ! -e "$MANAGED/feat-nested-escape"
check_contains 'the escaping-parent refusal names physical containment' \
  'resolves outside the worktree' "$nested_out"

# Replace the just-created destination directory with an outside symlink in the
# mkdir boundary stub. Only the post-mkdir containment check can catch this.
mkdir -p "$PRIMARY/post-mkdir/sub" "$TMP/post-mkdir-outside"
printf 'SECRET=1\n' >"$PRIMARY/post-mkdir/sub/config"
printf 'post-mkdir/sub/config\n' >"$PRIMARY/.worktreeinclude"
launch_reset
post_mkdir_status=0
post_mkdir_out=$(pwt_swap_after_mkdir \
  "$MANAGED/feat-post-mkdir-race/post-mkdir/sub" \
  "$TMP/post-mkdir-outside" \
  new feat/post-mkdir-race 2>&1) || post_mkdir_status=$?
if [ "$post_mkdir_status" -ne 0 ]; then
  ok 'a post-mkdir destination substitution exits non-zero'
else
  not_ok 'a post-mkdir destination substitution exits non-zero'
fi
check_contains 'the post-mkdir substitution is refused by containment' \
  'resolves outside the worktree' "$post_mkdir_out"
check 'the post-mkdir substitution writes nothing outside the worktree' \
  test ! -e "$TMP/post-mkdir-outside/config"
check 'the post-mkdir substitution abandons the worktree' \
  test ! -e "$MANAGED/feat-post-mkdir-race"
check_equals 'a post-mkdir substitution never launches Pi' '' "$(launched pwd)"

printf 'dir-dst\n' >"$PRIMARY/.worktreeinclude"
launch_reset
directory_status=0
directory_out=$(pwt new feat/directory-escape 2>&1) || directory_status=$?
if [ "$directory_status" -ne 0 ]; then
  ok 'a directory at the copy destination exits non-zero'
else
  not_ok 'a directory at the copy destination exits non-zero'
fi
check_equals 'a directory at the copy destination never launches Pi' '' "$(launched pwd)"
check 'nothing is copied through the directory-at-destination shape' \
  test ! -e "$TMP/victim-dir/dir-dst"
check 'a non-regular destination causes complete worktree abandonment' \
  test ! -e "$MANAGED/feat-directory-escape"
check_contains 'the directory refusal names the invalid destination shape' \
  'non-regular destination' "$directory_out"

rm -rf "$PRIMARY/evil-link" "$PRIMARY/nested-link" "$PRIMARY/dir-dst" \
  "$PRIMARY/post-mkdir"
rm -f "$PRIMARY/external-source"
rm -f "$PRIMARY/.worktreeinclude" "$PRIMARY/.env" \
  "$PRIMARY/config/local.json" "$PRIMARY/with space.txt" \
  "$PRIMARY/$newline_name" "$PRIMARY/valid..local"

# -------------------------------------------------------------------- summary

section "results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
