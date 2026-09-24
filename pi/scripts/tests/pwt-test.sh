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
TEST_SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/${BASH_SOURCE[0]##*/}

pass=0
fail=0
ok() { printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
not_ok() { printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  skip - %s\n' "$1"; }

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
PWT_TEST_COMMAND_LOG="$TMP/public-commands.log"
: >"$PWT_TEST_COMMAND_LOG"

export HOME="$TMP/home"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
unset GH_REPO GH_HOST
# A caller's own ssh configuration must never leak into what the ssh-transport
# cases below observe — each one sets what it needs on the one call under test.
unset GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT
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
export PWT_TEST_FETCH_PREFIX="$MANAGED/.pwt-pr-fetch."
export PWT_TEST_PARTIAL_PATH_FILE="$TMP/partial-pr-fetch-path"
PWT_TEST_REAL_GIT=$(command -v git)
PWT_TEST_REAL_MKDIR=$(command -v mkdir)
PWT_TEST_REAL_CP=$(command -v cp)

# Git boundary stub: normal calls delegate unchanged. A named failure mode lets
# the suite prove pwt distinguishes Git errors from ordinary missing records.
cat >"$BIN/git" <<'STUB'
#!/usr/bin/env bash
if [ -n "${PWT_TEST_COMPLETION_AUDIT_LOG:-}" ]; then
  printf '%s\n' "$*" >>"$PWT_TEST_COMPLETION_AUDIT_LOG"
  case $* in
    'config --get remote.origin.url' | \
      'for-each-ref --format=%(refname) refs/heads refs/remotes/origin' | \
      'worktree list --porcelain -z') ;;
    *)
      printf 'UNEXPECTED GIT: %s\n' "$*" >>"$PWT_TEST_COMPLETION_AUDIT_LOG"
      exit 97
      ;;
  esac
fi
args=" $* "
swap_test_managed_ancestor() {
  /bin/mv "$PWT_TEST_MANAGED_ANCESTOR" "$PWT_TEST_MANAGED_SAVED" || exit
  /bin/ln -s "$PWT_TEST_MANAGED_SAVED" \
    "$PWT_TEST_MANAGED_ANCESTOR" || exit
}
case $args in
  *' worktree remove '*)
    case $args in
      *' --force '*) ;;
      *)
        if [ -n "${PWT_TEST_REMOVE_ATTEMPT:-}" ]; then
          : >"$PWT_TEST_REMOVE_ATTEMPT"
        fi
        if [ -n "${PWT_TEST_REMOVE_LOG:-}" ]; then
          printf '%s\n' "$*" >>"$PWT_TEST_REMOVE_LOG"
        fi
        ;;
    esac
    ;;
esac
case $args in
  *' branch '*)
    if [ -n "${PWT_TEST_BRANCH_LOG:-}" ]; then
      printf '%s\n' "$*" >>"$PWT_TEST_BRANCH_LOG"
    fi
    ;;
esac
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
  remove-status)
    case $args in *' status --porcelain --untracked-files=all '*) exit 70 ;; esac
    ;;
  prune-status)
    case $args in
      *" -C $PWT_TEST_PRUNE_TARGET status --porcelain --untracked-files=all "*)
        exit 70
        ;;
    esac
    ;;
  prune-head-after-status)
    case $args in
      *" -C $PWT_TEST_PRUNE_TARGET status --porcelain --untracked-files=all "*)
        count=0
        if [ -f "$PWT_TEST_PRUNE_STATUS_COUNT" ]; then
          IFS= read -r count <"$PWT_TEST_PRUNE_STATUS_COUNT"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$PWT_TEST_PRUNE_STATUS_COUNT"
        "$PWT_TEST_REAL_GIT" "$@" || exit
        if [ "$count" -eq 2 ]; then
          printf 'committed after status\n' \
            >"$PWT_TEST_PRUNE_TARGET/prune-late-head.txt"
          "$PWT_TEST_REAL_GIT" -C "$PWT_TEST_PRUNE_TARGET" \
            add prune-late-head.txt || exit
          "$PWT_TEST_REAL_GIT" -C "$PWT_TEST_PRUNE_TARGET" \
            commit -qm 'advance after prune status' || exit
        fi
        exit 0
        ;;
    esac
    ;;
  remove-index-list)
    case $args in *' ls-files -v -z '*) exit 70 ;; esac
    ;;
  remove-ignored-list)
    case $args in
      *' ls-files --others --ignored --exclude-standard '*) exit 70 ;;
    esac
    ;;
  remove-checked)
    case $args in
      *' worktree remove '*)
        case $args in *' --force '*) ;; *) exit 70 ;; esac
        ;;
    esac
    ;;
  remove-dirty-after-ignored)
    case $args in
      *' ls-files --others --ignored --exclude-standard '*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        printf 'late edit\n' >"$PWT_TEST_REMOVE_TARGET/late.txt"
        exit 0
        ;;
    esac
    ;;
  remove-symlink-after-ignored)
    case $args in
      *' ls-files --others --ignored --exclude-standard '*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        mv "$PWT_TEST_REMOVE_TARGET" "$PWT_TEST_REMOVE_OUTSIDE"
        ln -s "$PWT_TEST_REMOVE_OUTSIDE" "$PWT_TEST_REMOVE_TARGET"
        exit 0
        ;;
    esac
    ;;
  remove-ignored-after-status)
    case $args in
      *' status --porcelain --untracked-files=all '*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        printf 'late ignored\n' >"$PWT_TEST_REMOVE_TARGET/.remove-secret"
        exit 0
        ;;
    esac
    ;;
  remove-symlink-after-status)
    case $args in
      *' status --porcelain --untracked-files=all '*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        mv "$PWT_TEST_REMOVE_TARGET" "$PWT_TEST_REMOVE_OUTSIDE"
        ln -s "$PWT_TEST_REMOVE_OUTSIDE" "$PWT_TEST_REMOVE_TARGET"
        exit 0
        ;;
    esac
    ;;
  remove-registration-after-status)
    case $args in
      *' status --porcelain --untracked-files=all '*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        : >"$PWT_TEST_REMOVE_SWITCHED"
        exit 0
        ;;
      *' worktree list --porcelain '*)
        if [ -e "$PWT_TEST_REMOVE_SWITCHED" ]; then
          printf 'worktree %s\nbranch refs/heads/%s\n\n' \
            "$PWT_TEST_REMOVE_DECOY" "$PWT_TEST_REMOVE_BRANCH"
          exit 0
        fi
        ;;
      *" -C $PWT_TEST_REMOVE_DECOY symbolic-ref --quiet --short HEAD "*)
        if [ -e "$PWT_TEST_REMOVE_SWITCHED" ]; then
          printf '%s\n' "$PWT_TEST_REMOVE_BRANCH"
          exit 0
        fi
        ;;
    esac
    ;;
  remove-success-keeps-path)
    case $args in
      *' worktree remove '*)
        case $args in *' --force '*) ;; *) exit 0 ;; esac
        ;;
    esac
    ;;
  remove-success-keeps-registration)
    case $args in
      *' worktree remove '*)
        case $args in
          *' --force '*) ;;
          *)
            "$PWT_TEST_REAL_GIT" "$@" || exit
            : >"$PWT_TEST_REMOVE_DONE"
            exit 0
            ;;
        esac
        ;;
      *' worktree list --porcelain '*)
        if [ -e "$PWT_TEST_REMOVE_DONE" ]; then
          "$PWT_TEST_REAL_GIT" "$@" || exit
          printf 'worktree %s\n\n' "$PWT_TEST_REMOVE_TARGET"
          exit 0
        fi
        ;;
    esac
    ;;
  remove-success-list-fails)
    case $args in
      *' worktree remove '*)
        case $args in
          *' --force '*) ;;
          *)
            "$PWT_TEST_REAL_GIT" "$@" || exit
            : >"$PWT_TEST_REMOVE_DONE"
            exit 0
            ;;
        esac
        ;;
      *' worktree list --porcelain '*)
        [ ! -e "$PWT_TEST_REMOVE_DONE" ] || exit 70
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
  pr-fetch-add-unregistered-partial)
    case $args in
      *' worktree add '*)
        for argument in "$@"; do
          case $argument in
            "$PWT_TEST_FETCH_PREFIX"*)
              printf 'partial worktree data\n' >"$argument/partial"
              printf '%s\n' "$argument" >"$PWT_TEST_PARTIAL_PATH_FILE"
              exit 70
              ;;
          esac
        done
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
  inject-managed-ancestor-symlink)
    case $args in
      *' fetch --quiet origin '*)
        /bin/mv "$PWT_TEST_MANAGED_ANCESTOR" "$PWT_TEST_MANAGED_SAVED" || exit
        /bin/ln -s "$PWT_TEST_MANAGED_OUTSIDE" \
          "$PWT_TEST_MANAGED_ANCESTOR" || exit
        ;;
    esac
    ;;
  pr-ignored-after-final-status)
    case $args in
      *" -C $PWT_TEST_PR_LATE_TARGET status --porcelain --untracked-files=all "*)
        count=0
        if [ -f "$PWT_TEST_PR_LATE_COUNT" ]; then
          IFS= read -r count <"$PWT_TEST_PR_LATE_COUNT"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$PWT_TEST_PR_LATE_COUNT"
        "$PWT_TEST_REAL_GIT" "$@" || exit
        if [ "$count" -eq 2 ]; then
          printf 'late ignored local content\n' >"$PWT_TEST_PR_LATE_TARGET/.env"
        fi
        exit 0
        ;;
    esac
    ;;
  pr-fetch-root-after-head)
    case $args in
      *' rev-parse HEAD '*)
        for argument in "$@"; do
          case $argument in
            "$PWT_TEST_FETCH_PREFIX"*)
              "$PWT_TEST_REAL_GIT" "$@" || exit
              swap_test_managed_ancestor
              exit 0
              ;;
          esac
        done
        ;;
    esac
    ;;
  pr-root-after-ignored-scan)
    case $args in
      *' check-ignore -z --stdin '*)
        "$PWT_TEST_REAL_GIT" "$@"
        status=$?
        swap_test_managed_ancestor
        exit "$status"
        ;;
    esac
    ;;
  pr-root-after-head-marker)
    case $args in
      *" config branch.$PWT_TEST_PR_ROOT_BRANCH.worktree-pr-head "*)
        "$PWT_TEST_REAL_GIT" "$@" || exit
        swap_test_managed_ancestor
        exit 0
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
  printf 'GIT_SSH_COMMAND=%s\n' "${GIT_SSH_COMMAND-<unset>}"
  printf 'PI_CODING_AGENT_DIR=%s\n' "${PI_CODING_AGENT_DIR-<unset>}"
  printf 'PI_CODING_AGENT_SESSION_DIR=%s\n' \
    "${PI_CODING_AGENT_SESSION_DIR-<unset>}"
  printf 'PI_PACKAGE_DIR=%s\n' "${PI_PACKAGE_DIR-<unset>}"
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
export PWT_GH_OTHER_PRS="$TMP/gh-other-prs"
export PWT_GH_STATES="$TMP/gh-states"
export PWT_GH_FAILURES="$TMP/gh-failures"
export PWT_GH_LOG="$TMP/gh.log"
mkdir -p "$PWT_GH_PRS" "$PWT_GH_OTHER_PRS" \
  "$PWT_GH_STATES" "$PWT_GH_FAILURES"
: >"$PWT_GH_LOG"
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
if [ -f "$PWT_GH_UNAVAILABLE" ]; then
  printf 'gh: could not authenticate\n' >&2
  exit 1
fi
printf '%s\n' "$*" >>"$PWT_GH_LOG"
if [ "$1" = auth ] && [ "$2" = status ]; then
  exit 0
fi
repo_selector=${GH_REPO:-owner/project}
want_repo=0
for argument in "$@"; do
  if [ "$want_repo" = 1 ]; then
    repo_selector=$argument
    want_repo=0
    continue
  fi
  case $argument in
    --repo) want_repo=1 ;;
    --repo=*) repo_selector=${argument#--repo=} ;;
  esac
done
case $repo_selector in
  */*/*) ;;
  *)
    if [ -n "${GH_HOST:-}" ]; then
      repo_selector="$GH_HOST/$repo_selector"
    fi
    ;;
esac
case $repo_selector in
  owner/project | github.com/owner/project) meta_root=$PWT_GH_PRS ;;
  other/wrong | github.com/other/wrong | enterprise.example/owner/project) \
    meta_root=$PWT_GH_OTHER_PRS ;;
  *)
    printf 'unknown repository: %s\n' "$repo_selector" >&2
    exit 1
    ;;
esac
if [ "$1" = pr ] && [ "$2" = view ]; then
  requested=$3
  number=${requested##*/}
  meta="$meta_root/$number"
  if [ ! -f "$meta" ]; then
    printf 'could not resolve pull request %s\n' "$3" >&2
    exit 1
  fi
  case " $* " in
    *' --json state,'*)
      branch=$(sed -n 's/^headRefName=//p' "$meta")
      state_name=$(printf '%s' "$branch" | tr '/' '-')
      if [ -f "$PWT_GH_FAILURES/$state_name" ]; then
        printf 'gh: simulated pull request state failure\n' >&2
        exit 70
      fi
      if [ -f "$PWT_GH_STATES/$state_name" ]; then
        sed -n 1p "$PWT_GH_STATES/$state_name"
      else
        printf 'OPEN\n'
      fi
      ;;
  esac
  sed -n 's/^headRefName=//p' "$meta"
  sed -n 's/^isCrossRepository=//p' "$meta"
  sed -n 's/^headRepositoryOwner=//p' "$meta"
  sed -n 's/^headRepository=//p' "$meta"
  sed -n 's/^url=//p' "$meta"
  sed -n 's/^headRefOid=//p' "$meta"
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = list ]; then
  branch=''
  want_head=0
  want_state=0
  state_scope=''
  for argument in "$@"; do
    if [ "$want_head" = 1 ]; then
      branch=$argument
      want_head=0
      continue
    fi
    if [ "$want_state" = 1 ]; then
      state_scope=$argument
      want_state=0
      continue
    fi
    case $argument in
      --head) want_head=1 ;;
      --head=*) branch=${argument#--head=} ;;
      --state) want_state=1 ;;
      --state=*) state_scope=${argument#--state=} ;;
    esac
  done
  if [ "$state_scope" != all ]; then
    printf 'gh: prune state lookup must include merged pull requests\n' >&2
    exit 64
  fi
  state_name=$(printf '%s' "$branch" | tr '/' '-')
  if [ -f "$PWT_GH_FAILURES/$state_name" ]; then
    printf 'gh: simulated pull request state failure\n' >&2
    exit 70
  fi
  if [ -f "$PWT_GH_STATES/$state_name" ]; then
    cat "$PWT_GH_STATES/$state_name"
  fi

  if [ "${PWT_TEST_PRUNE_MUTATION:-}" = dirty-after-state ] &&
    [ "$branch" = "$PWT_TEST_PRUNE_BRANCH" ]; then
    printf 'late edit\n' >"$PWT_TEST_PRUNE_TARGET/late.txt"
  elif [ "${PWT_TEST_PRUNE_MUTATION:-}" = symlink-after-state ] &&
    [ "$branch" = "$PWT_TEST_PRUNE_BRANCH" ]; then
    mv "$PWT_TEST_PRUNE_TARGET" "$PWT_TEST_PRUNE_OUTSIDE"
    ln -s "$PWT_TEST_PRUNE_OUTSIDE" "$PWT_TEST_PRUNE_TARGET"
  elif [ "${PWT_TEST_PRUNE_MUTATION:-}" = move-after-state ] &&
    [ "$branch" = "$PWT_TEST_PRUNE_BRANCH" ]; then
    "$PWT_TEST_REAL_GIT" -C "$PWT_TEST_PRUNE_PRIMARY" worktree move \
      "$PWT_TEST_PRUNE_TARGET" "$PWT_TEST_PRUNE_MOVED"
  elif [ "${PWT_TEST_PRUNE_MUTATION:-}" = head-after-state ] &&
    [ "$branch" = "$PWT_TEST_PRUNE_BRANCH" ]; then
    printf 'new committed head\n' >"$PWT_TEST_PRUNE_TARGET/prune-head-change.txt"
    "$PWT_TEST_REAL_GIT" -C "$PWT_TEST_PRUNE_TARGET" add prune-head-change.txt
    "$PWT_TEST_REAL_GIT" -C "$PWT_TEST_PRUNE_TARGET" \
      commit -qm 'advance during prune classification'
  fi
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = checkout ]; then
  number=$3
  meta="$meta_root/$number"
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
  swap_managed_ancestor() {
    local ancestor saved
    ancestor=$(sed -n 's/^swapManagedAncestor=//p' "$meta")
    saved=$(sed -n 's/^saveManagedAncestor=//p' "$meta")
    [ -n "$ancestor" ] || return 0
    [ -n "$saved" ] || return 1
    /bin/mv "$ancestor" "$saved" || return 1
    /bin/ln -s "$saved" "$ancestor"
  }
  if [ "$detach" = 1 ]; then
    if grep -q '^checkoutOidMismatch=true$' "$meta"; then
      git checkout -q --detach HEAD
    else
      git checkout -q --detach "refs/remotes/origin/$head_ref"
    fi
    checkout_status=$?
    dirty_target=$(sed -n 's/^dirtyAfterFetchPath=//p' "$meta")
    if [ -n "$dirty_target" ]; then
      printf 'dirty during disposable fetch\n' >>"$dirty_target/README.md"
    fi
    hidden_target=$(sed -n 's/^assumeAfterFetchPath=//p' "$meta")
    if [ -n "$hidden_target" ]; then
      git -C "$hidden_target" update-index --assume-unchanged README.md || exit
      printf 'hidden during disposable fetch\n' >"$hidden_target/README.md"
    fi
    if [ "$checkout_status" -eq 0 ]; then
      swap_managed_ancestor || exit
    fi
    exit "$checkout_status"
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
    checkout_status=$?
    if [ "$checkout_status" -eq 0 ]; then
      swap_managed_ancestor || exit
    fi
    exit "$checkout_status"
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

pr_state() {
  local branch=$1 state=$2 oid=${3:-} cross=${4:-false}
  local head_owner=${5:-owner} head_repo=${6:-project} url=${7:-}
  [ -n "$oid" ] || oid=$(git -C "$PRIMARY" rev-parse "$branch") || return 1
  [ -n "$url" ] || url=https://github.com/owner/project/pull/9000
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$state" "$branch" "$cross" "$head_owner" "$head_repo" "$url" "$oid" \
    >"$PWT_GH_STATES/$(printf '%s' "$branch" | tr '/' '-')"
}

pr_state_failure() {
  : >"$PWT_GH_FAILURES/$(printf '%s' "$1" | tr '/' '-')"
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

# Advances a PR head while changing one tracked file. Hidden-index regressions
# need a target tree that would actually overwrite the local edit; advancing an
# otherwise identical tree would let a missing guard pass for the wrong reason.
push_pr_file_change() {
  local number=$1 branch=$2 path=$3 contents=$4 clone oid
  clone="$TMP/file-change-$number"
  git clone -q "$REMOTE" "$clone" >/dev/null 2>&1 || return 1
  git -C "$clone" fetch -q origin "refs/heads/$branch" || return 1
  git -C "$clone" checkout -q --detach FETCH_HEAD || return 1
  printf '%s\n' "$contents" >"$clone/$path" || return 1
  git -C "$clone" add -f -- "$path" || return 1
  git -C "$clone" -c commit.gpgsign=false commit -qm \
    "change $path for $branch" || return 1
  oid=$(git -C "$clone" rev-parse HEAD) || return 1
  git -C "$clone" push -q origin "$oid:refs/heads/$branch" || return 1
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
  (
    cd "$dir" || exit 1
    printf '%s\n' "${1-}" >>"$PWT_TEST_COMMAND_LOG"
    "$PWT" "$@"
  )
}
pwt() { pwt_in "$PRIMARY" "$@"; }
pwt_utf8() {
  (export LC_ALL=en_US.UTF-8; pwt "$@")
}
pwt_with_pi_env() {
  local agent_dir=$1 session_dir=$2 package_dir=$3
  shift 3
  (
    cd "$PRIMARY" || exit 1
    PI_CODING_AGENT_DIR=$agent_dir \
      PI_CODING_AGENT_SESSION_DIR=$session_dir \
      PI_PACKAGE_DIR=$package_dir "$PWT" "$@"
  )
}
pwt_with_path() {
  local selected_path=$1
  shift
  (cd "$PRIMARY" && PATH="$selected_path" "$PWT" "$@")
}
pwt_in_with_path() {
  local dir=$1 selected_path=$2
  shift 2
  (cd "$dir" && PATH="$selected_path" "$PWT" "$@")
}
pwt_with_root() {
  local dir=$1 root=$2
  shift 2
  (cd "$dir" && PWT_REPO_ROOT="$root" "$PWT" "$@")
}
pwt_with_ambient_repo() {
  local dir=$1 root=$2 ambient_repo=$3
  shift 3
  (
    export GH_REPO="$ambient_repo"
    pwt_with_root "$dir" "$root" "$@"
  )
}
pwt_with_ambient_host() {
  local dir=$1 root=$2 ambient_host=$3
  shift 3
  (
    export GH_HOST="$ambient_host"
    pwt_with_root "$dir" "$root" "$@"
  )
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
pwt_inject_managed_ancestor_symlink() {
  local ancestor=$1 saved=$2 outside=$3
  shift 3
  (
    export PWT_TEST_GIT_FAIL=inject-managed-ancestor-symlink
    export PWT_TEST_MANAGED_ANCESTOR="$ancestor"
    export PWT_TEST_MANAGED_SAVED="$saved"
    export PWT_TEST_MANAGED_OUTSIDE="$outside"
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
if grep -Eq '(^|[[:space:]])(mapfile|readarray|(declare|local)[[:space:]]+-A)([[:space:]]|$)' \
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
# input. This also pins the rule that errors do not echo credential-bearing
# remote URLs.
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

utf8_remote_output=$(LC_ALL=en_US.UTF-8 \
  probe_remote 'https://host/ownér/repo' || true)
check_equals 'a UTF-8 locale cannot widen remote identity allowlists' '' \
  "$(root_value "$utf8_remote_output" managed_root)"
utf8_host_output=$(LC_ALL=en_US.UTF-8 \
  probe_remote 'https://höst/owner/repo' || true)
check_equals 'a UTF-8 locale cannot widen remote host allowlists' '' \
  "$(root_value "$utf8_host_output" managed_root)"

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
launched_has_arg() {
  local expected=$1 expected_file="$TMP/expected-arg" count index=0
  printf '%s' "$expected" >"$expected_file"
  count=$(launched argc)
  while [ "$index" -lt "${count:-0}" ]; do
    if [ -f "$PWT_TEST_ARGS_DIR/$index" ] &&
      cmp -s "$expected_file" "$PWT_TEST_ARGS_DIR/$index"; then
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}
check_pr_policy_rejects() {
  local label=$1
  shift
  launch_reset
  if pwt pr 121 -- "$@" >/dev/null 2>&1; then
    not_ok "$label"
  elif [ -n "$(launched pwd)" ]; then
    not_ok "$label (Pi launched)"
  else
    ok "$label"
  fi
}

launch_reset
pwt root >/dev/null 2>&1
check_equals 'root launches pi from the physical primary checkout' "$PRIMARY" "$(launched pwd)"
check_equals 'root exports PWT_REPO_ROOT equal to the physical primary checkout' \
  "$PRIMARY" "$(launched PWT_REPO_ROOT)"
check_equals 'root passes no arguments to pi by default' '0' "$(launched argc)"

launch_reset
pwt_with_pi_env relative-agent relative-sessions relative-package \
  root >/dev/null 2>&1
check_equals 'normal launch preserves the Pi agent-directory override' \
  'relative-agent' "$(launched PI_CODING_AGENT_DIR)"
check_equals 'normal launch preserves the Pi session-directory override' \
  'relative-sessions' "$(launched PI_CODING_AGENT_SESSION_DIR)"
check_equals 'normal launch preserves the Pi package-directory override' \
  'relative-package' "$(launched PI_PACKAGE_DIR)"

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
check 'git accepts the UTF-8 branch used to isolate locale collation' \
  git -C "$PRIMARY" check-ref-format --branch 'feat/ownér'
check_output 'a UTF-8 locale cannot widen the worktree-name allowlist' \
  'safe directory name' pwt_utf8 new 'feat/ownér'
check_ref_absent 'the rejected UTF-8 path segment leaves no branch' \
  'refs/heads/feat/ownér'
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

# The managed root itself can be replaced after repository discovery. Checking
# only the final target misses an ancestor symlink and lets Git populate the
# attacker's directory before the later ownership check notices.
ROOT_RACE_ANCESTOR=${MANAGED%/project}
ROOT_RACE_SAVED="$TMP/root-race-saved-owner"
ROOT_RACE_OUTSIDE="$TMP/root-race-outside"
ROOT_RACE_TARGET="$ROOT_RACE_OUTSIDE/project/feat-root-ancestor-race"
mkdir -p "$ROOT_RACE_OUTSIDE"
launch_reset
root_race_status=0
root_race_output=$(pwt_inject_managed_ancestor_symlink \
  "$ROOT_RACE_ANCESTOR" "$ROOT_RACE_SAVED" "$ROOT_RACE_OUTSIDE" \
  new feat/root-ancestor-race 2>&1) || root_race_status=$?
check 'new refuses a managed-root ancestor substituted during fetch' \
  test "$root_race_status" -ne 0
check_contains 'managed-root substitution names the changed root' \
  'managed worktree root changed' "$root_race_output"
check 'managed-root revalidation creates no directory outside the trusted root' \
  test ! -e "$ROOT_RACE_OUTSIDE/project"
check_equals 'managed-root substitution never launches Pi' '' "$(launched pwd)"
# A missing guard can register the outside path. Remove that failed RED-state
# fixture before restoring the real managed-root ancestor for later sections.
"$PWT_TEST_REAL_GIT" -C "$PRIMARY" worktree remove --force \
  "$ROOT_RACE_TARGET" >/dev/null 2>&1 || true
rm -f "$ROOT_RACE_ANCESTOR"
mv "$ROOT_RACE_SAVED" "$ROOT_RACE_ANCESTOR"

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
  'could not fetch origin/feat/git-failure' pwt branch feat/git-failure
check 'a failed fetch leaves no target worktree behind' \
  test ! -e "$MANAGED/feat-git-failure"
check_equals 'a failed fetch never launches Pi' '' "$(launched pwd)"
git -C "$PRIMARY" remote set-url origin "$REMOTE"

section 'network git calls over ssh'

# Every fixture so far uses a file-path remote, which never invokes ssh. These
# cases point origin at an ssh:// URL for one probe and restore it afterwards —
# $REMOTE stays the origin for every other section in this suite.
PWT_TEST_SSH_LOG="$TMP/ssh.log"
: >"$PWT_TEST_SSH_LOG"
export PWT_TEST_SSH_LOG

# Fails at once with ssh's own timeout wording, the same shape a real unreachable
# host produces under BatchMode — deterministic and fast, no real network wait.
SSH_FAIL_DIR="$TMP/ssh-fail"
mkdir -p "$SSH_FAIL_DIR"
cat >"$SSH_FAIL_DIR/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'fail: %s\n' "$*" >>"$PWT_TEST_SSH_LOG"
echo 'ssh: connect to host stub.invalid port 22: Operation timed out' >&2
exit 255
STUB
chmod +x "$SSH_FAIL_DIR/ssh"

# Runs its last argument locally instead of connecting anywhere; ${!#} is that
# last positional parameter.
SSH_PROXY_DIR="$TMP/ssh-proxy"
mkdir -p "$SSH_PROXY_DIR"
cat >"$SSH_PROXY_DIR/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'proxy: %s\n' "$*" >>"$PWT_TEST_SSH_LOG"
exec sh -c "${!#}"
STUB
chmod +x "$SSH_PROXY_DIR/ssh"

# Absolute fixture path, so owner/repo parsing behaves exactly as it does for
# every other case in this suite.
SSH_ORIGIN="ssh://git@stub.invalid$REMOTE"
with_ssh_origin() { git -C "$PRIMARY" remote set-url origin "$SSH_ORIGIN"; }
restore_origin() { git -C "$PRIMARY" remote set-url origin "$REMOTE"; }

# --- new: origin unreachable over ssh ------------------------------------

with_ssh_origin
launch_reset
: >"$PWT_TEST_SSH_LOG"
new_unreachable_out=$(pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" new fix/ssh-unreachable-new 2>&1)
new_unreachable_rc=$?
unreachable_ssh_log=$(cat "$PWT_TEST_SSH_LOG")
restore_origin

if [ "$new_unreachable_rc" -ne 0 ]; then
  ok 'new fails when origin is unreachable over ssh'
else
  not_ok 'new fails when origin is unreachable over ssh'
fi

check_contains 'new shows the ssh error when the default-branch lookup fails' \
  'Operation timed out' "$new_unreachable_out"

check_contains 'new explains why the default-branch lookup failed' \
  'cannot determine the current origin default branch' "$new_unreachable_out"

# Catches the note being dropped, or moved inside default_remote_branch where
# `note`'s stdout would be captured into $base instead of printed. Position, not
# just presence, is the assertion: printed line numbers within the SAME captured
# stream preserve real chronological order here (stdout and stderr share one fd
# after 2>&1).
note_line=$(printf '%s\n' "$new_unreachable_out" | grep -n "resolving origin's default branch" | head -1 | cut -d: -f1)
error_line=$(printf '%s\n' "$new_unreachable_out" | grep -n 'Operation timed out' | head -1 | cut -d: -f1)
if [ -n "$note_line" ] && [ -n "$error_line" ] && [ "$note_line" -lt "$error_line" ]; then
  ok 'new names the default-branch lookup before it runs'
else
  not_ok 'new names the default-branch lookup before it runs'
fi

if [ ! -e "$MANAGED/fix-ssh-unreachable-new" ] && [ -z "$(launched pwd)" ]; then
  ok 'new neither creates a worktree nor launches pi when origin is unreachable'
else
  not_ok 'new neither creates a worktree nor launches pi when origin is unreachable'
fi

# $unreachable_ssh_log only ever holds the ls-remote call — this "new" run dies
# in default_remote_branch before reaching the fetch; the fetch's own flags are
# covered separately by the proxy-mode cases below.
check_contains 'network git calls run ssh in batch mode' \
  '-o BatchMode=yes' "$unreachable_ssh_log"
check_contains 'network git calls bound the ssh connect time' \
  '-o ConnectTimeout=10' "$unreachable_ssh_log"
if printf '%s' "$unreachable_ssh_log" | grep -qF -- '-o ServerAliveInterval=15' &&
  printf '%s' "$unreachable_ssh_log" | grep -qF -- '-o ServerAliveCountMax=2'; then
  ok 'network git calls bound a stalled ssh session'
else
  not_ok 'network git calls bound a stalled ssh session'
fi

# --- new: ls-remote fails despite printing a valid ref ----------------------
#
# The empty-ref check alone cannot catch this: ref is non-empty. Only the
# explicit `if ! ref=$(...)` exit check does. Plain origin (no ssh) — this pins
# the exit-status handling, not the ssh plumbing.
FAILGIT_LSREMOTE="$TMP/failgit-lsremote"
mkdir -p "$FAILGIT_LSREMOTE"
cat >"$FAILGIT_LSREMOTE/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "ls-remote" ]; then
    printf 'ref: refs/heads/main\tHEAD\n'
    exit 128
  fi
done
exec $(command -v git) "\$@"
STUB
chmod +x "$FAILGIT_LSREMOTE/git"

launch_reset
lsremote_out=$(pwt_in_with_path "$PRIMARY" "$FAILGIT_LSREMOTE:$PATH" new fix/lsremote-fails 2>&1)
lsremote_rc=$?
if [ "$lsremote_rc" -ne 0 ] && printf '%s' "$lsremote_out" | grep -qF 'cannot determine the current origin default branch'; then
  ok 'new refuses a default branch from a failed ls-remote'
else
  not_ok 'new refuses a default branch from a failed ls-remote'
fi
check 'no worktree is created when ls-remote exits non-zero despite valid output' \
  test ! -e "$MANAGED/fix-lsremote-fails"

# --- new: happy path over ssh ------------------------------------------------

with_ssh_origin
launch_reset
: >"$PWT_TEST_SSH_LOG"
pwt_in_with_path "$PRIMARY" "$SSH_PROXY_DIR:$PATH" new fix/ssh-over-ssh-new >/dev/null 2>&1
restore_origin

check_equals 'new over ssh creates the worktree and launches pi' \
  "$MANAGED/fix-ssh-over-ssh-new" "$(launched pwd)"
check_equals 'batch-mode ssh settings do not reach the launched pi session' \
  '<unset>' "$(launched GIT_SSH_COMMAND)"

proxy_lines=$(grep -c '^proxy: ' "$PWT_TEST_SSH_LOG")
proxy_batch_lines=$(grep -c '^proxy: .*BatchMode=yes' "$PWT_TEST_SSH_LOG")
if [ "$proxy_lines" -eq 2 ] && [ "$proxy_batch_lines" -eq 2 ]; then
  ok 'new over ssh runs both the lookup and the fetch through batch-mode ssh'
else
  not_ok "new over ssh runs both the lookup and the fetch through batch-mode ssh (calls: $proxy_lines, batch: $proxy_batch_lines)"
fi

# --- branch: origin unreachable over ssh ------------------------------------

with_ssh_origin
launch_reset
: >"$PWT_TEST_SSH_LOG"
branch_fail_out=$(pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" branch feat/ssh-unreachable-branch 2>&1)
restore_origin

check_contains 'branch shows the ssh error when fetching origin fails' \
  'Operation timed out' "$branch_fail_out"
check_contains 'branch blames the fetch, not a missing branch, when origin is unreachable' \
  'could not fetch origin/feat/ssh-unreachable-branch: not on origin, or origin unreachable' \
  "$branch_fail_out"

# --- branch: happy path over ssh --------------------------------------------
#
# A branch that exists only on $REMOTE and has never been fetched — every other
# 'branch' fixture for this shape has already been fetched by this point in the
# suite, which would reuse the tracking ref instead of exercising the fetch.
# The only case in this file that catches cmd_branch's fetch reverting to plain
# `git` — the fail-mode branch cases above assert on the die message, not on
# what ssh was actually invoked with.
(
  cd "$TMP/seed" || exit 1
  git checkout -q -b feat/ssh-proxy-branch
  printf 'ssh proxy\n' >ssh-proxy.txt
  git add ssh-proxy.txt
  git commit -qm 'ssh proxy branch fixture'
  git push -q origin feat/ssh-proxy-branch
)

with_ssh_origin
launch_reset
: >"$PWT_TEST_SSH_LOG"
pwt_in_with_path "$PRIMARY" "$SSH_PROXY_DIR:$PATH" branch feat/ssh-proxy-branch >/dev/null 2>&1
restore_origin

check 'branch over ssh creates the worktree' \
  test -f "$MANAGED/feat-ssh-proxy-branch/ssh-proxy.txt"
if grep -q '^proxy: .*BatchMode=yes' "$PWT_TEST_SSH_LOG"; then
  ok 'branch over ssh fetches through batch-mode ssh'
else
  not_ok 'branch over ssh fetches through batch-mode ssh'
fi

# --- base command precedence: GIT_SSH_COMMAND, core.sshCommand, GIT_SSH ----
#
# Each stub fails at once and is referenced directly (by full path), never
# through PATH, so a real "ssh" is never invoked. $SSH_FAIL_DIR stays prepended
# to PATH in every case below as a decoy: if the matching fallback were dropped,
# remote_git would fall through to plain "ssh" and the decoy's `fail:` marker
# would show up instead of the expected one. The three cases above each
# configure one source at a time; the two below configure two at once and pin
# which one wins, so the chain's ORDER is covered too, not just presence.

SSH_CORE_STUB="$TMP/ssh-core-stub.sh"
cat >"$SSH_CORE_STUB" <<'STUB'
#!/usr/bin/env bash
printf 'core: %s\n' "$*" >>"$PWT_TEST_SSH_LOG"
exit 255
STUB
chmod +x "$SSH_CORE_STUB"

with_ssh_origin
git -C "$PRIMARY" config core.sshCommand "$SSH_CORE_STUB"
launch_reset
: >"$PWT_TEST_SSH_LOG"
pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" new fix/core-sshcommand >/dev/null 2>&1
git -C "$PRIMARY" config --unset core.sshCommand
restore_origin

if grep -q '^core: .*BatchMode=yes' "$PWT_TEST_SSH_LOG" && ! grep -q '^fail: ' "$PWT_TEST_SSH_LOG"; then
  ok 'network git calls keep a configured core.sshCommand'
else
  not_ok 'network git calls keep a configured core.sshCommand'
fi

# cwd equals $PRIMARY in every case above, so a bare `git config` (no `-C`)
# would happen to read the right repository anyway. Run from a non-git
# directory with PWT_REPO_ROOT pointing at $PRIMARY instead — the only case
# that catches the core.sshCommand lookup losing `-C "$primary"`.
CORE_FROM_OUTSIDE="$TMP/core-from-outside"
mkdir -p "$CORE_FROM_OUTSIDE"

with_ssh_origin
git -C "$PRIMARY" config core.sshCommand "$SSH_CORE_STUB"
launch_reset
: >"$PWT_TEST_SSH_LOG"
(cd "$CORE_FROM_OUTSIDE" && PATH="$SSH_FAIL_DIR:$PATH" PWT_REPO_ROOT="$PRIMARY" "$PWT" new fix/core-from-outside) >/dev/null 2>&1
git -C "$PRIMARY" config --unset core.sshCommand
restore_origin

if grep -q '^core: .*BatchMode=yes' "$PWT_TEST_SSH_LOG" && ! grep -q '^fail: ' "$PWT_TEST_SSH_LOG"; then
  ok 'network git calls read core.sshCommand from the primary checkout when run outside git'
else
  not_ok 'network git calls read core.sshCommand from the primary checkout when run outside git'
fi

SSH_ENV_STUB="$TMP/ssh-env-stub.sh"
cat >"$SSH_ENV_STUB" <<'STUB'
#!/usr/bin/env bash
printf 'env: %s\n' "$*" >>"$PWT_TEST_SSH_LOG"
exit 255
STUB
chmod +x "$SSH_ENV_STUB"

with_ssh_origin
launch_reset
: >"$PWT_TEST_SSH_LOG"
GIT_SSH_COMMAND="$SSH_ENV_STUB" pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" new fix/env-sshcommand >/dev/null 2>&1
restore_origin

if grep -q '^env: .*BatchMode=yes' "$PWT_TEST_SSH_LOG" && ! grep -q '^fail: ' "$PWT_TEST_SSH_LOG"; then
  ok "network git calls keep a caller's GIT_SSH_COMMAND"
else
  not_ok "network git calls keep a caller's GIT_SSH_COMMAND"
fi

# Directory name deliberately contains a space: this is what pins printf %q —
# without it, GIT_SSH_COMMAND's shell parsing would split the path in two.
SSH_GITSSH_DIR="$TMP/gitssh with space"
mkdir -p "$SSH_GITSSH_DIR"
cat >"$SSH_GITSSH_DIR/ssh" <<'STUB'
#!/usr/bin/env bash
printf 'gitssh: %s\n' "$*" >>"$PWT_TEST_SSH_LOG"
exit 255
STUB
chmod +x "$SSH_GITSSH_DIR/ssh"

with_ssh_origin
launch_reset
: >"$PWT_TEST_SSH_LOG"
GIT_SSH="$SSH_GITSSH_DIR/ssh" pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" new fix/gitssh-var >/dev/null 2>&1
restore_origin

if grep -q '^gitssh: .*BatchMode=yes' "$PWT_TEST_SSH_LOG" && ! grep -q '^fail: ' "$PWT_TEST_SSH_LOG"; then
  ok "network git calls keep a caller's GIT_SSH program"
else
  not_ok "network git calls keep a caller's GIT_SSH program"
fi

with_ssh_origin
git -C "$PRIMARY" config core.sshCommand "$SSH_CORE_STUB"
launch_reset
: >"$PWT_TEST_SSH_LOG"
GIT_SSH_COMMAND="$SSH_ENV_STUB" pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" new fix/precedence-env-over-core >/dev/null 2>&1
git -C "$PRIMARY" config --unset core.sshCommand
restore_origin

if grep -q '^env: ' "$PWT_TEST_SSH_LOG" && ! grep -q '^core: ' "$PWT_TEST_SSH_LOG"; then
  ok "network git calls prefer a caller's GIT_SSH_COMMAND over core.sshCommand"
else
  not_ok "network git calls prefer a caller's GIT_SSH_COMMAND over core.sshCommand"
fi

with_ssh_origin
git -C "$PRIMARY" config core.sshCommand "$SSH_CORE_STUB"
launch_reset
: >"$PWT_TEST_SSH_LOG"
GIT_SSH="$SSH_GITSSH_DIR/ssh" pwt_in_with_path "$PRIMARY" "$SSH_FAIL_DIR:$PATH" new fix/precedence-core-over-gitssh >/dev/null 2>&1
git -C "$PRIMARY" config --unset core.sshCommand
restore_origin

if grep -q '^core: ' "$PWT_TEST_SSH_LOG" && ! grep -q '^gitssh: ' "$PWT_TEST_SSH_LOG"; then
  ok 'network git calls prefer core.sshCommand over GIT_SSH'
else
  not_ok 'network git calls prefer core.sshCommand over GIT_SSH'
fi

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

# A successful gh checkout can move the managed-root ancestor and replace it
# with a symlink to the moved directory. Repository/branch checks still pass
# through that link, so containment must be re-established before copy/launch.
pr_meta 329 feat/pr-fresh-root-race false
FRESH_PR_ROOT_ANCESTOR=${MANAGED%/project}
FRESH_PR_ROOT_SAVED="$TMP/pr-fresh-root-saved-owner"
printf 'swapManagedAncestor=%s\nsaveManagedAncestor=%s\n' \
  "$FRESH_PR_ROOT_ANCESTOR" "$FRESH_PR_ROOT_SAVED" >>"$PWT_GH_PRS/329"
launch_reset
fresh_pr_root_status=0
fresh_pr_root_out=$(pwt pr 329 2>&1) || fresh_pr_root_status=$?
check 'fresh PR refuses a managed-root ancestor substituted during gh checkout' \
  test "$fresh_pr_root_status" -ne 0
check_contains 'fresh PR root substitution names the changed root' \
  'managed worktree root changed' "$fresh_pr_root_out"
check 'fresh PR root substitution copies no included file outside the trusted root' \
  test ! -e "$FRESH_PR_ROOT_SAVED/project/feat-pr-fresh-root-race/.env"
check_equals 'fresh PR root substitution never launches Pi' '' "$(launched pwd)"
check 'fresh PR root substitution leaves preparation state for safe recovery' \
  test -d "$PRIMARY/.git/pwt/preparing-feat-pr-fresh-root-race"
rm -f "$FRESH_PR_ROOT_ANCESTOR"
mv "$FRESH_PR_ROOT_SAVED" "$FRESH_PR_ROOT_ANCESTOR"
git -C "$PRIMARY" worktree remove --force \
  "$MANAGED/feat-pr-fresh-root-race" >/dev/null 2>&1 || true
rmdir "$PRIMARY/.git/pwt/preparing-feat-pr-fresh-root-race" \
  >/dev/null 2>&1 || true
git -C "$PRIMARY" branch -D feat/pr-fresh-root-race >/dev/null 2>&1 || true

launch_reset
fork_out=$(pwt pr 102 2>&1)
check_contains 'pr warns before launching a fork pull request' \
  'pull request #102 comes from a fork' "$fork_out"
check_equals 'pr still launches after the fork warning' \
  "$MANAGED/feat-forked" "$(launched pwd)"

pr_meta 103 feat/pr-passthrough false
launch_reset
pwt pr 103 -- --no-session --model 'space value' '' >/dev/null 2>&1
check_equals 'permitted PR arguments stay unchanged before policy' \
  '8' "$(launched argc)"
check_arg_equals 'a permitted post-separator Pi flag reaches Pi literally' 0 '--no-session'
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
check_output 'PR numbers stay ASCII-only under a UTF-8 locale' \
  'pull request must be a number' pwt_utf8 pr 'ↅ'
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

pr_meta 109 feat/pr-utf8-invalid-oid false
utf8_invalid_oid=''
utf8_oid_i=0
while [ "$utf8_oid_i" -lt 40 ]; do
  utf8_invalid_oid="${utf8_invalid_oid}ↅ"
  utf8_oid_i=$((utf8_oid_i + 1))
done
sed "s/^headRefOid=.*/headRefOid=$utf8_invalid_oid/" "$PWT_GH_PRS/109" \
  >"$PWT_GH_PRS/109.tmp"
mv "$PWT_GH_PRS/109.tmp" "$PWT_GH_PRS/109"
launch_reset
check_output 'head object IDs stay ASCII-only under a UTF-8 locale' \
  'invalid head object ID' pwt_utf8 pr 109
check_equals 'a locale-collating non-hex object ID never launches Pi' \
  '' "$(launched pwd)"

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

# Both metadata lookup and checkout must stay pinned to the resolved origin,
# even outside Git and when gh's ambient repository override points elsewhere.
pr_meta 116 feat/pr-ambient-wrong false
mv "$PWT_GH_PRS/116" "$PWT_GH_OTHER_PRS/116"
pr_meta 116 feat/pr-ambient-right false
launch_reset
check 'pr works outside Git with an ambient GH_REPO override' \
  pwt_with_ambient_repo "$TMP" "$PRIMARY" other/wrong pr 116
check_equals 'ambient GH_REPO cannot redirect the launched PR worktree' \
  "$MANAGED/feat-pr-ambient-right" "$(launched pwd)"
check 'ambient GH_REPO leaves the other repository branch absent' \
  test ! -e "$MANAGED/feat-pr-ambient-wrong"

# A host-qualified selector must win over gh's ambient enterprise-host override.
# Removing the origin host from --repo makes both lookup and checkout select the
# wrong fixture consistently, which exact-OID validation alone cannot detect.
pr_meta 118 feat/pr-ambient-host-wrong false
mv "$PWT_GH_PRS/118" "$PWT_GH_OTHER_PRS/118"
pr_meta 118 feat/pr-ambient-host-right false
launch_reset
check 'pr works outside Git with an ambient GH_HOST override' \
  pwt_with_ambient_host "$TMP" "$PRIMARY" enterprise.example pr 118
check_equals 'ambient GH_HOST cannot redirect the launched PR worktree' \
  "$MANAGED/feat-pr-ambient-host-right" "$(launched pwd)"
check 'ambient GH_HOST leaves the other-host branch absent' \
  test ! -e "$MANAGED/feat-pr-ambient-host-wrong"

# Git permits userless SCP-style enterprise remotes. The fake enterprise URL
# cannot fetch this local fixture, but gh must still reach checkout with the
# enterprise selector rather than silently falling back to github.com.
pr_meta 120 feat/pr-userless-enterprise false
sed 's#^url=https://github.com/#url=https://enterprise.example/#' \
  "$PWT_GH_PRS/120" >"$PWT_GH_OTHER_PRS/120"
rm -f "$PWT_GH_PRS/120"
git -C "$PRIMARY" remote set-url origin \
  'enterprise.example:owner/project.git'
launch_reset
: >"$PWT_GH_LOG"
check_fails 'userless enterprise fixture fails only at its unavailable transport' \
  pwt pr 120
check_output 'pr derives an enterprise host from a userless SCP origin' \
  '--repo enterprise.example/owner/project' cat "$PWT_GH_LOG"
check_equals 'unavailable enterprise transport never launches Pi' '' "$(launched pwd)"
git -C "$PRIMARY" remote set-url origin "$REMOTE"

pr_meta 117 feat/pr-wrong-base-repo false
sed 's#^url=https://github.com/owner/project/#url=https://github.com/other/wrong/#' \
  "$PWT_GH_PRS/117" >"$PWT_GH_PRS/117.tmp"
mv "$PWT_GH_PRS/117.tmp" "$PWT_GH_PRS/117"
launch_reset
check_fails 'pr rejects a canonical-looking URL for a different repository' \
  pwt pr 117
check_equals 'wrong base-repository metadata never launches Pi' '' "$(launched pwd)"

pr_meta 119 feat/pr-wrong-base-host false
sed 's#^url=https://github.com/#url=https://enterprise.example/#' \
  "$PWT_GH_PRS/119" >"$PWT_GH_PRS/119.tmp"
mv "$PWT_GH_PRS/119.tmp" "$PWT_GH_PRS/119"
launch_reset
check_fails 'pr rejects a canonical-looking URL for a different host' \
  pwt pr 119
check_equals 'wrong base-host metadata never launches Pi' '' "$(launched pwd)"

rm -f "$PRIMARY/.worktreeinclude" "$PRIMARY/.env"

# ----------------------------------------------------------- PR launch policy

section 'pr-policy'

pr_meta 121 feat/pr-policy false
launch_reset
check 'PR launch accepts ordinary model, thinking, and prompt arguments' \
  pwt pr 121 -- --model 'model value' --thinking high 'prompt value'
check_equals 'PR launch appends exactly four enforcement tokens' \
  '9' "$(launched argc)"
check_arg_equals 'PR launch preserves the model option first' 0 '--model'
check_arg_equals 'PR launch preserves the model value' 1 'model value'
check_arg_equals 'PR launch preserves the thinking option' 2 '--thinking'
check_arg_equals 'PR launch preserves the thinking value' 3 'high'
check_arg_equals 'PR launch preserves the prompt before policy' 4 'prompt value'
check_arg_equals 'PR policy disables extension discovery last' 5 '--no-extensions'
check_arg_equals 'PR policy appends the tool option' 6 '--tools'
check_arg_equals 'PR policy appends only read-only tools' 7 'read,grep,find,ls'
check_arg_equals 'PR policy appends the no-approve trust boundary' 8 '--no-approve'
check_fails 'PR policy keeps AGENTS and CLAUDE context discovery enabled' \
  launched_has_arg '--no-context-files'
check_fails 'PR policy does not append the short context-disable alias' \
  launched_has_arg '-nc'

launch_reset
check 'reused PR worktrees receive the same launch policy' \
  pwt pr 121 -- --provider google
check_equals 'reused PR launch keeps permitted arguments before policy' \
  '6' "$(launched argc)"
check_arg_equals 'reused PR launch preserves its provider option' 0 '--provider'
check_arg_equals 'reused PR launch preserves its provider value' 1 'google'
check_arg_equals 'reused PR launch disables extension discovery' 2 '--no-extensions'
check_arg_equals 'reused PR launch appends the tool option' 3 '--tools'
check_arg_equals 'reused PR launch appends only read-only tools' 4 'read,grep,find,ls'
check_arg_equals 'reused PR launch appends no-approve last' 5 '--no-approve'

launch_reset
dash_value_status=0
dash_value_out=$(pwt pr 121 -- --name -review \
  --system-prompt --approve 2>&1) || dash_value_status=$?
if [ "$dash_value_status" -eq 0 ]; then
  ok 'PR policy preserves dash-leading values using Pi parser semantics'
else
  not_ok "PR policy preserves dash-leading values using Pi parser semantics ($dash_value_out)"
fi
check_equals 'dash-leading values remain before the enforced suffix' \
  '8' "$(launched argc)"
check_arg_equals 'dash-leading name option remains unchanged' 0 '--name'
check_arg_equals 'dash-leading name value remains unchanged' 1 '-review'
check_arg_equals 'system prompt option remains unchanged' 2 '--system-prompt'
check_arg_equals 'option-looking system prompt remains a value' 3 '--approve'
check_arg_equals 'dash-leading value launch still disables extensions' \
  4 '--no-extensions'
check_arg_equals 'dash-leading value launch still appends tools' 5 '--tools'
check_arg_equals 'dash-leading value launch still limits tools' \
  6 'read,grep,find,ls'
check_arg_equals 'dash-leading value launch still appends no-approve last' \
  7 '--no-approve'

launch_reset
check 'PR policy permits audited policy-neutral Pi flags' \
  pwt pr 121 -- --no-session --offline -p 'review prompt'
check_equals 'audited flags remain before the policy suffix' \
  '8' "$(launched argc)"
check_arg_equals 'audited no-session flag remains unchanged' 0 '--no-session'
check_arg_equals 'audited offline flag remains unchanged' 1 '--offline'
check_arg_equals 'audited print flag remains unchanged' 2 '-p'
check_arg_equals 'audited print prompt remains unchanged' 3 'review prompt'
check_arg_equals 'audited flag launch still appends policy last' \
  7 '--no-approve'

launch_reset
# Pi treats a three-dash token after --print as its prompt, not as an option.
# This catches a validator that scans the prompt as an unknown flag instead.
check 'PR policy preserves Pi print prompts beginning with three dashes' \
  pwt pr 121 -- -p '--- review this change'
check_equals 'three-dash print prompts remain before the policy suffix' \
  '6' "$(launched argc)"
check_arg_equals 'three-dash print option remains unchanged' 0 '-p'
check_arg_equals 'three-dash print prompt remains unchanged' \
  1 '--- review this change'
check_arg_equals 'three-dash print launch still appends policy last' \
  5 '--no-approve'

launch_reset
# Pi leaves a dash-leading invalid TUI value for its next parser iteration.
# This catches a validator that skips a hidden policy override as that value.
check 'PR policy accepts a valid TUI mode' \
  pwt pr 121 -- --tui-mode fullscreen
check_equals 'valid TUI mode remains before the policy suffix' \
  '6' "$(launched argc)"
check_arg_equals 'valid TUI mode option remains unchanged' 0 '--tui-mode'
check_arg_equals 'valid TUI mode value remains unchanged' 1 'fullscreen'
check_arg_equals 'valid TUI mode launch still appends policy last' \
  5 '--no-approve'

launch_reset
check 'PR policy accepts a non-RPC output mode' \
  pwt pr 121 -- --mode json
check_equals 'non-RPC output mode remains before the policy suffix' \
  '6' "$(launched argc)"
check_arg_equals 'non-RPC mode option remains unchanged' 0 '--mode'
check_arg_equals 'non-RPC mode value remains unchanged' 1 'json'
check_arg_equals 'non-RPC mode launch still appends policy last' \
  5 '--no-approve'

check_pr_policy_rejects 'PR policy rejects --tools overrides' \
  --tools read,bash
check_pr_policy_rejects 'PR policy rejects -t overrides' -t read,bash
check_pr_policy_rejects 'PR policy rejects attached --tools overrides' \
  --tools=read,bash
check_pr_policy_rejects 'PR policy rejects attached -t overrides' -tread,bash
# Pi applies excludeTools after tools, so the final --tools suffix alone cannot
# prevent a forwarded exclusion from removing an enforced read-only tool.
check_pr_policy_rejects 'PR policy rejects --exclude-tools overrides' \
  --exclude-tools read
check_pr_policy_rejects 'PR policy rejects -xt overrides' -xt read
check_pr_policy_rejects 'PR policy rejects --approve' --approve
check_pr_policy_rejects 'PR policy rejects -a' -a
check_pr_policy_rejects 'PR policy rejects --no-context-files' \
  --no-context-files
check_pr_policy_rejects 'PR policy rejects -nc' -nc
check_pr_policy_rejects 'PR policy rejects --extension paths' \
  --extension ./review.ts
check_pr_policy_rejects 'PR policy rejects --extension= paths' \
  --extension=./review.ts
check_pr_policy_rejects 'PR policy rejects -e paths' -e ./review.ts
check_pr_policy_rejects 'PR policy rejects attached -e paths' -e./review.ts
check_pr_policy_rejects 'PR policy rejects --session selection' \
  --session saved.jsonl
check_pr_policy_rejects 'PR policy rejects --session-id selection' \
  --session-id saved-id
check_pr_policy_rejects 'PR policy rejects --session-dir overrides' \
  --session-dir /tmp/poisoned
check_pr_policy_rejects 'PR policy rejects --resume selection' --resume
check_pr_policy_rejects 'PR policy rejects -r selection' -r
check_pr_policy_rejects 'PR policy rejects --continue selection' --continue
check_pr_policy_rejects 'PR policy rejects -c selection' -c
check_pr_policy_rejects 'PR policy rejects --fork selection' --fork saved.jsonl
check_pr_policy_rejects 'PR policy rejects a forwarded option terminator' --
check_pr_policy_rejects 'PR policy rejects unknown future long options' \
  --future-value
check_pr_policy_rejects 'PR policy rejects unknown short options' -z
check_pr_policy_rejects 'PR policy rejects unsupported model equals form' \
  --model=gpt-4o
check_pr_policy_rejects 'PR policy rejects unsupported api-key equals form' \
  --api-key=not-a-real-key
check_pr_policy_rejects 'PR policy rejects invalid TUI mode values' \
  --tui-mode invalid
check_pr_policy_rejects 'PR policy rejects dangling TUI mode values' \
  --tui-mode
check_output 'dangling TUI mode reports the policy diagnostic' \
  'needs regular or fullscreen after Pi option: --tui-mode' \
  pwt pr 121 -- --tui-mode
check_pr_policy_rejects 'PR policy does not let TUI mode hide extensions' \
  --tui-mode --extension ./review.ts
check_pr_policy_rejects 'PR policy does not let TUI mode hide context disabling' \
  --tui-mode --no-context-files
# Pi does not consume ordinary dash-leading options as --print prompts. These
# catch a validator that skips every token after --print instead of only ---*.
check_pr_policy_rejects 'PR policy checks extensions after print mode' \
  -p --extension ./review.ts
check_pr_policy_rejects 'PR policy checks trust flags after print mode' \
  --print --approve
check_pr_policy_rejects 'PR policy rejects RPC mode outside the tool boundary' \
  --mode rpc
check_pr_policy_rejects 'PR policy rejects session export mode' \
  --export /tmp/private-session.jsonl /tmp/session.html
# These commands run before Pi creates the restricted agent session. Removing
# this guard would let the stub launch and make every assertion below fail.
for reserved_command in auth install remove uninstall update list config; do
  check_pr_policy_rejects \
    "PR policy rejects Pi pre-session command $reserved_command" \
    "$reserved_command"
done
check_pr_policy_rejects 'PR policy rejects dangling value-taking options' --model
for value_option in \
  --provider --api-key --system-prompt --append-system-prompt \
  --name -n --models --thinking --skill \
  --prompt-template --theme; do
  check_pr_policy_rejects \
    "PR policy rejects dangling value-taking option $value_option" \
    "$value_option"
done

# Pi migrates a project .pi/commands directory before it creates the agent
# session. PR launch must refuse that write even when the directory is tracked.
MIGRATION_PUSH="$TMP/pr-migration-push"
git clone -q "$REMOTE" "$MIGRATION_PUSH"
git -C "$MIGRATION_PUSH" checkout -q -b feat/pr-migration-dir origin/stable
mkdir -p "$MIGRATION_PUSH/.pi/commands"
printf 'legacy prompt\n' >"$MIGRATION_PUSH/.pi/commands/review.md"
git -C "$MIGRATION_PUSH" add .pi/commands/review.md
git -C "$MIGRATION_PUSH" commit -qm 'add legacy project command'
git -C "$MIGRATION_PUSH" push -q origin feat/pr-migration-dir
migration_dir_oid=$(git -C "$MIGRATION_PUSH" rev-parse HEAD)
printf 'headRefName=%s\nisCrossRepository=false\nheadRepositoryOwner=owner\nheadRepository=project\nurl=%s\nheadRefOid=%s\n' \
  'feat/pr-migration-dir' 'https://github.com/owner/project/pull/122' \
  "$migration_dir_oid" >"$PWT_GH_PRS/122"

launch_reset
check_fails 'PR policy refuses a tracked startup migration' pwt pr 122
check_output 'tracked migration refusal explains the pre-session write' \
  'would migrate .pi/commands to .pi/prompts before launch' pwt pr 122
check_equals 'tracked migration refusal never launches Pi' \
  '' "$(launched pwd)"
check 'tracked migration refusal preserves the commands directory' \
  test -f "$MANAGED/feat-pr-migration-dir/.pi/commands/review.md"
check 'tracked migration refusal does not create the prompts directory' \
  test ! -e "$MANAGED/feat-pr-migration-dir/.pi/prompts"
check_equals 'tracked migration refusal leaves the PR worktree clean' '' \
  "$(git -C "$MANAGED/feat-pr-migration-dir" status --porcelain)"

# A committed .pi symlink can redirect that migration outside the worktree.
# Refuse the symlink itself so later external state cannot open the same path.
MIGRATION_VICTIM="$TMP/pr-migration-victim"
mkdir -p "$MIGRATION_VICTIM"
printf 'outside content\n' >"$MIGRATION_VICTIM/sentinel"
git -C "$MIGRATION_PUSH" checkout -q -B feat/pr-migration-symlink origin/stable
ln -s "$MIGRATION_VICTIM" "$MIGRATION_PUSH/.pi"
git -C "$MIGRATION_PUSH" add .pi
git -C "$MIGRATION_PUSH" commit -qm 'add escaping pi symlink'
git -C "$MIGRATION_PUSH" push -q origin feat/pr-migration-symlink
migration_symlink_oid=$(git -C "$MIGRATION_PUSH" rev-parse HEAD)
printf 'headRefName=%s\nisCrossRepository=false\nheadRepositoryOwner=owner\nheadRepository=project\nurl=%s\nheadRefOid=%s\n' \
  'feat/pr-migration-symlink' 'https://github.com/owner/project/pull/123' \
  "$migration_symlink_oid" >"$PWT_GH_PRS/123"

launch_reset
check_fails 'PR policy refuses a symlinked project config directory' pwt pr 123
check_output 'symlinked config refusal names the unsafe path shape' \
  'does not allow a symlinked .pi directory' pwt pr 123
check_equals 'symlinked config refusal never launches Pi' \
  '' "$(launched pwd)"
check 'symlinked config refusal preserves the outside target' \
  test -f "$MIGRATION_VICTIM/sentinel"
check 'symlinked config refusal creates no outside commands directory' \
  test ! -e "$MIGRATION_VICTIM/commands"
check 'symlinked config refusal creates no outside prompts directory' \
  test ! -e "$MIGRATION_VICTIM/prompts"

# Relative Pi directory overrides resolve after pwt enters the PR worktree.
# Scrubbing them prevents a nested tracked symlink from redirecting migrations.
AGENT_DIR_VICTIM="$TMP/pr-agent-dir-victim"
mkdir -p "$AGENT_DIR_VICTIM/commands"
printf 'outside agent content\n' >"$AGENT_DIR_VICTIM/commands/review.md"
PACKAGE_DIR_VICTIM="$TMP/pr-package-dir-victim/session-dir"
git -C "$MIGRATION_PUSH" checkout -q -B feat/pr-agent-dir-env origin/stable
mkdir -p "$MIGRATION_PUSH/.pi" "$MIGRATION_PUSH/.evil"
ln -s "$AGENT_DIR_VICTIM" "$MIGRATION_PUSH/.pi/agent"
printf '{"name":"pi-fixture","piConfig":{"configDir":".evil"}}\n' \
  >"$MIGRATION_PUSH/package.json"
printf '{"sessionDir":"%s"}\n' "$PACKAGE_DIR_VICTIM" \
  >"$MIGRATION_PUSH/.evil/settings.json"
git -C "$MIGRATION_PUSH" add .pi/agent package.json .evil/settings.json
git -C "$MIGRATION_PUSH" commit -qm 'add cwd-sensitive Pi overrides'
git -C "$MIGRATION_PUSH" push -q origin feat/pr-agent-dir-env
agent_dir_oid=$(git -C "$MIGRATION_PUSH" rev-parse HEAD)
printf 'headRefName=%s\nisCrossRepository=false\nheadRepositoryOwner=owner\nheadRepository=project\nurl=%s\nheadRefOid=%s\n' \
  'feat/pr-agent-dir-env' 'https://github.com/owner/project/pull/124' \
  "$agent_dir_oid" >"$PWT_GH_PRS/124"

mkdir -p "$HOME/.pi/agent"
printf '{"sessionDir":".pi/agent/sessions"}\n' \
  >"$HOME/.pi/agent/settings.json"
launch_reset
check 'PR policy safely launches with cwd-sensitive Pi inputs hardened' \
  pwt_with_pi_env .pi/agent '' . pr 124
check_equals 'Pi agent-directory override is absent from PR launch' \
  '<unset>' "$(launched PI_CODING_AGENT_DIR)"
check_equals 'PR launch pins an absolute trusted session directory' \
  "$PRIMARY/.git/pwt/sessions/feat-pr-agent-dir-env" \
  "$(launched PI_CODING_AGENT_SESSION_DIR)"
check_equals 'Pi package-directory override is absent from PR launch' \
  '<unset>' "$(launched PI_PACKAGE_DIR)"
check 'scrubbed overrides preserve the outside commands directory' \
  test -f "$AGENT_DIR_VICTIM/commands/review.md"
check 'scrubbed overrides create no outside prompts directory' \
  test ! -e "$AGENT_DIR_VICTIM/prompts"
check 'package override creates no outside session directory' \
  test ! -e "$PACKAGE_DIR_VICTIM"
rm -f "$HOME/.pi/agent/settings.json"

# Pi loads tracked project settings before --no-approve takes effect. Refuse
# the file so an attacker-controlled sessionDir cannot write outside the PR.
SETTINGS_VICTIM="$TMP/pr-settings-victim/session-dir"
git -C "$MIGRATION_PUSH" checkout -q -B feat/pr-project-settings origin/stable
mkdir -p "$MIGRATION_PUSH/.pi"
printf '{"sessionDir":"%s"}\n' "$SETTINGS_VICTIM" \
  >"$MIGRATION_PUSH/.pi/settings.json"
git -C "$MIGRATION_PUSH" add .pi/settings.json
git -C "$MIGRATION_PUSH" commit -qm 'add external session directory setting'
git -C "$MIGRATION_PUSH" push -q origin feat/pr-project-settings
settings_oid=$(git -C "$MIGRATION_PUSH" rev-parse HEAD)
printf 'headRefName=%s\nisCrossRepository=false\nheadRepositoryOwner=owner\nheadRepository=project\nurl=%s\nheadRefOid=%s\n' \
  'feat/pr-project-settings' 'https://github.com/owner/project/pull/125' \
  "$settings_oid" >"$PWT_GH_PRS/125"

launch_reset
check_fails 'PR policy refuses tracked project settings on fresh checkout' \
  pwt pr 125
check_equals 'fresh project-settings refusal never launches Pi' \
  '' "$(launched pwd)"
launch_reset
check_fails 'PR policy refuses tracked project settings on reuse' pwt pr 125
check_output 'project-settings refusal explains the pre-session trust gap' \
  'does not allow .pi/settings.json before trust enforcement' pwt pr 125
check_equals 'reused project-settings refusal never launches Pi' \
  '' "$(launched pwd)"
check 'project-settings refusal creates no outside session directory' \
  test ! -e "$SETTINGS_VICTIM"

# Pi's env-based interpreter and helper lookup runs after pwt enters the PR.
# A relative PATH component could therefore execute a tracked PR binary first.
PATH_ATTACK_BASH_MARKER="$TMP/pr-path-bash-ran"
PATH_ATTACK_GIT_MARKER="$TMP/pr-path-git-ran"
export PATH_ATTACK_BASH_MARKER PATH_ATTACK_GIT_MARKER
git -C "$MIGRATION_PUSH" checkout -q -B feat/pr-relative-path origin/stable
printf '#!/bin/sh\nprintf executed >"$PATH_ATTACK_BASH_MARKER"\n' \
  >"$MIGRATION_PUSH/bash"
printf '#!/bin/sh\nprintf executed >"$PATH_ATTACK_GIT_MARKER"\n' \
  >"$MIGRATION_PUSH/git"
chmod +x "$MIGRATION_PUSH/bash" "$MIGRATION_PUSH/git"
git -C "$MIGRATION_PUSH" add bash git
git -C "$MIGRATION_PUSH" commit -qm 'add hostile path interpreter'
git -C "$MIGRATION_PUSH" push -q origin feat/pr-relative-path
path_oid=$(git -C "$MIGRATION_PUSH" rev-parse HEAD)
printf 'headRefName=%s\nisCrossRepository=false\nheadRepositoryOwner=owner\nheadRepository=project\nurl=%s\nheadRefOid=%s\n' \
  'feat/pr-relative-path' 'https://github.com/owner/project/pull/126' \
  "$path_oid" >"$PWT_GH_PRS/126"

launch_reset
check_fails 'PR policy rejects relative PATH entries before Pi launch' \
  pwt_with_path ".:$PATH" pr 126
check_output 'relative PATH refusal names the absolute-entry requirement' \
  'pwt pr requires absolute PATH entries' pwt_with_path ".:$PATH" pr 126
check 'relative PATH refusal never executes the tracked interpreter' \
  test ! -e "$PATH_ATTACK_BASH_MARKER"
check_equals 'relative PATH refusal never launches Pi' '' "$(launched pwd)"

# The guard must run before repository discovery when pwt starts inside an
# existing PR worktree. The fixed shebang protects script startup; the early
# validation protects the first external `git` lookup.
pwt pr 126 >/dev/null 2>&1
launch_reset
check_fails 'PR policy rejects relative PATH before repository discovery' \
  pwt_in_with_path "$MANAGED/feat-pr-relative-path" ".:$PATH" pr 126
check_output 'early relative PATH refusal uses the policy diagnostic' \
  'pwt pr requires absolute PATH entries' \
  pwt_in_with_path "$MANAGED/feat-pr-relative-path" ".:$PATH" pr 126
check 'early PATH refusal never executes the tracked Bash interpreter' \
  test ! -e "$PATH_ATTACK_BASH_MARKER"
check 'early PATH refusal never executes tracked Git' \
  test ! -e "$PATH_ATTACK_GIT_MARKER"
check_equals 'early PATH refusal never launches Pi' '' "$(launched pwd)"

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

# show-ref uses status 1 for an absent branch; every other status is a Git
# failure. Treating all failures as absence lets checkout mutate refs anyway.
pr_meta 214 feat/pr-show-ref-failure false
launch_reset
show_ref_failure_status=0
show_ref_failure_out=$(pwt_git_fail show-ref pr 214 2>&1) || \
  show_ref_failure_status=$?
check 'pr fails closed when local-branch inspection fails' \
  test "$show_ref_failure_status" -ne 0
check_contains 'pr reports the failed local-branch inspection' \
  'cannot inspect local branch' "$show_ref_failure_out"
check 'failed PR branch inspection creates no managed worktree' \
  test ! -e "$MANAGED/feat-pr-show-ref-failure"
check_equals 'failed PR branch inspection never invokes gh checkout' '0' \
  "$(grep -c '^pr checkout 214' "$PWT_GH_LOG")"
check_equals 'failed PR branch inspection never launches Pi' '' "$(launched pwd)"

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

# Legacy markerless reuse must bind the configured tracking remote to the PR's
# canonical host as well as owner/repository. Same-path repositories on another
# host are not the same identity.
pr_meta 323 feat/pr-reuse-wrong-host false
pwt pr 323 >/dev/null 2>&1
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-wrong-host.worktree-pr-url
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-wrong-host.worktree-pr-head
git -C "$PRIMARY" remote add wrong-host-323 \
  https://enterprise.example/owner/project.git
git -C "$PRIMARY" config branch.feat/pr-reuse-wrong-host.remote wrong-host-323
wrong_host_before=$(git -C "$MANAGED/feat-pr-reuse-wrong-host" rev-parse HEAD)
launch_reset
check_fails 'markerless PR reuse rejects a same-path remote on another host' \
  pwt pr 323
check_equals 'wrong-host legacy refusal preserves the branch head' \
  "$wrong_host_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-wrong-host" rev-parse HEAD)"
check_equals 'wrong-host legacy refusal never launches Pi' '' "$(launched pwd)"

# A configured branch.remote value is a name, not a URL fallback. If no such
# remote exists, owner/repository-shaped text must not authenticate reuse.
pr_meta 324 feat/pr-reuse-missing-remote false
pwt pr 324 >/dev/null 2>&1
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-missing-remote.worktree-pr-url
git -C "$PRIMARY" config --unset-all \
  branch.feat/pr-reuse-missing-remote.worktree-pr-head
git -C "$PRIMARY" config \
  branch.feat/pr-reuse-missing-remote.remote owner/project
missing_remote_before=$(git -C "$MANAGED/feat-pr-reuse-missing-remote" rev-parse HEAD)
launch_reset
check_fails 'markerless PR reuse rejects an unresolved tracking remote' pwt pr 324
check_equals 'unresolved-remote refusal preserves the branch head' \
  "$missing_remote_before" \
  "$(git -C "$MANAGED/feat-pr-reuse-missing-remote" rev-parse HEAD)"
check_equals 'unresolved-remote refusal never launches Pi' '' "$(launched pwd)"

# status deliberately hides assume-unchanged edits. Refuse before the
# authenticated fetch updates any refs, and preserve the worktree byte-for-byte.
pr_meta 325 feat/pr-reuse-assume-unchanged false
pwt pr 325 >/dev/null 2>&1
assume_pr_head=$(git -C "$MANAGED/feat-pr-reuse-assume-unchanged" rev-parse HEAD)
assume_tracking_head=$(git -C "$PRIMARY" rev-parse \
  refs/remotes/origin/feat/pr-reuse-assume-unchanged)
git -C "$MANAGED/feat-pr-reuse-assume-unchanged" update-index \
  --assume-unchanged README.md
printf 'assume-unchanged PR edit\n' \
  >"$MANAGED/feat-pr-reuse-assume-unchanged/README.md"
assume_pr_status=$(git -C "$MANAGED/feat-pr-reuse-assume-unchanged" status \
  --porcelain --untracked-files=all)
check_equals 'the PR assume-unchanged fixture is hidden from status' '' \
  "$assume_pr_status"
push_pr_file_change 325 feat/pr-reuse-assume-unchanged README.md \
  'remote assume-unchanged replacement' >/dev/null
launch_reset
assume_pr_result=0
assume_pr_out=$(pwt pr 325 2>&1) || assume_pr_result=$?
check 'PR refresh refuses assume-unchanged local state' \
  test "$assume_pr_result" -ne 0
check_contains 'PR refresh names the hidden assume-unchanged state' \
  'assume-unchanged' "$assume_pr_out"
check_equals 'assume-unchanged refusal preserves the PR worktree head' \
  "$assume_pr_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-assume-unchanged" rev-parse HEAD)"
check 'assume-unchanged refusal preserves the local file' grep -qF \
  'assume-unchanged PR edit' \
  "$MANAGED/feat-pr-reuse-assume-unchanged/README.md"
check_equals 'initial hidden-state refusal happens before the PR fetch' \
  "$assume_tracking_head" \
  "$(git -C "$PRIMARY" rev-parse refs/remotes/origin/feat/pr-reuse-assume-unchanged)"
check_equals 'assume-unchanged refusal never launches Pi' '' "$(launched pwd)"

# A materialized skip-worktree entry is hidden through the same status seam but
# has a different ls-files flag, so keep a separate behavioral regression.
pr_meta 326 feat/pr-reuse-skip-worktree false
pwt pr 326 >/dev/null 2>&1
skip_pr_head=$(git -C "$MANAGED/feat-pr-reuse-skip-worktree" rev-parse HEAD)
skip_tracking_head=$(git -C "$PRIMARY" rev-parse \
  refs/remotes/origin/feat/pr-reuse-skip-worktree)
git -C "$MANAGED/feat-pr-reuse-skip-worktree" update-index \
  --skip-worktree README.md
printf 'skip-worktree PR edit\n' \
  >"$MANAGED/feat-pr-reuse-skip-worktree/README.md"
skip_pr_status=$(git -C "$MANAGED/feat-pr-reuse-skip-worktree" status \
  --porcelain --untracked-files=all)
check_equals 'the PR skip-worktree fixture is hidden from status' '' "$skip_pr_status"
push_pr_file_change 326 feat/pr-reuse-skip-worktree README.md \
  'remote skip-worktree replacement' >/dev/null
launch_reset
skip_pr_result=0
skip_pr_out=$(pwt pr 326 2>&1) || skip_pr_result=$?
check 'PR refresh refuses materialized skip-worktree local state' \
  test "$skip_pr_result" -ne 0
check_contains 'PR refresh names the hidden skip-worktree state' \
  'materialized skip-worktree' "$skip_pr_out"
check_equals 'skip-worktree refusal preserves the PR worktree head' \
  "$skip_pr_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-skip-worktree" rev-parse HEAD)"
check 'skip-worktree refusal preserves the local file' grep -qF \
  'skip-worktree PR edit' "$MANAGED/feat-pr-reuse-skip-worktree/README.md"
check_equals 'skip-worktree refusal happens before the PR fetch' \
  "$skip_tracking_head" \
  "$(git -C "$PRIMARY" rev-parse refs/remotes/origin/feat/pr-reuse-skip-worktree)"
check_equals 'skip-worktree refusal never launches Pi' '' "$(launched pwd)"

# An ignored file can appear after the target-tree scan but before mutation.
# Inject it after the final clean status result and require the later collision
# check to preserve both the file and the old head.
pr_meta 327 feat/pr-reuse-late-ignored false
pwt pr 327 >/dev/null 2>&1
late_ignored_head=$(git -C "$MANAGED/feat-pr-reuse-late-ignored" rev-parse HEAD)
push_pr_tree_shape 327 feat/pr-reuse-late-ignored exact-file >/dev/null
late_ignored_count="$TMP/pr-late-ignored-status-count"
: >"$late_ignored_count"
launch_reset
late_ignored_result=0
late_ignored_out=$(
  PWT_TEST_GIT_FAIL=pr-ignored-after-final-status \
    PWT_TEST_PR_LATE_TARGET="$MANAGED/feat-pr-reuse-late-ignored" \
    PWT_TEST_PR_LATE_COUNT="$late_ignored_count" \
    pwt pr 327 2>&1
) || late_ignored_result=$?
check 'PR refresh refuses an ignored collision created at the mutation boundary' \
  test "$late_ignored_result" -ne 0
check_contains 'late ignored collision names the protected path' \
  '.env' "$late_ignored_out"
check_equals 'late ignored fixture reaches the final status boundary' '2' \
  "$(sed -n 1p "$late_ignored_count")"
check_equals 'late ignored collision preserves the PR worktree head' \
  "$late_ignored_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-late-ignored" rev-parse HEAD)"
check 'late ignored collision preserves the local file' grep -qF \
  'late ignored local content' "$MANAGED/feat-pr-reuse-late-ignored/.env"
check_equals 'late ignored collision never launches Pi' '' "$(launched pwd)"

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

pr_meta 321 feat/pr-reuse-dirty-during-fetch false
pwt pr 321 >/dev/null 2>&1
dirty_during_head=$(git -C "$MANAGED/feat-pr-reuse-dirty-during-fetch" rev-parse HEAD)
rewrite_pr_head feat/pr-reuse-dirty-during-fetch >/dev/null
printf 'dirtyAfterFetchPath=%s\n' \
  "$MANAGED/feat-pr-reuse-dirty-during-fetch" >>"$PWT_GH_PRS/321"
launch_reset
dirty_during_status=0
dirty_during_out=$(pwt pr 321 2>&1) || dirty_during_status=$?
check 'pr refuses edits created during the disposable fetch' \
  test "$dirty_during_status" -ne 0
check_equals 'mid-fetch edit preserves the reused branch head' "$dirty_during_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-dirty-during-fetch" rev-parse HEAD)"
check 'mid-fetch tracked edit remains in the worktree' \
  grep -q '^dirty during disposable fetch$' \
  "$MANAGED/feat-pr-reuse-dirty-during-fetch/README.md"
check_equals 'mid-fetch edit preserves the last verified head marker' \
  "$dirty_during_head" \
  "$(pr_marker feat/pr-reuse-dirty-during-fetch worktree-pr-head)"
check_equals 'mid-fetch edit never launches Pi' '' "$(launched pwd)"

# Hidden index state can be introduced after the initial guard. Inject an
# assume-unchanged edit during authenticated fetch so only the mutation-boundary
# hidden-state check can prevent the refresh.
pr_meta 328 feat/pr-reuse-hidden-during-fetch false
pwt pr 328 >/dev/null 2>&1
hidden_during_head=$(git -C "$MANAGED/feat-pr-reuse-hidden-during-fetch" rev-parse HEAD)
push_pr_file_change 328 feat/pr-reuse-hidden-during-fetch README.md \
  'remote replacement for late hidden edit' >/dev/null
printf 'assumeAfterFetchPath=%s\n' \
  "$MANAGED/feat-pr-reuse-hidden-during-fetch" >>"$PWT_GH_PRS/328"
launch_reset
hidden_during_status=0
hidden_during_out=$(pwt pr 328 2>&1) || hidden_during_status=$?
check 'pr refuses hidden index state introduced during disposable fetch' \
  test "$hidden_during_status" -ne 0
check_contains 'mid-fetch hidden-state refusal names assume-unchanged' \
  'assume-unchanged' "$hidden_during_out"
check_equals 'mid-fetch hidden state preserves the reused branch head' \
  "$hidden_during_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-hidden-during-fetch" rev-parse HEAD)"
check 'mid-fetch hidden state preserves the local edit' grep -qF \
  'hidden during disposable fetch' \
  "$MANAGED/feat-pr-reuse-hidden-during-fetch/README.md"
check_equals 'mid-fetch hidden state preserves the last verified head marker' \
  "$hidden_during_head" \
  "$(pr_marker feat/pr-reuse-hidden-during-fetch worktree-pr-head)"
check_equals 'mid-fetch hidden state never launches Pi' '' "$(launched pwd)"

# Reused PR fetching has the same ancestor-substitution boundary, but its
# disposable worktree must remain blocked rather than be removed through the
# substituted path. The real PR worktree must not refresh or launch.
pr_meta 330 feat/pr-reuse-root-race false
pwt pr 330 >/dev/null 2>&1
reuse_root_head=$(git -C "$MANAGED/feat-pr-reuse-root-race" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-root-race >/dev/null
REUSE_PR_ROOT_ANCESTOR=${MANAGED%/project}
REUSE_PR_ROOT_SAVED="$TMP/pr-reuse-root-saved-owner"
printf 'swapManagedAncestor=%s\nsaveManagedAncestor=%s\n' \
  "$REUSE_PR_ROOT_ANCESTOR" "$REUSE_PR_ROOT_SAVED" >>"$PWT_GH_PRS/330"
launch_reset
reuse_root_status=0
reuse_root_out=$(pwt pr 330 2>&1) || reuse_root_status=$?
check 'reused PR refuses a managed-root ancestor substituted during gh fetch' \
  test "$reuse_root_status" -ne 0
check_contains 'reused PR reports its blocked disposable fetch worktree' \
  'temporary PR fetch worktree remains blocked' "$reuse_root_out"
check_equals 'reused PR root substitution preserves the branch head' \
  "$reuse_root_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-root-race" rev-parse HEAD)"
check_equals 'reused PR root substitution never launches Pi' '' "$(launched pwd)"
reuse_root_fetch=$(git -C "$PRIMARY" worktree list --porcelain | \
  sed -n 's#^worktree \(.*\.pwt-pr-fetch\.[^/]*\)$#\1#p' | head -1)
check 'reused PR preserves the disposable worktree when containment changed' \
  test -n "$reuse_root_fetch"
rm -f "$REUSE_PR_ROOT_ANCESTOR"
mv "$REUSE_PR_ROOT_SAVED" "$REUSE_PR_ROOT_ANCESTOR"
if [ -n "$reuse_root_fetch" ]; then
  git -C "$PRIMARY" worktree remove --force "$reuse_root_fetch" \
    >/dev/null 2>&1 || true
fi

# If containment changes after the post-gh check but before scratch cleanup,
# cleanup must preserve the disposable worktree rather than remove it through
# the substituted root.
pr_meta 331 feat/pr-reuse-root-cleanup-race false
pwt pr 331 >/dev/null 2>&1
reuse_cleanup_head=$(git -C \
  "$MANAGED/feat-pr-reuse-root-cleanup-race" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-root-cleanup-race >/dev/null
REUSE_CLEANUP_ANCESTOR=${MANAGED%/project}
REUSE_CLEANUP_SAVED="$TMP/pr-reuse-cleanup-saved-owner"
launch_reset
reuse_cleanup_status=0
reuse_cleanup_out=$(
  export PWT_TEST_GIT_FAIL=pr-fetch-root-after-head
  export PWT_TEST_MANAGED_ANCESTOR="$REUSE_CLEANUP_ANCESTOR"
  export PWT_TEST_MANAGED_SAVED="$REUSE_CLEANUP_SAVED"
  pwt pr 331 2>&1
) || reuse_cleanup_status=$?
check 'reused PR refuses root substitution immediately before fetch cleanup' \
  test "$reuse_cleanup_status" -ne 0
check_contains 'fetch-cleanup root substitution reports the blocked worktree' \
  'temporary PR fetch worktree remains blocked' "$reuse_cleanup_out"
check_equals 'fetch-cleanup root substitution preserves the reused branch head' \
  "$reuse_cleanup_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-root-cleanup-race" rev-parse HEAD)"
check_equals 'fetch-cleanup root substitution never launches Pi' '' "$(launched pwd)"
reuse_cleanup_fetch=$(git -C "$PRIMARY" worktree list --porcelain | \
  sed -n 's#^worktree \(.*\.pwt-pr-fetch\.[^/]*\)$#\1#p' | head -1)
check 'fetch-cleanup root substitution preserves the disposable worktree' \
  test -n "$reuse_cleanup_fetch"
rm -f "$REUSE_CLEANUP_ANCESTOR"
mv "$REUSE_CLEANUP_SAVED" "$REUSE_CLEANUP_ANCESTOR"
if [ -n "$reuse_cleanup_fetch" ]; then
  git -C "$PRIMARY" worktree remove --force "$reuse_cleanup_fetch" \
    >/dev/null 2>&1 || true
fi

# The root can also change after the scratch fetch has been safely removed.
# Inject at the final ignored-path scan so the refresh-boundary ownership check
# alone prevents the real branch from moving.
pr_meta 332 feat/pr-reuse-root-refresh-race false
pwt pr 332 >/dev/null 2>&1
reuse_refresh_head=$(git -C \
  "$MANAGED/feat-pr-reuse-root-refresh-race" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-root-refresh-race >/dev/null
REUSE_REFRESH_ANCESTOR=${MANAGED%/project}
REUSE_REFRESH_SAVED="$TMP/pr-reuse-refresh-saved-owner"
launch_reset
reuse_refresh_status=0
reuse_refresh_out=$(
  export PWT_TEST_GIT_FAIL=pr-root-after-ignored-scan
  export PWT_TEST_MANAGED_ANCESTOR="$REUSE_REFRESH_ANCESTOR"
  export PWT_TEST_MANAGED_SAVED="$REUSE_REFRESH_SAVED"
  pwt pr 332 2>&1
) || reuse_refresh_status=$?
check 'reused PR refuses root substitution at the refresh boundary' \
  test "$reuse_refresh_status" -ne 0
check_contains 'refresh-boundary root substitution names the changed root' \
  'managed worktree root changed' "$reuse_refresh_out"
check_equals 'refresh-boundary root substitution preserves the branch head' \
  "$reuse_refresh_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-root-refresh-race" rev-parse HEAD)"
check_equals 'refresh-boundary root substitution never launches Pi' '' "$(launched pwd)"
rm -f "$REUSE_REFRESH_ANCESTOR"
mv "$REUSE_REFRESH_SAVED" "$REUSE_REFRESH_ANCESTOR"

# Finally, move the root after a successful refresh records its marker. The
# launch-boundary check must refuse to enter the moved worktree.
pr_meta 333 feat/pr-reuse-root-launch-race false
pwt pr 333 >/dev/null 2>&1
force_advance_pr_head feat/pr-reuse-root-launch-race >/dev/null
reuse_launch_oid=$(sed -n 's/^headRefOid=//p' "$PWT_GH_PRS/333")
REUSE_LAUNCH_ANCESTOR=${MANAGED%/project}
REUSE_LAUNCH_SAVED="$TMP/pr-reuse-launch-saved-owner"
launch_reset
reuse_launch_status=0
reuse_launch_out=$(
  export PWT_TEST_GIT_FAIL=pr-root-after-head-marker
  export PWT_TEST_MANAGED_ANCESTOR="$REUSE_LAUNCH_ANCESTOR"
  export PWT_TEST_MANAGED_SAVED="$REUSE_LAUNCH_SAVED"
  export PWT_TEST_PR_ROOT_BRANCH=feat/pr-reuse-root-launch-race
  pwt pr 333 2>&1
) || reuse_launch_status=$?
check 'reused PR refuses root substitution at the launch boundary' \
  test "$reuse_launch_status" -ne 0
check_contains 'launch-boundary root substitution names the changed root' \
  'managed worktree root changed' "$reuse_launch_out"
check_equals 'launch-boundary fixture reaches the advertised PR head' \
  "$reuse_launch_oid" \
  "$(git -C "$MANAGED/feat-pr-reuse-root-launch-race" rev-parse HEAD)"
check_equals 'launch-boundary root substitution never launches Pi' '' "$(launched pwd)"
rm -f "$REUSE_LAUNCH_ANCESTOR"
mv "$REUSE_LAUNCH_SAVED" "$REUSE_LAUNCH_ANCESTOR"

pr_meta 322 feat/pr-reuse-partial-fetch-add false
pwt pr 322 >/dev/null 2>&1
partial_fetch_head=$(git -C "$MANAGED/feat-pr-reuse-partial-fetch-add" rev-parse HEAD)
force_advance_pr_head feat/pr-reuse-partial-fetch-add >/dev/null
rm -f "$PWT_TEST_PARTIAL_PATH_FILE"
launch_reset
partial_fetch_status=0
partial_fetch_out=$(pwt_git_fail pr-fetch-add-unregistered-partial \
  pr 322 2>&1) || partial_fetch_status=$?
partial_fetch_path=''
if [ -f "$PWT_TEST_PARTIAL_PATH_FILE" ]; then
  IFS= read -r partial_fetch_path <"$PWT_TEST_PARTIAL_PATH_FILE"
fi
check 'late disposable worktree-add failure exits non-zero' \
  test "$partial_fetch_status" -ne 0
check 'late disposable worktree-add fixture records its scratch path' \
  test -n "$partial_fetch_path"
check 'failed unregistered scratch cleanup preserves the blocked path' \
  test -f "$partial_fetch_path/partial"
check_contains 'failed scratch cleanup reports the blocked path' \
  "$partial_fetch_path" "$partial_fetch_out"
check_equals 'failed scratch cleanup preserves the real branch head' \
  "$partial_fetch_head" \
  "$(git -C "$MANAGED/feat-pr-reuse-partial-fetch-add" rev-parse HEAD)"
check_equals 'failed scratch cleanup never launches Pi' '' "$(launched pwd)"
if [ -n "$partial_fetch_path" ]; then
  rm -rf "$partial_fetch_path"
fi

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
cleanup_failure_registration=$("$PWT_TEST_REAL_GIT" -C "$PRIMARY" \
  worktree list --porcelain | \
  sed -n "\\#^worktree $MANAGED/feat-cleanup-failure\$#p")
check_equals 'a cleanup error leaves its worktree registered for explicit recovery' \
  "worktree $MANAGED/feat-cleanup-failure" "$cleanup_failure_registration"
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

# --------------------------------------------------------- guarded removal

section 'remove'

# A clean managed worktree is disposable, but its branch is history and remains
# unless deletion is requested explicitly.
launch_reset
pwt new feat/removable >/dev/null 2>&1
check 'the worktree to remove exists first' test -d "$MANAGED/feat-removable"
check 'remove deletes a clean managed worktree' pwt remove feat/removable
check 'the removed worktree directory is gone' test ! -d "$MANAGED/feat-removable"
check 'remove keeps the branch by default' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/removable

# Bash 3.2 expands ASCII ranges with locale collation, where uppercase H can
# match [a-z]. Run the real hidden-index check under UTF-8 so ordinary tracked
# files cannot be mistaken for assume-unchanged state.
launch_reset
pwt new feat/locale-collation >/dev/null 2>&1
check 'remove recognizes an ordinary clean worktree under a UTF-8 locale' \
  pwt_utf8 remove feat/locale-collation
check 'UTF-8 removal deletes the clean worktree' \
  test ! -e "$MANAGED/feat-locale-collation"
check 'hidden-index inspection pins bytewise collation locally' \
  grep -qF 'local LC_ALL=C path=$1 list_file record flag rel' "$PWT"

# An interrupted preparation leaves shared Git state that blocks reuse. Explicit
# removal is the recovery path, so it must clear that state after Git removes
# the worktree.
launch_reset
pwt new feat/marker-recovery >/dev/null 2>&1
remove_common=$(git -C "$PRIMARY" rev-parse \
  --path-format=absolute --git-common-dir)
remove_marker="$remove_common/pwt/preparing-feat-marker-recovery"
mkdir -p "$remove_marker"
check 'remove recovers an incompletely prepared worktree' \
  pwt remove feat/marker-recovery
check 'remove clears stale preparation state' test ! -e "$remove_marker"
launch_reset
check 'a branch is reusable after stale-state removal' \
  pwt branch feat/marker-recovery
pwt remove feat/marker-recovery >/dev/null 2>&1

launch_reset
pwt new feat/disposable >/dev/null 2>&1
check 'remove --delete-branch succeeds for a merged branch' \
  pwt remove feat/disposable --delete-branch
check_fails 'remove --delete-branch deletes the merged branch' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/disposable

# Both tracked edits and untracked files are local work. The wrapper must name
# that reason itself rather than relying on Git's eventual removal failure.
launch_reset
pwt new feat/dirty-tracked >/dev/null 2>&1
printf 'edited\n' >>"$MANAGED/feat-dirty-tracked/README.md"
check_fails 'remove refuses a worktree with tracked changes' \
  pwt remove feat/dirty-tracked
check_output 'tracked-change refusal identifies local work' \
  'uncommitted or untracked work' pwt remove feat/dirty-tracked
check 'the tracked-dirty worktree survives refusal' \
  test -d "$MANAGED/feat-dirty-tracked"

launch_reset
pwt new feat/dirty-untracked >/dev/null 2>&1
printf 'scratch\n' >"$MANAGED/feat-dirty-untracked/notes.md"
check_fails 'remove refuses a worktree with an untracked file' \
  pwt remove feat/dirty-untracked
check_output 'untracked-file refusal identifies local work' \
  'uncommitted or untracked work' pwt remove feat/dirty-untracked
check 'the untracked-dirty worktree survives refusal' \
  test -d "$MANAGED/feat-dirty-untracked"

# Git status deliberately hides assume-unchanged entries. A destructive wrapper
# must detect that index state itself rather than accepting a false clean result.
launch_reset
pwt new feat/assume-unchanged >/dev/null 2>&1
git -C "$MANAGED/feat-assume-unchanged" update-index \
  --assume-unchanged README.md
printf 'hidden local edit\n' >>"$MANAGED/feat-assume-unchanged/README.md"
assume_status=$(git -C "$MANAGED/feat-assume-unchanged" status \
  --porcelain --untracked-files=all)
check_equals 'the assume-unchanged fixture is hidden from status' '' \
  "$assume_status"
ASSUME_REMOVE_ATTEMPT="$TMP/assume-remove-attempt"
assume_remove_status=0
assume_remove_out=$(
  PWT_TEST_REMOVE_ATTEMPT="$ASSUME_REMOVE_ATTEMPT" \
    pwt remove feat/assume-unchanged 2>&1
) || assume_remove_status=$?
check 'remove refuses hidden tracked work' test "$assume_remove_status" -ne 0
check_contains 'hidden-work refusal names assume-unchanged state' \
  'assume-unchanged' "$assume_remove_out"
check 'hidden-work refusal never reaches Git removal' \
  test ! -e "$ASSUME_REMOVE_ATTEMPT"
check 'hidden-work refusal preserves the local edit' grep -qF \
  'hidden local edit' "$MANAGED/feat-assume-unchanged/README.md"

# A materialized skip-worktree entry is another way tracked edits can disappear
# from status. Assert the fixture shape before relying on the pwt refusal.
launch_reset
pwt new feat/skip-worktree >/dev/null 2>&1
git -C "$MANAGED/feat-skip-worktree" update-index --skip-worktree README.md
printf 'skip-worktree local edit\n' >>"$MANAGED/feat-skip-worktree/README.md"
skip_status=$(git -C "$MANAGED/feat-skip-worktree" status \
  --porcelain --untracked-files=all)
check_equals 'the skip-worktree fixture is hidden from status' '' "$skip_status"
SKIP_REMOVE_ATTEMPT="$TMP/skip-remove-attempt"
skip_remove_status=0
skip_remove_out=$(
  PWT_TEST_REMOVE_ATTEMPT="$SKIP_REMOVE_ATTEMPT" \
    pwt remove feat/skip-worktree 2>&1
) || skip_remove_status=$?
check 'remove refuses materialized skip-worktree state' \
  test "$skip_remove_status" -ne 0
check_contains 'skip-worktree refusal names the hidden index state' \
  'materialized skip-worktree' "$skip_remove_out"
check 'skip-worktree refusal never reaches Git removal' \
  test ! -e "$SKIP_REMOVE_ATTEMPT"
check 'skip-worktree refusal preserves the local edit' grep -qF \
  'skip-worktree local edit' "$MANAGED/feat-skip-worktree/README.md"

# A repository can configure status to ignore dirty submodules. pwt overrides
# that preference at the destructive boundary so nested local work still blocks.
SUBMODULE_SOURCE="$TMP/remove-submodule-source"
git init -q "$SUBMODULE_SOURCE"
printf 'submodule seed\n' >"$SUBMODULE_SOURCE/submodule.txt"
git -C "$SUBMODULE_SOURCE" add submodule.txt
git -C "$SUBMODULE_SOURCE" commit -qm 'seed removal submodule'
launch_reset
pwt new feat/dirty-submodule >/dev/null 2>&1
git -C "$MANAGED/feat-dirty-submodule" \
  -c protocol.file.allow=always submodule add -q \
  "$SUBMODULE_SOURCE" vendor/removal-submodule
git -C "$MANAGED/feat-dirty-submodule" commit -qam \
  'add removal submodule'
git -C "$MANAGED/feat-dirty-submodule" config \
  submodule.vendor/removal-submodule.ignore all
printf 'nested local edit\n' \
  >>"$MANAGED/feat-dirty-submodule/vendor/removal-submodule/submodule.txt"
submodule_status=$(git -C "$MANAGED/feat-dirty-submodule" status \
  --porcelain --untracked-files=all)
check_equals 'the dirty-submodule fixture is hidden by repository config' '' \
  "$submodule_status"
SUBMODULE_REMOVE_ATTEMPT="$TMP/submodule-remove-attempt"
submodule_remove_status=0
submodule_remove_out=$(
  PWT_TEST_REMOVE_ATTEMPT="$SUBMODULE_REMOVE_ATTEMPT" \
    pwt remove feat/dirty-submodule 2>&1
) || submodule_remove_status=$?
check 'remove refuses a dirty submodule hidden by repository config' \
  test "$submodule_remove_status" -ne 0
check_contains 'dirty-submodule refusal names local work' \
  'uncommitted or untracked work' "$submodule_remove_out"
check 'dirty-submodule refusal never reaches Git removal' \
  test ! -e "$SUBMODULE_REMOVE_ATTEMPT"
check 'dirty-submodule refusal preserves the nested local edit' grep -qF \
  'nested local edit' \
  "$MANAGED/feat-dirty-submodule/vendor/removal-submodule/submodule.txt"

# Ignored worktreeinclude files are intentionally disposable, but removal must
# disclose them before Git destroys the directory.
printf '.remove-secret\n' >>"$exclude_file"
printf '.remove-secret\n' >"$PRIMARY/.worktreeinclude"
printf 'SECRET=1\n' >"$PRIMARY/.remove-secret"
launch_reset
ignored_create_status=0
ignored_create_out=$(pwt new feat/has-ignored 2>&1) || ignored_create_status=$?
if [ "$ignored_create_status" -eq 0 ]; then
  ok 'the ignored removal fixture is created successfully'
else
  not_ok "the ignored removal fixture is created successfully (got: $ignored_create_out)"
fi
check 'the ignored removal fixture contains its copied file' \
  test -f "$MANAGED/feat-has-ignored/.remove-secret"
ignored_status=$(git -C "$MANAGED/feat-has-ignored" status \
  --porcelain --untracked-files=all)
check_equals 'ignored content is not reported as untracked work' '' "$ignored_status"
remove_out=$(pwt remove feat/has-ignored 2>&1)
check 'remove accepts a clean worktree containing ignored files' \
  test ! -d "$MANAGED/feat-has-ignored"
check_contains 'remove discloses the ignored file it destroys' \
  '.remove-secret' "$remove_out"
rm -f "$PRIMARY/.worktreeinclude" "$PRIMARY/.remove-secret"

# A refusal must not announce that ignored content will be destroyed.
printf 'ignored beside dirty work\n' \
  >"$MANAGED/feat-dirty-tracked/.remove-secret"
dirty_ignored_status=0
dirty_ignored_out=$(pwt remove feat/dirty-tracked 2>&1) || \
  dirty_ignored_status=$?
check 'dirty work with ignored content is still refused' \
  test "$dirty_ignored_status" -ne 0
check_not_contains 'a refused removal makes no destruction announcement' \
  'removing will destroy' "$dirty_ignored_out"

# Removing the directory containing the caller would strand its shell in a
# deleted cwd. The same worktree remains removable from elsewhere.
launch_reset
pwt new feat/self-remove >/dev/null 2>&1
check_fails 'remove refuses the caller-current worktree' \
  pwt_in "$MANAGED/feat-self-remove" remove feat/self-remove
check_output 'caller-current refusal explains the standing-directory guard' \
  'standing in' pwt_in "$MANAGED/feat-self-remove" remove feat/self-remove
check 'caller-current refusal preserves the worktree' \
  test -d "$MANAGED/feat-self-remove"
check 'the same worktree remains removable from elsewhere' \
  pwt remove feat/self-remove

launch_reset
pwt new feat/deleted-cwd-remove >/dev/null 2>&1
DELETED_CWD="$TMP/deleted-remove-cwd"
mkdir "$DELETED_CWD"
deleted_cwd_status=0
deleted_cwd_out=$(
  cd "$DELETED_CWD" || exit 1
  rmdir "$DELETED_CWD" || exit 1
  PWT_REPO_ROOT="$PRIMARY" "$PWT" remove feat/deleted-cwd-remove 2>&1
) || deleted_cwd_status=$?
check 'remove fails closed when the caller cwd no longer exists' \
  test "$deleted_cwd_status" -ne 0
check_contains 'deleted-cwd refusal uses a pwt diagnostic' \
  'cannot determine the current directory; refusing to remove' \
  "$deleted_cwd_out"
check 'deleted-cwd refusal preserves the worktree' \
  test -d "$MANAGED/feat-deleted-cwd-remove"
pwt remove feat/deleted-cwd-remove >/dev/null 2>&1

# Registration alone does not establish pwt ownership.
check_fails 'remove refuses an unmanaged worktree' pwt remove feat/stray
check_output 'unmanaged removal refusal names managed-root ownership' \
  'pwt does not manage it' pwt remove feat/stray
check 'unmanaged removal refusal preserves the worktree' test -d "$UNMANAGED"

# A path registered by the primary repository can be replaced by a clean checkout
# from another repository. Physical containment alone must not grant ownership.
launch_reset
pwt new feat/remove-wrong-repo >/dev/null 2>&1
WRONG_REPO_REAL="$TMP/remove-wrong-repo-real"
mv "$MANAGED/feat-remove-wrong-repo" "$WRONG_REPO_REAL"
git clone -q "$WRONG" "$MANAGED/feat-remove-wrong-repo"
git -C "$MANAGED/feat-remove-wrong-repo" checkout -qb \
  feat/remove-wrong-repo
WRONG_REPO_ATTEMPT="$TMP/remove-wrong-repo-attempt"
wrong_repo_status=0
wrong_repo_out=$(
  PWT_TEST_REMOVE_ATTEMPT="$WRONG_REPO_ATTEMPT" \
    pwt remove feat/remove-wrong-repo 2>&1
) || wrong_repo_status=$?
check 'remove refuses a same-branch checkout from another repository' \
  test "$wrong_repo_status" -ne 0
check_contains 'wrong-repository refusal names repository ownership' \
  'different repository' "$wrong_repo_out"
check 'wrong-repository refusal never reaches Git removal' \
  test ! -e "$WRONG_REPO_ATTEMPT"
check 'wrong-repository refusal preserves the replacement checkout' \
  test -d "$MANAGED/feat-remove-wrong-repo/.git"
rm -rf "$MANAGED/feat-remove-wrong-repo"
mv "$WRONG_REPO_REAL" "$MANAGED/feat-remove-wrong-repo"
pwt remove feat/remove-wrong-repo >/dev/null 2>&1

check_fails 'remove refuses the primary checkout' pwt remove "$primary_branch"
check_output 'primary-checkout refusal reaches its explicit defense-in-depth guard' \
  'refusing to remove the primary checkout' pwt remove "$primary_branch"
check 'primary-checkout removal refusal preserves the repository' test -d "$PRIMARY"
check_fails 'remove fails for a branch with no worktree' \
  pwt remove feat/never-existed
check_fails 'remove requires a branch name' pwt remove
check_fails 'remove rejects an invalid branch name' pwt remove 'bad branch'

# Parser fixtures must be clean so a missing argument guard would delete one.
launch_reset
pwt new feat/remove-arg-guard >/dev/null 2>&1
pwt new feat/remove-other-clean >/dev/null 2>&1
check_output 'remove takes exactly one branch name' \
  'remove takes exactly one branch name' \
  pwt remove feat/remove-arg-guard feat/remove-other-clean
check_output 'remove rejects an unknown flag' 'unknown option: --nope' \
  pwt remove feat/remove-arg-guard --nope
check 'argument refusals preserve the first clean worktree' \
  test -d "$MANAGED/feat-remove-arg-guard"
check 'argument refusals preserve the second clean worktree' \
  test -d "$MANAGED/feat-remove-other-clean"
pwt remove feat/remove-arg-guard >/dev/null 2>&1
pwt remove feat/remove-other-clean >/dev/null 2>&1

# A registered target replaced by a symlink must be refused without following
# it. Restore the fixture afterward so normal checked removal can clean it up.
launch_reset
pwt new feat/symlink-remove >/dev/null 2>&1
SYMLINK_REMOVE_REAL="$TMP/symlink-remove-real"
mv "$MANAGED/feat-symlink-remove" "$SYMLINK_REMOVE_REAL"
ln -s "$SYMLINK_REMOVE_REAL" "$MANAGED/feat-symlink-remove"
check_fails 'remove refuses a symlink substituted for a managed worktree' \
  pwt remove feat/symlink-remove
check_output 'symlinked removal refusal names the unsafe path shape' \
  'must not be a symlink' pwt remove feat/symlink-remove
check 'symlinked removal refusal preserves the link' \
  test -L "$MANAGED/feat-symlink-remove"
check 'symlinked removal refusal preserves the target' \
  test -d "$SYMLINK_REMOVE_REAL"
rm -f "$MANAGED/feat-symlink-remove"
mv "$SYMLINK_REMOVE_REAL" "$MANAGED/feat-symlink-remove"
pwt remove feat/symlink-remove >/dev/null 2>&1

# A nested lexical path can escape when an intermediate directory is replaced.
# Physical containment must reject that registered worktree as unmanaged.
mkdir -p "$MANAGED/remove-intermediate"
git -C "$PRIMARY" worktree add -q -b feat/remove-escape \
  "$MANAGED/remove-intermediate/worktree" origin/stable >/dev/null 2>&1
mv "$MANAGED/remove-intermediate" "$TMP/remove-outside"
ln -s "$TMP/remove-outside" "$MANAGED/remove-intermediate"
check_fails 'remove refuses a worktree physically escaped from the managed root' \
  pwt remove feat/remove-escape
check_output 'physical-escape refusal names managed-root ownership' \
  'not under the managed root' pwt remove feat/remove-escape
check 'physical-escape refusal preserves the outside worktree' \
  test -d "$TMP/remove-outside/worktree"
rm -f "$MANAGED/remove-intermediate"
mv "$TMP/remove-outside" "$MANAGED/remove-intermediate"
pwt remove feat/remove-escape >/dev/null 2>&1
rmdir "$MANAGED/remove-intermediate"

# Every Git query that decides whether deletion is safe fails closed and leaves
# both the registered worktree and its contents untouched.
launch_reset
pwt new feat/remove-git-failure >/dev/null 2>&1
check_fails 'remove exits non-zero when worktree enumeration fails' \
  pwt_git_fail worktree-list remove feat/remove-git-failure
check_output 'remove reports failed worktree enumeration' \
  'cannot list repository worktrees' \
  pwt_git_fail worktree-list remove feat/remove-git-failure
check 'enumeration failure preserves the worktree' \
  test -d "$MANAGED/feat-remove-git-failure"

check_fails 'remove exits non-zero when ignored-file inspection fails' \
  pwt_git_fail remove-ignored-list remove feat/remove-git-failure
check_output 'remove explains failed ignored-file inspection' \
  'refusing to remove without knowing what would be destroyed' \
  pwt_git_fail remove-ignored-list remove feat/remove-git-failure
check 'ignored-file inspection failure preserves the worktree' \
  test -d "$MANAGED/feat-remove-git-failure"

check_fails 'remove exits non-zero when status inspection fails' \
  pwt_git_fail remove-status remove feat/remove-git-failure
check_output 'remove explains failed status inspection' \
  'cannot determine whether' \
  pwt_git_fail remove-status remove feat/remove-git-failure
check 'status inspection failure preserves the worktree' \
  test -d "$MANAGED/feat-remove-git-failure"

check_fails 'remove exits non-zero when checked Git removal fails' \
  pwt_git_fail remove-checked remove feat/remove-git-failure
check_output 'remove reports the checked Git removal failure' \
  'Git could not remove worktree' \
  pwt_git_fail remove-checked remove feat/remove-git-failure
check 'checked Git removal failure preserves the worktree' \
  test -d "$MANAGED/feat-remove-git-failure"
pwt remove feat/remove-git-failure >/dev/null 2>&1

launch_reset
pwt new feat/remove-index-failure >/dev/null 2>&1
check_fails 'remove exits non-zero when index-flag inspection fails' \
  pwt_git_fail remove-index-list remove feat/remove-index-failure
check_output 'remove explains failed index-flag inspection' \
  'cannot inspect tracked-file index flags' \
  pwt_git_fail remove-index-list remove feat/remove-index-failure
check 'index-flag inspection failure preserves the worktree' \
  test -d "$MANAGED/feat-remove-index-failure"
if [ -d "$MANAGED/feat-remove-index-failure" ]; then
  pwt remove feat/remove-index-failure >/dev/null 2>&1
fi

# A successful exit from Git is not sufficient: verify both filesystem and
# registration state, and fail closed if post-removal enumeration itself fails.
launch_reset
pwt new feat/remove-lies-path >/dev/null 2>&1
check_fails 'remove rejects a success result that leaves the path' \
  pwt_git_fail remove-success-keeps-path remove feat/remove-lies-path
check_output 'path-verification failure names the retained path' \
  'worktree path remains after Git reported removal' \
  pwt_git_fail remove-success-keeps-path remove feat/remove-lies-path
check 'path-verification failure preserves the worktree' \
  test -d "$MANAGED/feat-remove-lies-path"
pwt remove feat/remove-lies-path >/dev/null 2>&1

launch_reset
pwt new feat/remove-lies-registration >/dev/null 2>&1
REGISTRATION_DONE="$TMP/remove-registration-done"
registration_lie_status=0
registration_lie_out=$(
  PWT_TEST_GIT_FAIL=remove-success-keeps-registration \
    PWT_TEST_REMOVE_DONE="$REGISTRATION_DONE" \
    PWT_TEST_REMOVE_TARGET="$MANAGED/feat-remove-lies-registration" \
    pwt remove feat/remove-lies-registration 2>&1
) || registration_lie_status=$?
check 'remove rejects a success result that leaves registration' \
  test "$registration_lie_status" -ne 0
check_contains 'registration-verification failure names retained state' \
  'worktree remains registered after Git reported removal' \
  "$registration_lie_out"
check 'registration-lie fixture really removes the directory' \
  test ! -e "$MANAGED/feat-remove-lies-registration"

launch_reset
pwt new feat/remove-post-list-failure >/dev/null 2>&1
POST_LIST_DONE="$TMP/remove-post-list-done"
post_list_status=0
post_list_out=$(
  PWT_TEST_GIT_FAIL=remove-success-list-fails \
    PWT_TEST_REMOVE_DONE="$POST_LIST_DONE" \
    pwt remove feat/remove-post-list-failure 2>&1
) || post_list_status=$?
check 'remove fails closed when post-removal enumeration fails' \
  test "$post_list_status" -ne 0
check_contains 'post-removal enumeration failure names verification' \
  'cannot verify its worktree registration' "$post_list_out"
check 'post-enumeration fixture really removes the directory' \
  test ! -e "$MANAGED/feat-remove-post-list-failure"

# External inspection can run filters and hooks. Re-check immediately after the
# ignored-file query so late edits and target substitution cannot reach delete.
launch_reset
pwt new feat/remove-late-dirty >/dev/null 2>&1
REMOVE_ATTEMPT="$TMP/remove-late-dirty-attempt"
remove_late_status=0
remove_late_out=$(
  PWT_TEST_GIT_FAIL=remove-dirty-after-ignored \
    PWT_TEST_REMOVE_TARGET="$MANAGED/feat-remove-late-dirty" \
    PWT_TEST_REMOVE_ATTEMPT="$REMOVE_ATTEMPT" \
    pwt remove feat/remove-late-dirty 2>&1
) || remove_late_status=$?
check 'remove refuses work created during ignored-file inspection' \
  test "$remove_late_status" -ne 0
check_contains 'late-work refusal identifies local work' \
  'uncommitted or untracked work' "$remove_late_out"
check 'late-work refusal never reaches Git removal' test ! -e "$REMOVE_ATTEMPT"
check 'late-work refusal preserves the new file' \
  test -f "$MANAGED/feat-remove-late-dirty/late.txt"

launch_reset
pwt new feat/remove-late-symlink >/dev/null 2>&1
REMOVE_SYMLINK_OUTSIDE="$TMP/remove-late-symlink-real"
REMOVE_SYMLINK_ATTEMPT="$TMP/remove-late-symlink-attempt"
remove_symlink_status=0
remove_symlink_out=$(
  PWT_TEST_GIT_FAIL=remove-symlink-after-ignored \
    PWT_TEST_REMOVE_TARGET="$MANAGED/feat-remove-late-symlink" \
    PWT_TEST_REMOVE_OUTSIDE="$REMOVE_SYMLINK_OUTSIDE" \
    PWT_TEST_REMOVE_ATTEMPT="$REMOVE_SYMLINK_ATTEMPT" \
    pwt remove feat/remove-late-symlink 2>&1
) || remove_symlink_status=$?
check 'remove refuses target substitution after ignored-file inspection' \
  test "$remove_symlink_status" -ne 0
check_contains 'late target substitution reaches the symlink ownership guard' \
  'must not be a symlink' "$remove_symlink_out"
check 'late target substitution never reaches Git removal' \
  test ! -e "$REMOVE_SYMLINK_ATTEMPT"
check 'late target substitution preserves the outside worktree' \
  test -d "$REMOVE_SYMLINK_OUTSIDE"
rm -f "$MANAGED/feat-remove-late-symlink"
mv "$REMOVE_SYMLINK_OUTSIDE" "$MANAGED/feat-remove-late-symlink"

# Status is another external inspection boundary. Re-check ignored content and
# target ownership after it before allowing Git removal to run.
launch_reset
pwt new feat/remove-late-ignored >/dev/null 2>&1
LATE_IGNORED_ATTEMPT="$TMP/remove-late-ignored-attempt"
late_ignored_status=0
late_ignored_out=$(
  PWT_TEST_GIT_FAIL=remove-ignored-after-status \
    PWT_TEST_REMOVE_TARGET="$MANAGED/feat-remove-late-ignored" \
    PWT_TEST_REMOVE_ATTEMPT="$LATE_IGNORED_ATTEMPT" \
    pwt remove feat/remove-late-ignored 2>&1
) || late_ignored_status=$?
check 'remove refuses ignored content created during status inspection' \
  test "$late_ignored_status" -ne 0
check_contains 'late ignored refusal names changed disclosure state' \
  'ignored files changed while preparing removal' "$late_ignored_out"
check 'late ignored refusal never reaches Git removal' \
  test ! -e "$LATE_IGNORED_ATTEMPT"
check 'late ignored refusal preserves the new file' \
  test -f "$MANAGED/feat-remove-late-ignored/.remove-secret"

launch_reset
pwt new feat/remove-status-symlink >/dev/null 2>&1
STATUS_SYMLINK_OUTSIDE="$TMP/remove-status-symlink-real"
STATUS_SYMLINK_ATTEMPT="$TMP/remove-status-symlink-attempt"
status_symlink_status=0
status_symlink_out=$(
  PWT_TEST_GIT_FAIL=remove-symlink-after-status \
    PWT_TEST_REMOVE_TARGET="$MANAGED/feat-remove-status-symlink" \
    PWT_TEST_REMOVE_OUTSIDE="$STATUS_SYMLINK_OUTSIDE" \
    PWT_TEST_REMOVE_ATTEMPT="$STATUS_SYMLINK_ATTEMPT" \
    pwt remove feat/remove-status-symlink 2>&1
) || status_symlink_status=$?
check 'remove refuses target substitution during status inspection' \
  test "$status_symlink_status" -ne 0
check_contains 'post-status substitution reaches the symlink guard' \
  'must not be a symlink' "$status_symlink_out"
check 'post-status substitution never reaches Git removal' \
  test ! -e "$STATUS_SYMLINK_ATTEMPT"
check 'post-status substitution preserves the outside worktree' \
  test -d "$STATUS_SYMLINK_OUTSIDE"
rm -f "$MANAGED/feat-remove-status-symlink"
mv "$STATUS_SYMLINK_OUTSIDE" "$MANAGED/feat-remove-status-symlink"

# If the named branch moves to another valid managed target during inspection,
# the saved target must not be removed under its stale identity.
launch_reset
pwt new feat/remove-registration-moved >/dev/null 2>&1
pwt new feat/remove-registration-decoy >/dev/null 2>&1
REGISTRATION_SWITCHED="$TMP/remove-registration-switched"
REGISTRATION_MOVE_ATTEMPT="$TMP/remove-registration-move-attempt"
registration_move_status=0
registration_move_out=$(
  PWT_TEST_GIT_FAIL=remove-registration-after-status \
    PWT_TEST_REMOVE_TARGET="$MANAGED/feat-remove-registration-moved" \
    PWT_TEST_REMOVE_DECOY="$MANAGED/feat-remove-registration-decoy" \
    PWT_TEST_REMOVE_BRANCH=feat/remove-registration-moved \
    PWT_TEST_REMOVE_SWITCHED="$REGISTRATION_SWITCHED" \
    PWT_TEST_REMOVE_ATTEMPT="$REGISTRATION_MOVE_ATTEMPT" \
    pwt remove feat/remove-registration-moved 2>&1
) || registration_move_status=$?
check 'remove refuses registration movement during inspection' \
  test "$registration_move_status" -ne 0
check_contains 'registration movement names the stale target' \
  'registration changed while preparing removal' "$registration_move_out"
check 'registration movement never reaches Git removal' \
  test ! -e "$REGISTRATION_MOVE_ATTEMPT"
check 'registration movement preserves the original worktree' \
  test -d "$MANAGED/feat-remove-registration-moved"
check 'registration movement preserves the decoy worktree' \
  test -d "$MANAGED/feat-remove-registration-decoy"
if [ -d "$MANAGED/feat-remove-registration-moved" ]; then
  pwt remove feat/remove-registration-moved >/dev/null 2>&1
fi
pwt remove feat/remove-registration-decoy >/dev/null 2>&1

# Non-forcing branch deletion removes a fully merged branch but preserves a
# clean branch containing local-only commits after its worktree is removed.
launch_reset
pwt new feat/unmerged-delete >/dev/null 2>&1
printf 'local history\n' >"$MANAGED/feat-unmerged-delete/local.txt"
git -C "$MANAGED/feat-unmerged-delete" add local.txt
git -C "$MANAGED/feat-unmerged-delete" commit -qm 'add local-only history'
unmerged_head=$(git -C "$MANAGED/feat-unmerged-delete" rev-parse HEAD)
UNMERGED_BRANCH_LOG="$TMP/unmerged-branch-log"
unmerged_status=0
unmerged_out=$(
  PWT_TEST_BRANCH_LOG="$UNMERGED_BRANCH_LOG" \
    pwt remove feat/unmerged-delete --delete-branch 2>&1
) || \
  unmerged_status=$?
check 'remove reports failure when safe branch deletion rejects local history' \
  test "$unmerged_status" -ne 0
check 'safe branch deletion still removes the disposable worktree' \
  test ! -e "$MANAGED/feat-unmerged-delete"
check 'safe branch deletion preserves the unmerged local branch' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/unmerged-delete
check_equals 'safe branch deletion preserves the exact local commit' \
  "$unmerged_head" "$(git -C "$PRIMARY" rev-parse feat/unmerged-delete)"
check_contains 'safe branch deletion explains its partial completion' \
  'could not safely delete branch' "$unmerged_out"
check_output 'runtime branch deletion uses the non-forcing form' \
  'branch -d feat/unmerged-delete' cat "$UNMERGED_BRANCH_LOG"

# Source-level pins complement the behavioral unmerged-history assertion. The
# exact negative spelling does not claim to recognize every possible force form.
check 'remove uses Git non-forcing branch deletion' \
  grep -qF 'branch -d "$branch"' "$PWT"
if grep -qF 'branch -D "$branch"' "$PWT"; then
  not_ok 'remove source omits the exact branch -D spelling'
else
  ok 'remove source omits the exact branch -D spelling'
fi
check 'remove status explicitly inspects dirty submodules' \
  grep -qF -- '--ignore-submodules=none' "$PWT"

# ---------------------------------------------------- dry-run-first pruning

section 'prune'

# Cover every PR state that controls candidacy. A missing state fixture is an
# explicit no-PR result from the gh boundary, not a command failure.
launch_reset
for b in prune-merged prune-open prune-none prune-closed prune-dirty; do
  pwt new "feat/$b" >/dev/null 2>&1
done
pr_state feat/prune-merged MERGED
pr_state feat/prune-open OPEN
pr_state feat/prune-closed CLOSED
pr_state feat/prune-dirty MERGED
printf 'wip\n' >"$MANAGED/feat-prune-dirty/wip.txt"

: >"$PWT_GH_LOG"
prune_dry_status=0
prune_dry=$(pwt prune 2>&1) || prune_dry_status=$?
if [ "$prune_dry_status" -eq 0 ]; then
  ok 'prune dry run succeeds'
else
  not_ok "prune dry run succeeds (got: $(printf '%s' "$prune_dry" | tr '\n' '|'))"
fi
check 'prune without --yes removes nothing' \
  test -d "$MANAGED/feat-prune-merged"
check_contains 'prune dry run lists the merged candidate' \
  'feat/prune-merged' "$prune_dry"
check_output 'prune pins merge-state queries to the resolved origin' \
  '--repo github.com/owner/project' cat "$PWT_GH_LOG"
check_equals 'prune probes GitHub authentication once per run' '1' \
  "$(grep -c '^auth status$' "$PWT_GH_LOG")"
check_contains 'prune reports an incomplete PR marker as unverified' \
  'feat/pr-reuse-partial-marker — pull request is UNVERIFIED' "$prune_dry"
check_contains 'prune reports a malformed PR marker as unverified' \
  'feat/pr-reuse-malformed-marker — pull request is UNVERIFIED' "$prune_dry"

# The candidate and left-alone reports share a branch/path shape, so scope
# assertions to the correct output block instead of grepping the whole result.
prune_candidates=$(printf '%s\n' "$prune_dry" | sed -n '/would remove/,$p')
prune_left_alone=$(printf '%s\n' "$prune_dry" | sed -n '1,/would remove/p')
for pair in \
  'prune-open:still open' \
  'prune-none:no pull request' \
  'prune-closed:closed but unmerged' \
  'prune-dirty:merged but dirty'; do
  b=${pair%%:*}
  why=${pair#*:}
  check_not_contains "prune never selects a worktree that is $why (feat/$b)" \
    "feat/$b" "$prune_candidates"
  check_contains "prune explains why it left feat/$b alone" \
    "feat/$b" "$prune_left_alone"
done

PRUNE_REMOVE_LOG="$TMP/prune-remove.log"
: >"$PRUNE_REMOVE_LOG"
PWT_TEST_REMOVE_LOG="$PRUNE_REMOVE_LOG" pwt prune --yes >/dev/null 2>&1
check 'prune --yes removes the merged clean worktree' \
  test ! -e "$MANAGED/feat-prune-merged"
check 'prune --yes leaves the still-open worktree' \
  test -d "$MANAGED/feat-prune-open"
check 'prune --yes leaves the worktree with no pull request' \
  test -d "$MANAGED/feat-prune-none"
check 'prune --yes leaves the closed-but-unmerged worktree' \
  test -d "$MANAGED/feat-prune-closed"
check 'prune --yes leaves the merged-but-dirty worktree' \
  test -d "$MANAGED/feat-prune-dirty"
check 'prune --yes preserves a worktree with incomplete PR markers' \
  test -d "$MANAGED/feat-pr-reuse-partial-marker"
check 'prune --yes preserves a worktree with malformed PR markers' \
  test -d "$MANAGED/feat-pr-reuse-malformed-marker"
check 'prune keeps the branch of every removed worktree' \
  git -C "$PRIMARY" show-ref --verify --quiet refs/heads/feat/prune-merged
check_output 'applied pruning removes the exact dry-run candidate path' \
  "worktree remove $MANAGED/feat-prune-merged" cat "$PRUNE_REMOVE_LOG"

# A branch name is not a PR identity. An old merged PR cannot authorize
# deletion after the local branch advances, and a same-named fork PR cannot
# authorize deletion of an ordinary same-repository worktree.
launch_reset
pwt new feat/prune-advanced-after-merge >/dev/null 2>&1
pr_state feat/prune-advanced-after-merge MERGED
printf 'advanced locally\n' \
  >"$MANAGED/feat-prune-advanced-after-merge/advanced.txt"
git -C "$MANAGED/feat-prune-advanced-after-merge" add advanced.txt
git -C "$MANAGED/feat-prune-advanced-after-merge" \
  commit -qm 'advance after merged pull request'
prune_advanced=$(pwt prune 2>&1)
prune_advanced_candidates=$(printf '%s\n' "$prune_advanced" | \
  sed -n '/would remove/,$p')
check_not_contains 'prune does not advertise a branch advanced after its merge' \
  'feat/prune-advanced-after-merge' "$prune_advanced_candidates"
check_contains 'prune reports the advanced branch as unverified' \
  'feat/prune-advanced-after-merge — pull request is UNVERIFIED' \
  "$prune_advanced"
check 'prune --yes preserves a branch advanced after its merge' \
  pwt prune --yes
check 'the advanced clean worktree survives applied pruning' \
  test -d "$MANAGED/feat-prune-advanced-after-merge"

launch_reset
pwt new feat/prune-same-name-fork >/dev/null 2>&1
pr_state feat/prune-same-name-fork MERGED '' true fork-owner fork-project
prune_fork_name=$(pwt prune 2>&1)
prune_fork_candidates=$(printf '%s\n' "$prune_fork_name" | \
  sed -n '/would remove/,$p')
check_not_contains 'prune does not advertise a same-named fork PR' \
  'feat/prune-same-name-fork' "$prune_fork_candidates"
check 'prune --yes preserves the ordinary branch matched by a fork PR' \
  pwt prune --yes
check 'the worktree matched only by a same-named fork survives pruning' \
  test -d "$MANAGED/feat-prune-same-name-fork"

# A fork worktree made by `pwt pr` has an exact canonical-URL marker, so its
# merged PR can be verified without weakening the ordinary branch-name lookup.
pr_meta 901 feat/prune-recorded-fork true fork-owner fork-project
pwt pr 901 >/dev/null 2>&1
pr_state feat/prune-recorded-fork MERGED
: >"$PWT_GH_LOG"
prune_recorded_fork=$(pwt prune 2>&1)
prune_recorded_candidates=$(printf '%s\n' "$prune_recorded_fork" | \
  sed -n '/would remove/,$p')
check_contains 'prune accepts a merged fork worktree with an exact PR marker' \
  'feat/prune-recorded-fork' "$prune_recorded_candidates"
check_output 'prune verifies a recorded fork by its canonical PR URL' \
  'pr view https://github.com/owner/project/pull/901' cat "$PWT_GH_LOG"
pwt prune --yes >/dev/null 2>&1
check 'prune removes the exactly verified merged fork worktree' \
  test ! -e "$MANAGED/feat-prune-recorded-fork"
check 'prune preserves the branch of a removed fork worktree' \
  git -C "$PRIMARY" show-ref --verify --quiet \
    refs/heads/feat/prune-recorded-fork

rm -f "$PWT_GH_STATES/feat-prune-advanced-after-merge" \
  "$PWT_GH_STATES/feat-prune-same-name-fork" \
  "$PWT_GH_STATES/feat-prune-recorded-fork"
pwt remove feat/prune-advanced-after-merge >/dev/null 2>&1
pwt remove feat/prune-same-name-fork >/dev/null 2>&1

# A worktree containing the caller is reported but never removed.
launch_reset
pwt new feat/prune-self >/dev/null 2>&1
pr_state feat/prune-self MERGED
prune_self_out=$(pwt_in "$MANAGED/feat-prune-self" prune --yes 2>&1)
check 'prune leaves the worktree containing the caller' \
  test -d "$MANAGED/feat-prune-self"
check_contains 'prune explains the caller-current skip' \
  'you are standing in it' "$prune_self_out"
check 'prune removes that worktree once the caller is elsewhere' pwt prune --yes
check 'the former caller-current worktree is gone afterwards' \
  test ! -e "$MANAGED/feat-prune-self"

# Git's lock is an explicit keep signal. The dry run must report it accurately
# instead of promising a removal that the later Git command will refuse.
launch_reset
pwt new feat/prune-locked >/dev/null 2>&1
pr_state feat/prune-locked MERGED
git -C "$PRIMARY" worktree lock --reason 'keep for another process' \
  "$MANAGED/feat-prune-locked"
prune_locked=$(pwt prune 2>&1)
prune_locked_candidates=$(printf '%s\n' "$prune_locked" | \
  sed -n '/would remove/,$p')
check_not_contains 'prune does not advertise a locked worktree as removable' \
  'feat/prune-locked' "$prune_locked_candidates"
check_contains 'prune reports a locked worktree as left alone' \
  'feat/prune-locked — worktree is locked' "$prune_locked"
check 'prune --yes succeeds while leaving a locked worktree alone' \
  pwt prune --yes
check 'applied pruning preserves the locked worktree' \
  test -d "$MANAGED/feat-prune-locked"
git -C "$PRIMARY" worktree unlock "$MANAGED/feat-prune-locked"
rm -f "$PWT_GH_STATES/feat-prune-locked"
pwt remove feat/prune-locked >/dev/null 2>&1

# GitHub availability is checked before any candidate can be removed.
launch_reset
pwt new feat/prune-auth >/dev/null 2>&1
pr_state feat/prune-auth MERGED
touch "$PWT_GH_UNAVAILABLE"
check_fails 'prune fails when gh is unauthenticated' pwt prune
check_output 'prune explains the authentication failure' \
  'prune needs gh' pwt prune
check_fails 'prune --yes fails when gh is unauthenticated' pwt prune --yes
check 'prune removes nothing while gh is unauthenticated' \
  test -d "$MANAGED/feat-prune-auth"
rm -f "$PWT_GH_UNAVAILABLE"

NOGH="$TMP/nogh"
mkdir -p "$NOGH"
for binary in bash git sed tr head grep; do
  ln -s "$(command -v "$binary")" "$NOGH/$binary"
done
pwt_without_gh() { pwt_in_with_path "$PRIMARY" "$NOGH" "$@"; }
missing_gh_status=0
missing_gh_out=$(pwt_without_gh prune 2>&1) || missing_gh_status=$?
check 'prune fails when gh is not on PATH' test "$missing_gh_status" -ne 0
if printf '%s\n' "$missing_gh_out" | grep -qF 'not on PATH'; then
  ok 'prune distinguishes missing gh from failed authentication'
else
  not_ok "prune distinguishes missing gh from failed authentication (got: $missing_gh_out)"
fi

# Parser tests use a clean merged fixture, so they fail only if their intended
# guards run rather than because a later dirty-state check happens to reject.
check_output 'prune rejects positional arguments' \
  'prune takes no positional arguments' pwt prune something
check_output 'prune rejects unknown flags' \
  'unknown option: --force' pwt prune --force
check_equals 'prune --help prints the shared usage' \
  "$(pwt help)" "$(pwt prune --help)"

# Keep the remaining checks focused and fast by clearing the baseline fixtures
# that no longer participate in pruning behavior.
rm -f "$MANAGED/feat-prune-dirty/wip.txt"
for branch in \
  feat/prune-open feat/prune-none feat/prune-closed \
  feat/prune-dirty feat/prune-auth; do
  pwt remove "$branch" >/dev/null 2>&1
done

# A per-branch API failure is not a PR state. Classification finishes before
# removal begins, so even an earlier merged candidate survives the failed run.
launch_reset
pwt new feat/prune-a-before-api-failure >/dev/null 2>&1
pwt new feat/prune-z-api-failure >/dev/null 2>&1
pr_state feat/prune-a-before-api-failure MERGED
pr_state_failure feat/prune-z-api-failure
PRUNE_API_REMOVE_LOG="$TMP/prune-api-remove.log"
: >"$PRUNE_API_REMOVE_LOG"
: >"$PWT_GH_LOG"
prune_api_status=0
prune_api_out=$(
  PWT_TEST_REMOVE_LOG="$PRUNE_API_REMOVE_LOG" pwt prune --yes 2>&1
) || prune_api_status=$?
check 'prune fails when one branch state query fails' \
  test "$prune_api_status" -ne 0
check_contains 'prune names the branch whose state is unavailable' \
  'cannot determine pull request state for feat/prune-z-api-failure' \
  "$prune_api_out"
check 'a branch-state failure preserves an earlier merged candidate' \
  test -d "$MANAGED/feat-prune-a-before-api-failure"
check 'a branch-state failure preserves its own worktree' \
  test -d "$MANAGED/feat-prune-z-api-failure"
check_equals 'a branch-state failure starts no removals' '' \
  "$(sed -n '1p' "$PRUNE_API_REMOVE_LOG")"
prune_a_query_line=$(grep -n -- '--head feat/prune-a-before-api-failure' \
  "$PWT_GH_LOG" | head -1 | cut -d: -f1)
prune_z_query_line=$(grep -n -- '--head feat/prune-z-api-failure' \
  "$PWT_GH_LOG" | head -1 | cut -d: -f1)
check 'the merged candidate is classified before the simulated API failure' \
  test "$prune_a_query_line" -lt "$prune_z_query_line"
rm -f "$PWT_GH_FAILURES/feat-prune-z-api-failure" \
  "$PWT_GH_STATES/feat-prune-a-before-api-failure"
pwt remove feat/prune-a-before-api-failure >/dev/null 2>&1
pwt remove feat/prune-z-api-failure >/dev/null 2>&1

# Git enumeration and status failures are safety failures, never empty or clean
# states. Each leaves the intended target untouched.
launch_reset
pwt new feat/prune-git-failure >/dev/null 2>&1
pr_state feat/prune-git-failure MERGED
check_fails 'prune fails closed when Git cannot enumerate worktrees' \
  pwt_git_fail worktree-list prune --yes
check_output 'prune reports failed worktree enumeration' \
  'cannot list repository worktrees; refusing to prune' \
  pwt_git_fail worktree-list prune --yes
check 'worktree enumeration failure preserves the merged candidate' \
  test -d "$MANAGED/feat-prune-git-failure"

PRUNE_STATUS_ATTEMPT="$TMP/prune-status-attempt"
prune_status=0
prune_status_out=$(
  export PWT_TEST_GIT_FAIL=prune-status
  export PWT_TEST_PRUNE_TARGET="$MANAGED/feat-prune-git-failure"
  export PWT_TEST_REMOVE_ATTEMPT="$PRUNE_STATUS_ATTEMPT"
  pwt prune --yes 2>&1
) || prune_status=$?
check 'prune fails closed when candidate status inspection fails' \
  test "$prune_status" -ne 0
check_contains 'prune reports failed candidate status inspection' \
  'refusing to prune' "$prune_status_out"
check 'failed candidate status inspection never reaches removal' \
  test ! -e "$PRUNE_STATUS_ATTEMPT"
check 'failed candidate status inspection preserves the worktree' \
  test -d "$MANAGED/feat-prune-git-failure"
check_fails 'prune fails closed when index-flag inspection fails' \
  pwt_git_fail remove-index-list prune --yes
check_output 'prune reports failed index-flag inspection' \
  'cannot inspect tracked-file index flags' \
  pwt_git_fail remove-index-list prune --yes
check 'failed index-flag inspection preserves the merged candidate' \
  test -d "$MANAGED/feat-prune-git-failure"
rm -f "$PWT_GH_STATES/feat-prune-git-failure"
pwt remove feat/prune-git-failure >/dev/null 2>&1

# Unexpected API output is not a new state that may silently alter deletion.
launch_reset
pwt new feat/prune-invalid-state >/dev/null 2>&1
pr_state feat/prune-invalid-state UNKNOWN
check_fails 'prune rejects an unexpected pull request state' pwt prune --yes
check_output 'unexpected PR state fails with the branch diagnostic' \
  'cannot determine pull request state for feat/prune-invalid-state' \
  pwt prune --yes
check 'unexpected PR state preserves the worktree' \
  test -d "$MANAGED/feat-prune-invalid-state"
rm -f "$PWT_GH_STATES/feat-prune-invalid-state"
pwt remove feat/prune-invalid-state >/dev/null 2>&1

# Bash 3.2 locale collation can make non-ASCII numerals match [0-9]. Both API
# metadata and stored PR URLs must retain an ASCII-only pull-request identity.
launch_reset
pwt new feat/prune-nonascii-api-number >/dev/null 2>&1
pr_state feat/prune-nonascii-api-number MERGED '' false owner project \
  'https://github.com/owner/project/pull/ↅ'
prune_nonascii_api_status=0
prune_nonascii_api_out=$(pwt_utf8 prune --yes 2>&1) || \
  prune_nonascii_api_status=$?
check 'prune rejects a non-ASCII PR number from API metadata' \
  test "$prune_nonascii_api_status" -ne 0
check_contains 'non-ASCII API metadata fails at PR-state validation' \
  'cannot determine pull request state for feat/prune-nonascii-api-number' \
  "$prune_nonascii_api_out"
check 'invalid non-ASCII API metadata never authorizes removal' \
  test -d "$MANAGED/feat-prune-nonascii-api-number"
rm -f "$PWT_GH_STATES/feat-prune-nonascii-api-number"
pwt remove feat/prune-nonascii-api-number >/dev/null 2>&1

launch_reset
pwt new feat/prune-nonascii-marker-number >/dev/null 2>&1
prune_nonascii_marker_head=$(git -C \
  "$MANAGED/feat-prune-nonascii-marker-number" rev-parse HEAD)
git -C "$PRIMARY" config \
  branch.feat/prune-nonascii-marker-number.worktree-pr-url \
  'https://github.com/owner/project/pull/ↅ'
git -C "$PRIMARY" config \
  branch.feat/prune-nonascii-marker-number.worktree-pr-head \
  "$prune_nonascii_marker_head"
prune_nonascii_marker=$(pwt_utf8 prune 2>&1)
check_contains 'prune treats a non-ASCII recorded PR number as unverified' \
  'feat/prune-nonascii-marker-number — pull request is UNVERIFIED' \
  "$prune_nonascii_marker"
check 'prune preserves a worktree with a non-ASCII recorded PR number' \
  pwt_utf8 prune --yes
check 'the invalid recorded PR identity survives applied pruning' \
  test -d "$MANAGED/feat-prune-nonascii-marker-number"
git -C "$PRIMARY" config --unset-all \
  branch.feat/prune-nonascii-marker-number.worktree-pr-url
git -C "$PRIMARY" config --unset-all \
  branch.feat/prune-nonascii-marker-number.worktree-pr-head
pwt remove feat/prune-nonascii-marker-number >/dev/null 2>&1

# Every unsafe shape is made merged-and-clean alongside a valid control. This
# makes the containment guards, rather than PR-state filtering, decide survival.
launch_reset
pwt new feat/prune-containment-control >/dev/null 2>&1
pr_state feat/prune-containment-control MERGED
pr_state feat/stray MERGED
primary_branch_now=$(git -C "$PRIMARY" symbolic-ref --short HEAD)
pr_state "$primary_branch_now" MERGED

git -C "$PRIMARY" worktree add -q -b feat/prune-symlink \
  "$MANAGED/feat-prune-symlink" origin/stable 2>/dev/null
PRUNE_SYMLINK_REAL="$MANAGED/feat-prune-symlink-real"
mv "$MANAGED/feat-prune-symlink" "$PRUNE_SYMLINK_REAL"
ln -s "$PRUNE_SYMLINK_REAL" "$MANAGED/feat-prune-symlink"
pr_state feat/prune-symlink MERGED

mkdir -p "$MANAGED/prune-intermediate"
git -C "$PRIMARY" worktree add -q -b feat/prune-escape \
  "$MANAGED/prune-intermediate/feat-prune-escape" origin/stable 2>/dev/null
mv "$MANAGED/prune-intermediate" "$TMP/prune-outside"
ln -s "$TMP/prune-outside" "$MANAGED/prune-intermediate"
pr_state feat/prune-escape MERGED

prune_containment_dry=$(pwt prune 2>&1)
prune_containment_candidates=$(printf '%s\n' "$prune_containment_dry" | \
  sed -n '/would remove/,$p')
check_contains 'prune dry run still lists the valid containment control' \
  'feat/prune-containment-control' "$prune_containment_candidates"
check_not_contains 'prune dry run never advertises a physical escape' \
  'feat/prune-escape' "$prune_containment_candidates"
check_not_contains 'prune dry run never advertises a symlinked registration' \
  'feat/prune-symlink' "$prune_containment_candidates"
check_not_contains 'prune dry run never advertises an unmanaged registration' \
  'feat/stray' "$prune_containment_candidates"

pwt prune --yes >/dev/null 2>&1
check 'prune removes a valid control beside unsafe registrations' \
  test ! -e "$MANAGED/feat-prune-containment-control"
check 'prune never removes an unmanaged merged worktree' test -d "$UNMANAGED"
check 'prune never removes the primary checkout' test -d "$PRIMARY"
check 'prune never follows a substituted worktree symlink' \
  test -L "$MANAGED/feat-prune-symlink"
check 'the substituted symlink target also survives pruning' \
  test -d "$PRUNE_SYMLINK_REAL"
check 'prune never removes a physically escaped worktree' \
  test -d "$TMP/prune-outside/feat-prune-escape"
check 'prune keeps an explicit primary-checkout exclusion' \
  grep -qF 'if [[ -n $path && -n $branch && $path != "$primary" && ! -L $path ]]; then' \
  "$PWT"

rm -f "$MANAGED/feat-prune-symlink"
mv "$PRUNE_SYMLINK_REAL" "$MANAGED/feat-prune-symlink"
pwt remove feat/prune-symlink >/dev/null 2>&1
git -C "$PRIMARY" worktree remove --force \
  "$TMP/prune-outside/feat-prune-escape" >/dev/null 2>&1
rm -f "$MANAGED/prune-intermediate"
rm -rf "$TMP/prune-outside"
rm -f "$PWT_GH_STATES/feat-prune-containment-control" \
  "$PWT_GH_STATES/feat-stray" \
  "$PWT_GH_STATES/feat-prune-symlink" \
  "$PWT_GH_STATES/feat-prune-escape" \
  "$PWT_GH_STATES/$(printf '%s' "$primary_branch_now" | tr '/' '-')"

# State lookup is an external boundary. A late edit must be caught by the
# shared removal guard before Git receives a destructive command.
launch_reset
pwt new feat/prune-late-dirty >/dev/null 2>&1
pr_state feat/prune-late-dirty MERGED
PRUNE_LATE_DIRTY_ATTEMPT="$TMP/prune-late-dirty-attempt"
prune_late_dirty_status=0
prune_late_dirty_out=$(
  export PWT_TEST_PRUNE_MUTATION=dirty-after-state
  export PWT_TEST_PRUNE_BRANCH=feat/prune-late-dirty
  export PWT_TEST_PRUNE_TARGET="$MANAGED/feat-prune-late-dirty"
  export PWT_TEST_REMOVE_ATTEMPT="$PRUNE_LATE_DIRTY_ATTEMPT"
  pwt prune --yes 2>&1
) || prune_late_dirty_status=$?
check 'prune refuses work created after candidate classification' \
  test "$prune_late_dirty_status" -ne 0
check_contains 'late-work refusal identifies local work' \
  'uncommitted or untracked work' "$prune_late_dirty_out"
check 'late-work refusal never reaches Git removal' \
  test ! -e "$PRUNE_LATE_DIRTY_ATTEMPT"
check 'late-work refusal preserves the new file' \
  test -f "$MANAGED/feat-prune-late-dirty/late.txt"
rm -f "$MANAGED/feat-prune-late-dirty/late.txt" \
  "$PWT_GH_STATES/feat-prune-late-dirty"
pwt remove feat/prune-late-dirty >/dev/null 2>&1

# A post-classification path substitution must be rejected by the same physical
# ownership checks used by explicit removal.
launch_reset
pwt new feat/prune-late-symlink >/dev/null 2>&1
pr_state feat/prune-late-symlink MERGED
PRUNE_SYMLINK_OUTSIDE="$TMP/prune-late-symlink-real"
PRUNE_SYMLINK_ATTEMPT="$TMP/prune-late-symlink-attempt"
prune_symlink_status=0
prune_symlink_out=$(
  export PWT_TEST_PRUNE_MUTATION=symlink-after-state
  export PWT_TEST_PRUNE_BRANCH=feat/prune-late-symlink
  export PWT_TEST_PRUNE_TARGET="$MANAGED/feat-prune-late-symlink"
  export PWT_TEST_PRUNE_OUTSIDE="$PRUNE_SYMLINK_OUTSIDE"
  export PWT_TEST_REMOVE_ATTEMPT="$PRUNE_SYMLINK_ATTEMPT"
  pwt prune --yes 2>&1
) || prune_symlink_status=$?
check 'prune refuses a symlink substituted after classification' \
  test "$prune_symlink_status" -ne 0
check_contains 'late symlink refusal names the unsafe path shape' \
  'must not be a symlink' "$prune_symlink_out"
check 'late symlink refusal never reaches Git removal' \
  test ! -e "$PRUNE_SYMLINK_ATTEMPT"
check 'late symlink refusal preserves the outside worktree' \
  test -d "$PRUNE_SYMLINK_OUTSIDE"
rm -f "$MANAGED/feat-prune-late-symlink"
mv "$PRUNE_SYMLINK_OUTSIDE" "$MANAGED/feat-prune-late-symlink"
rm -f "$PWT_GH_STATES/feat-prune-late-symlink"
pwt remove feat/prune-late-symlink >/dev/null 2>&1

# The apply phase is tied to both the branch and the physical path printed by
# the dry-run classifier. Moving a valid registration invalidates that identity.
launch_reset
pwt new feat/prune-moved >/dev/null 2>&1
pr_state feat/prune-moved MERGED
PRUNE_MOVED="$MANAGED/feat-prune-moved-destination"
PRUNE_MOVED_ATTEMPT="$TMP/prune-moved-attempt"
prune_moved_status=0
prune_moved_out=$(
  export PWT_TEST_PRUNE_MUTATION=move-after-state
  export PWT_TEST_PRUNE_BRANCH=feat/prune-moved
  export PWT_TEST_PRUNE_TARGET="$MANAGED/feat-prune-moved"
  export PWT_TEST_PRUNE_MOVED="$PRUNE_MOVED"
  export PWT_TEST_PRUNE_PRIMARY="$PRIMARY"
  export PWT_TEST_REMOVE_ATTEMPT="$PRUNE_MOVED_ATTEMPT"
  pwt prune --yes 2>&1
) || prune_moved_status=$?
check 'prune refuses a candidate moved after classification' \
  test "$prune_moved_status" -ne 0
check_contains 'moved-candidate refusal names changed classification' \
  'changed after prune classification' "$prune_moved_out"
check 'moved-candidate refusal never reaches Git removal' \
  test ! -e "$PRUNE_MOVED_ATTEMPT"
check 'moved-candidate refusal preserves the registered worktree' \
  test -d "$PRUNE_MOVED"
rm -f "$PWT_GH_STATES/feat-prune-moved"
pwt remove feat/prune-moved >/dev/null 2>&1

# Even a clean commit created after GitHub classification invalidates the
# candidate. This specifically pins the stored-OID guard rather than dirtiness.
launch_reset
pwt new feat/prune-head-changed >/dev/null 2>&1
pr_state feat/prune-head-changed MERGED
PRUNE_HEAD_ATTEMPT="$TMP/prune-head-attempt"
prune_head_status=0
prune_head_out=$(
  export PWT_TEST_PRUNE_MUTATION=head-after-state
  export PWT_TEST_PRUNE_BRANCH=feat/prune-head-changed
  export PWT_TEST_PRUNE_TARGET="$MANAGED/feat-prune-head-changed"
  export PWT_TEST_REMOVE_ATTEMPT="$PRUNE_HEAD_ATTEMPT"
  pwt prune --yes 2>&1
) || prune_head_status=$?
check 'prune refuses a clean HEAD changed after classification' \
  test "$prune_head_status" -ne 0
check_contains 'changed-HEAD refusal names the invalidated classification' \
  'worktree HEAD changed after prune classification' "$prune_head_out"
check 'changed-HEAD refusal never reaches Git removal' \
  test ! -e "$PRUNE_HEAD_ATTEMPT"
check 'the newly committed HEAD survives pruning' \
  test -f "$MANAGED/feat-prune-head-changed/prune-head-change.txt"
rm -f "$PWT_GH_STATES/feat-prune-head-changed"
pwt remove feat/prune-head-changed >/dev/null 2>&1

# The first expected-HEAD check is not enough: status/ignored-file inspection
# is another process boundary before removal. Commit after status so only the
# final expected-HEAD comparison can stop Git.
launch_reset
pwt new feat/prune-head-after-status >/dev/null 2>&1
pr_state feat/prune-head-after-status MERGED
PRUNE_LATE_HEAD_ATTEMPT="$TMP/prune-late-head-attempt"
PRUNE_LATE_HEAD_STATUS_COUNT="$TMP/prune-late-head-status-count"
prune_late_head_status=0
prune_late_head_out=$(
  export PWT_TEST_GIT_FAIL=prune-head-after-status
  export PWT_TEST_PRUNE_TARGET="$MANAGED/feat-prune-head-after-status"
  export PWT_TEST_REMOVE_ATTEMPT="$PRUNE_LATE_HEAD_ATTEMPT"
  export PWT_TEST_PRUNE_STATUS_COUNT="$PRUNE_LATE_HEAD_STATUS_COUNT"
  pwt prune --yes 2>&1
) || prune_late_head_status=$?
check 'prune refuses a clean HEAD changed during removal inspection' \
  test "$prune_late_head_status" -ne 0
check_contains 'late HEAD refusal names the final removal boundary' \
  'worktree HEAD changed while preparing removal' "$prune_late_head_out"
check_equals 'late HEAD fixture mutates only during removal inspection' '2' \
  "$(sed -n 1p "$PRUNE_LATE_HEAD_STATUS_COUNT" 2>/dev/null)"
check 'late HEAD refusal never reaches Git removal' \
  test ! -e "$PRUNE_LATE_HEAD_ATTEMPT"
check 'the commit created after status survives pruning' \
  test -f "$MANAGED/feat-prune-head-after-status/prune-late-head.txt"
rm -f "$PWT_GH_STATES/feat-prune-head-after-status"
pwt remove feat/prune-head-after-status >/dev/null 2>&1

# Git status hides assume-unchanged edits. An accurate dry run must classify
# that local state as skipped instead of advertising a removal that will fail.
launch_reset
pwt new feat/prune-hidden >/dev/null 2>&1
printf 'hidden prune edit\n' >>"$MANAGED/feat-prune-hidden/README.md"
git -C "$MANAGED/feat-prune-hidden" update-index --assume-unchanged README.md
pr_state feat/prune-hidden MERGED
prune_hidden=$(pwt prune 2>&1)
prune_hidden_candidates=$(printf '%s\n' "$prune_hidden" | sed -n '/would remove/,$p')
prune_hidden_left=$(printf '%s\n' "$prune_hidden" | sed -n '1,/nothing to prune/p')
check_not_contains 'prune does not advertise hidden local state as removable' \
  'feat/prune-hidden' "$prune_hidden_candidates"
check_contains 'prune reports hidden local state as left alone' \
  'feat/prune-hidden' "$prune_hidden_left"
check 'prune --yes preserves hidden local state' \
  pwt prune --yes
check 'hidden local edits survive applied pruning' \
  grep -qF 'hidden prune edit' "$MANAGED/feat-prune-hidden/README.md"
git -C "$MANAGED/feat-prune-hidden" update-index --no-assume-unchanged README.md
git -C "$MANAGED/feat-prune-hidden" checkout -- README.md
rm -f "$PWT_GH_STATES/feat-prune-hidden"
pwt remove feat/prune-hidden >/dev/null 2>&1

# -------------------------------------------------------------------- install

section 'install'

LOCAL_BIN="$HOME/.local/bin"
COMP_DIR="$HOME/.local/share/bash-completion/completions"
COMP_LINK="$COMP_DIR/pwt"
EXPECTED_COMPLETION=${PWT_COMPLETION_UNDER_TEST:-"$REPO_ROOT/pi/scripts/pwt-completion.bash"}

reset_install() {
  rm -rf "$LOCAL_BIN" "$HOME/.local/share/bash-completion"
}

# Install is repository-independent and creates both autoloadable symlinks.
reset_install
export PATH="$LOCAL_BIN:$PATH"
check 'install succeeds outside a Git repository' pwt_in "$OUTSIDE" install
check 'install creates the ~/.local/bin directory' test -d "$LOCAL_BIN"
check 'install creates a symlink at ~/.local/bin/pwt' test -L "$LOCAL_BIN/pwt"
check_equals 'the installed pwt symlink points at the repository script' \
  "$PWT" "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"
check 'install creates the per-user bash-completion directory' test -d "$COMP_DIR"
check 'install creates an autoloadable pwt completion symlink' test -L "$COMP_LINK"
check_equals 'the installed completion points at the repository script' \
  "$EXPECTED_COMPLETION" "$(readlink "$COMP_LINK" 2>/dev/null)"

# Both links are idempotent.
check 'install is idempotent when both symlinks are current' pwt_in "$OUTSIDE" install
check_output 'repeat install reports the existing links' \
  'already installed' pwt_in "$OUTSIDE" install

# Stale links are owned by this installer and may be safely repointed.
rm -f "$LOCAL_BIN/pwt" "$COMP_LINK"
ln -s "$TMP/stale-pwt" "$LOCAL_BIN/pwt"
ln -s "$TMP/stale-pwt-completion" "$COMP_LINK"
check 'install repoints stale binary and completion symlinks' \
  pwt_in "$OUTSIDE" install
check_equals 'the stale binary symlink is repointed to the repository script' \
  "$PWT" "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"
check_equals 'the stale completion symlink is repointed to the repository script' \
  "$EXPECTED_COMPLETION" "$(readlink "$COMP_LINK" 2>/dev/null)"

# A stale-link update must not delete a regular file that appears after the
# initial lstat. The readlink shim makes that race deterministic.
reset_install
mkdir -p "$LOCAL_BIN"
ln -s "$TMP/stale-pwt" "$LOCAL_BIN/pwt"
INSTALL_RACE_BIN="$TMP/install-race-bin"
INSTALL_RACE_MARKER="$TMP/install-race-marker"
mkdir -p "$INSTALL_RACE_BIN"
PWT_TEST_REAL_READLINK=$(command -v readlink)
export PWT_TEST_REAL_READLINK INSTALL_RACE_MARKER
export PWT_TEST_INSTALL_RACE_TARGET="$LOCAL_BIN/pwt"
cat >"$INSTALL_RACE_BIN/readlink" <<'STUB'
#!/bin/bash
if [ "$1" = "$PWT_TEST_INSTALL_RACE_TARGET" ] && [ ! -e "$INSTALL_RACE_MARKER" ]; then
  original=$($PWT_TEST_REAL_READLINK "$1") || exit
  /bin/rm -f "$1"
  printf 'raced-in user file\n' >"$1"
  : >"$INSTALL_RACE_MARKER"
  printf '%s\n' "$original"
  exit 0
fi
exec "$PWT_TEST_REAL_READLINK" "$@"
STUB
chmod +x "$INSTALL_RACE_BIN/readlink"
install_race_status=0
install_race_out=$(cd "$OUTSIDE" && \
  PATH="$INSTALL_RACE_BIN:/usr/bin:/bin" "$PWT" install 2>&1) || \
  install_race_status=$?
check 'install refuses a target changed during stale-link replacement' \
  test "$install_race_status" -ne 0
check_contains 'install reports the concurrent target change' \
  'changed during preflight' "$install_race_out"
check 'install preserves a raced-in user file at the original target' \
  grep -qF 'raced-in user file' "$LOCAL_BIN/pwt"
check 'install does not move raced-in data after preflight detects it' \
  test -z "$(find "$LOCAL_BIN" -name '*.pwt-install.*' -print -quit)"

# A real file is user-owned. The explicit diagnostic pins the no-clobber guard;
# relying on ln to fail would preserve the file for the wrong reason.
reset_install
mkdir -p "$LOCAL_BIN"
printf 'user-owned binary\n' >"$LOCAL_BIN/pwt"
check_fails 'install refuses to clobber a non-symlink pwt file' \
  pwt_in "$OUTSIDE" install
check_output 'binary collision names the non-symlink refusal' \
  'exists and is not a symlink' pwt_in "$OUTSIDE" install
check 'the user-owned pwt file survives a refused install' \
  grep -qF 'user-owned binary' "$LOCAL_BIN/pwt"

reset_install
mkdir -p "$COMP_DIR"
printf 'user-owned completion\n' >"$COMP_LINK"
completion_collision_status=0
completion_collision_out=$(pwt_in "$OUTSIDE" install 2>&1) ||
  completion_collision_status=$?
check 'install refuses to clobber a non-symlink completion file' \
  test "$completion_collision_status" -ne 0
check_contains 'completion collision names the non-symlink refusal' \
  'exists and is not a symlink' "$completion_collision_out"
check_not_contains 'completion collision refuses before installing the binary' \
  "installed $LOCAL_BIN/pwt" "$completion_collision_out"
check 'the user-owned completion survives a refused install' \
  grep -qF 'user-owned completion' "$COMP_LINK"
check 'completion preflight failure creates no partial binary link' \
  test ! -L "$LOCAL_BIN/pwt"

# Preflight every destination before changing either one. In particular, a
# completion collision must not repoint a stale but otherwise valid binary link.
reset_install
mkdir -p "$LOCAL_BIN" "$COMP_DIR"
ln -s "$TMP/stale-before-completion-collision" "$LOCAL_BIN/pwt"
printf 'user-owned completion\n' >"$COMP_LINK"
stale_collision_status=0
stale_collision_out=$(pwt_in "$OUTSIDE" install 2>&1) ||
  stale_collision_status=$?
check 'completion collision refuses before repointing a stale binary' \
  test "$stale_collision_status" -ne 0
check_not_contains 'completion collision reports no transient binary repoint' \
  "repointed $LOCAL_BIN/pwt" "$stale_collision_out"
check_equals 'completion collision preserves the stale binary target' \
  "$TMP/stale-before-completion-collision" \
  "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"

# A destination can still fail after preflight. Force only the completion ln to
# fail and require rollback of a newly created or repointed binary symlink.
INSTALL_COMPLETION_FAIL_BIN="$TMP/install-completion-fail-bin"
mkdir -p "$INSTALL_COMPLETION_FAIL_BIN"
PWT_TEST_REAL_LN=$(command -v ln)
export PWT_TEST_REAL_LN PWT_TEST_INSTALL_COMPLETION_TARGET="$COMP_LINK"
cat >"$INSTALL_COMPLETION_FAIL_BIN/ln" <<'STUB'
#!/bin/bash
last=''
for argument in "$@"; do
  last=$argument
done
if [ "$last" = "$PWT_TEST_INSTALL_COMPLETION_TARGET" ]; then
  exit 76
fi
exec "$PWT_TEST_REAL_LN" "$@"
STUB
chmod +x "$INSTALL_COMPLETION_FAIL_BIN/ln"

reset_install
completion_link_status=0
completion_link_out=$(cd "$OUTSIDE" && \
  PATH="$INSTALL_COMPLETION_FAIL_BIN:$PATH" "$PWT" install 2>&1) || \
  completion_link_status=$?
check 'late completion-link failure exits non-zero' \
  test "$completion_link_status" -ne 0
check_contains 'late completion-link failure reports the failed link' \
  'cannot create symlink' "$completion_link_out"
check 'late completion-link failure rolls back a new binary link' \
  test ! -L "$LOCAL_BIN/pwt"

reset_install
mkdir -p "$LOCAL_BIN"
ln -s "$TMP/stale-before-late-failure" "$LOCAL_BIN/pwt"
completion_repoint_status=0
completion_repoint_out=$(cd "$OUTSIDE" && \
  PATH="$INSTALL_COMPLETION_FAIL_BIN:$PATH" "$PWT" install 2>&1) || \
  completion_repoint_status=$?
check 'late completion failure after binary repoint exits non-zero' \
  test "$completion_repoint_status" -ne 0
check_equals 'late completion failure restores the previous binary target' \
  "$TMP/stale-before-late-failure" \
  "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"

reset_install
mkdir -p "$LOCAL_BIN" "$COMP_DIR"
ln -s "$TMP/stale-binary-before-completion-repoint" "$LOCAL_BIN/pwt"
ln -s "$TMP/stale-completion-before-repoint" "$COMP_LINK"
completion_stale_status=0
completion_stale_out=$(cd "$OUTSIDE" && \
  PATH="$INSTALL_COMPLETION_FAIL_BIN:$PATH" "$PWT" install 2>&1) || \
  completion_stale_status=$?
check 'late stale-completion repoint failure exits non-zero' \
  test "$completion_stale_status" -ne 0
check_equals 'failed stale-completion repoint restores the binary target' \
  "$TMP/stale-binary-before-completion-repoint" \
  "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"
check_equals 'failed stale-completion repoint restores its previous target' \
  "$TMP/stale-completion-before-repoint" \
  "$(readlink "$COMP_LINK" 2>/dev/null)"

# Invoking install through its installed link must resolve back to this checkout,
# not repoint the link at itself.
reset_install
pwt_in "$OUTSIDE" install >/dev/null 2>&1
via_symlink=$(cd "$OUTSIDE" && "$LOCAL_BIN/pwt" install 2>&1)
check_equals 'install through its symlink still targets the repository script' \
  "$PWT" "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"
check_contains 'install through its symlink succeeds idempotently' \
  'already installed' "$via_symlink"

# The lock must be acquired before resolving an installed symlink. Otherwise a
# concurrent installer can move that link mid-resolution and make it resolve to
# the install target itself.
INSTALL_LOCK_BIN="$TMP/install-lock-bin"
INSTALL_LOCK_READLINK_MARKER="$TMP/install-lock-readlink-marker"
mkdir -p "$INSTALL_LOCK_BIN"
cat >"$INSTALL_LOCK_BIN/readlink" <<'STUB'
#!/bin/bash
: >"$PWT_TEST_INSTALL_LOCK_READLINK_MARKER"
exec "$PWT_TEST_REAL_READLINK" "$@"
STUB
chmod +x "$INSTALL_LOCK_BIN/readlink"
mkdir "$LOCAL_BIN/.pwt-install.lock"
locked_install_status=0
locked_install_out=$(cd "$OUTSIDE" && \
  PWT_TEST_INSTALL_LOCK_READLINK_MARKER="$INSTALL_LOCK_READLINK_MARKER" \
    PATH="$INSTALL_LOCK_BIN:/usr/bin:/bin" "$LOCAL_BIN/pwt" install 2>&1) || \
  locked_install_status=$?
check 'install through its symlink refuses a concurrent installer' \
  test "$locked_install_status" -ne 0
check_contains 'concurrent install refusal names the active install' \
  'another pwt install is already running' "$locked_install_out"
check 'concurrent install refuses before resolving its installed symlink' \
  test ! -e "$INSTALL_LOCK_READLINK_MARKER"
check_equals 'concurrent install leaves the installed pwt link unchanged' \
  "$PWT" "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"
check "refused install preserves the other installer's lock" \
  test -d "$LOCAL_BIN/.pwt-install.lock"
check 'concurrent-install fixture lock is removable afterwards' \
  rmdir "$LOCAL_BIN/.pwt-install.lock"

# Releasing the lock makes its pathname available to a successor. If release
# then reports failure, EXIT cleanup must not remove the successor's directory.
INSTALL_RELEASE_BIN="$TMP/install-release-bin"
INSTALL_RELEASE_MARKER="$TMP/install-release-marker"
PWT_TEST_REAL_RMDIR=$(command -v rmdir)
export PWT_TEST_REAL_RMDIR INSTALL_RELEASE_MARKER
export PWT_TEST_INSTALL_RELEASE_LOCK="$LOCAL_BIN/.pwt-install.lock"
mkdir -p "$INSTALL_RELEASE_BIN"
cat >"$INSTALL_RELEASE_BIN/rmdir" <<'STUB'
#!/bin/bash
if [ "$1" = "$PWT_TEST_INSTALL_RELEASE_LOCK" ] && [ ! -e "$INSTALL_RELEASE_MARKER" ]; then
  "$PWT_TEST_REAL_RMDIR" "$1" || exit
  /bin/mkdir "$1" || exit
  : >"$INSTALL_RELEASE_MARKER"
  exit 70
fi
exec "$PWT_TEST_REAL_RMDIR" "$@"
STUB
chmod +x "$INSTALL_RELEASE_BIN/rmdir"
release_install_status=0
release_install_out=$(cd "$OUTSIDE" && \
  PATH="$INSTALL_RELEASE_BIN:/usr/bin:/bin" "$PWT" install 2>&1) || \
  release_install_status=$?
check 'install surfaces a lock-release failure' \
  test "$release_install_status" -ne 0
check_contains 'lock-release failure names the retained lock' \
  'cannot release pwt install lock' "$release_install_out"
check 'lock release reached the successor-install fixture' \
  test -e "$INSTALL_RELEASE_MARKER"
check "failed release preserves the successor installer's lock" \
  test -d "$LOCAL_BIN/.pwt-install.lock"
check 'successor-install fixture lock is removable afterwards' \
  "$PWT_TEST_REAL_RMDIR" "$LOCAL_BIN/.pwt-install.lock"

# Bash 3.2 disables errexit inside command substitutions. An explicit failure
# path in resolve_self must therefore reject a broken readlink and release the
# whole-installer lock without changing the installed link.
INSTALL_FAILURE_BIN="$TMP/install-failure-bin"
INSTALL_FAILURE_MARKER="$TMP/install-failure-marker"
mkdir -p "$INSTALL_FAILURE_BIN"
cat >"$INSTALL_FAILURE_BIN/readlink" <<'STUB'
#!/bin/bash
if [ ! -e "$PWT_TEST_FAILED_READLINK_MARKER" ]; then
  : >"$PWT_TEST_FAILED_READLINK_MARKER"
  printf '%s\n' "$PWT_TEST_FAILED_READLINK_VALUE"
  exit 70
fi
exec "$PWT_TEST_REAL_READLINK" "$@"
STUB
chmod +x "$INSTALL_FAILURE_BIN/readlink"
readlink_failure_status=0
readlink_failure_out=$(cd "$OUTSIDE" && \
  PWT_TEST_FAILED_READLINK_VALUE="$PWT" \
    PWT_TEST_FAILED_READLINK_MARKER="$INSTALL_FAILURE_MARKER" \
    PATH="$INSTALL_FAILURE_BIN:/usr/bin:/bin" "$LOCAL_BIN/pwt" install 2>&1) || \
  readlink_failure_status=$?
check 'install rejects a failed symlink resolution' \
  test "$readlink_failure_status" -ne 0
check_contains 'failed symlink resolution reports the source-path error' \
  'cannot resolve the pwt source path' "$readlink_failure_out"
check_equals 'failed symlink resolution leaves the installed link unchanged' \
  "$PWT" "$(readlink "$LOCAL_BIN/pwt" 2>/dev/null)"
check 'failed symlink resolution releases the installer lock' \
  test ! -e "$LOCAL_BIN/.pwt-install.lock"

# The path warning is guidance only; installation still succeeds.
reset_install
off_path_status=0
off_path_out=$(cd "$OUTSIDE" && PATH="$BIN:/usr/bin:/bin" "$PWT" install 2>&1) || \
  off_path_status=$?
check_equals 'install succeeds when ~/.local/bin is not on PATH' '0' "$off_path_status"
check_contains 'install warns when ~/.local/bin is not on PATH' 'PATH' "$off_path_out"
check_fails 'install rejects unexpected arguments' pwt_in "$OUTSIDE" install extra

# Install resolves utilities before it has any repository trust boundary. A
# relative PATH entry would let the caller's checkout provide those utilities.
INSTALL_PATH_MARKER="$TMP/install-path-marker"
cat >"$OUTSIDE/mkdir" <<'STUB'
#!/bin/bash
: >"$PWT_TEST_INSTALL_PATH_MARKER"
exit 70
STUB
chmod +x "$OUTSIDE/mkdir"
install_path_status=0
install_path_out=$(
  cd "$OUTSIDE" || exit 1
  PWT_TEST_INSTALL_PATH_MARKER="$INSTALL_PATH_MARKER" \
    PATH=".:$BIN:/usr/bin:/bin" "$PWT" install 2>&1
) || install_path_status=$?
check 'install rejects relative PATH entries before utility lookup' \
  test "$install_path_status" -ne 0
check_contains 'install relative-PATH refusal names the absolute-entry rule' \
  'absolute PATH entries' "$install_path_out"
check 'install never executes a cwd-provided utility' \
  test ! -e "$INSTALL_PATH_MARKER"
rm -f "$OUTSIDE/mkdir"

# HOME is the installation authority and must be an absolute location. A
# relative XDG_DATA_HOME is invalid by the XDG contract and falls back safely.
relative_home_status=0
relative_home_out=$(
  cd "$OUTSIDE" || exit 1
  HOME=relative-home PATH="$BIN:/usr/bin:/bin" "$PWT" install 2>&1
) || relative_home_status=$?
check 'install rejects a relative HOME' test "$relative_home_status" -ne 0
check_contains 'relative HOME refusal names the absolute-path requirement' \
  'absolute HOME' "$relative_home_out"
check 'relative HOME creates no cwd-relative install directory' \
  test ! -e "$OUTSIDE/relative-home"

reset_install
relative_xdg_status=0
(
  export XDG_DATA_HOME=relative-data
  pwt_in "$OUTSIDE" install >/dev/null 2>&1
) || relative_xdg_status=$?
check_equals 'install ignores a relative XDG_DATA_HOME' '0' "$relative_xdg_status"
check 'relative XDG data falls back to the HOME completion directory' \
  test -L "$COMP_LINK"
check 'relative XDG data creates no cwd-relative directory' \
  test ! -e "$OUTSIDE/relative-data"

# ------------------------------------------------------------- bash completion

section 'completion'

COMPLETION=${PWT_COMPLETION_UNDER_TEST:-"$REPO_ROOT/pi/scripts/pwt-completion.bash"}

check 'the completion script exists' test -f "$COMPLETION"
check 'the completion script parses as valid bash' bash -n "$COMPLETION"

# zsh does not autoload Bash completions. bashcompinit must be able to source the
# installed-format file and register pwt's public completion function.
if command -v zsh >/dev/null 2>&1; then
  if zsh -f -c '
    autoload -Uz compinit && compinit -u -d "$1"
    autoload -Uz bashcompinit && bashcompinit
    source "$2"
    complete -p pwt | grep -qxF "complete -o nospace -F _pwt pwt"
  ' pwt-test "$TMP/zcompdump" "$COMPLETION" >/dev/null 2>&1; then
    ok 'zsh bashcompinit registers the pwt completion'
  else
    not_ok 'zsh bashcompinit registers the pwt completion'
  fi
else
  skip 'zsh bashcompinit registration (zsh unavailable)'
fi

# Prove each source detector catches its named regression before asking it to
# reject the real completion. Without these positive controls, a broken pattern
# could make the security negatives pass vacuously.
completion_source_has_network_call() {
  sed 's/#.*//' |
    grep -qE '\b(gh|curl|wget|nc|netcat|ssh|scp|sftp|ftp|telnet|rsync)\b|git[[:space:]]+(clone|fetch|pull|push|ls-remote)([[:space:]]|$)|git[[:space:]]+remote[[:space:]]+(update|prune)([[:space:]]|$)|git[[:space:]]+submodule[[:space:]]+(update|sync|foreach)([[:space:]]|$)|/dev/(tcp|udp)/'
}
completion_source_uses_bash4() {
  sed 's/#.*//' |
    grep -qE '\b(mapfile|readarray|compopt)\b|(^|[[:space:]])(declare|local)[[:space:]]+-A([[:space:]]|$)'
}

if printf '%s\n' 'git remote update' | completion_source_has_network_call; then
  ok 'the network detector rejects a network-capable Git command'
else
  not_ok 'the network detector rejects a network-capable Git command'
fi
if completion_source_has_network_call <"$COMPLETION"; then
  not_ok 'the completion script makes no network calls'
else
  ok 'the completion script makes no network calls'
fi
if printf '%s\n' 'declare -A values' | completion_source_uses_bash4; then
  ok 'the Bash 3.2 detector rejects associative arrays'
else
  not_ok 'the Bash 3.2 detector rejects associative arrays'
fi
if completion_source_uses_bash4 <"$COMPLETION"; then
  not_ok 'the completion script avoids Bash 4-only builtins'
else
  ok 'the completion script avoids Bash 4-only builtins'
fi

if [ -f "$COMPLETION" ]; then
  # shellcheck disable=SC1090
  . "$COMPLETION"

  complete_for() {
    COMP_WORDS=("$@")
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    COMPREPLY=()
    _pwt >/dev/null 2>&1 || true
    # Runtime completion uses a trailing delimiter under the global `nospace`
    # registration. Strip it only for value-oriented unit assertions here.
    printf '%s\n' "${COMPREPLY[@]-}" | sed 's/ $//'
  }

  cd "$PRIMARY" || exit 1

  subs=$(complete_for pwt '')
  expected_subs=$(printf '%s\n' \
    new branch open pr root list remove prune install help | sort)
  actual_subs=$(printf '%s\n' "$subs" | sed '/^$/d' | sort)
  check_equals 'completion offers exactly the ten pwt subcommands' \
    "$expected_subs" "$actual_subs"

  filtered=$(complete_for pwt 'pr')
  if printf '%s\n' "$filtered" | grep -qx 'pr' &&
    printf '%s\n' "$filtered" | grep -qx 'prune' &&
    ! printf '%s\n' "$filtered" | grep -qx 'new'; then
    ok 'completion filters pwt subcommands by prefix'
  else
    not_ok 'completion filters pwt subcommands by prefix'
  fi

  types=$(complete_for pwt new '')
  if printf '%s\n' "$types" | grep -qx 'feat/' &&
    printf '%s\n' "$types" | grep -qx 'fix/'; then
    ok 'completion offers conventional-commit type prefixes for new'
  else
    not_ok 'completion offers conventional-commit type prefixes for new'
  fi

  branches=$(complete_for pwt branch '')
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
  git -C "$PRIMARY" branch origin/local-topic
  branches=$(complete_for pwt branch 'origin/')
  if printf '%s\n' "$branches" | grep -qx 'origin/local-topic'; then
    ok 'completion preserves origin-prefixed local branch names'
  else
    not_ok 'completion preserves origin-prefixed local branch names'
  fi

  # Git's NUL-delimited porcelain keeps worktree paths literal. A physical
  # managed root containing a backslash must still match its registered branch.
  BACKSLASH_HOME="$TMP/home\\completion"
  BACKSLASH_MANAGED="$BACKSLASH_HOME/github/.worktrees/owner/project"
  BACKSLASH_WORKTREE="$BACKSLASH_MANAGED/completion-backslash"
  mkdir -p "$BACKSLASH_MANAGED"
  git -C "$PRIMARY" worktree add -q -b feat/completion-backslash \
    "$BACKSLASH_WORKTREE" HEAD 2>/dev/null
  backslash_opens=$(HOME="$BACKSLASH_HOME" complete_for pwt open '')
  if printf '%s\n' "$backslash_opens" | grep -qx 'feat/completion-backslash'; then
    ok 'completion preserves a backslash in the physical managed root'
  else
    not_ok 'completion preserves a backslash in the physical managed root'
  fi
  git -C "$PRIMARY" worktree remove --force "$BACKSLASH_WORKTREE" >/dev/null 2>&1
  git -C "$PRIMARY" branch -D feat/completion-backslash >/dev/null 2>&1

  # A worktree for this repository can still sit below another repository's
  # managed subtree. Completion must use pwt's repo-specific root, not the broad
  # shared worktree directory.
  SIBLING_MANAGED="$HOME/github/.worktrees/other/repository"
  SIBLING_WORKTREE="$SIBLING_MANAGED/completion-stray"
  mkdir -p "$SIBLING_MANAGED"
  git -C "$PRIMARY" worktree add -q -b feat/completion-stray \
    "$SIBLING_WORKTREE" HEAD 2>/dev/null

  opens=$(complete_for pwt open '')
  if printf '%s\n' "$opens" | grep -qx 'feat/alpha'; then
    ok 'completion offers managed worktree branches for open'
  else
    not_ok 'completion offers managed worktree branches for open'
  fi
  if printf '%s\n' "$opens" | grep -qx 'feat/stray'; then
    not_ok 'completion excludes worktrees outside the managed root'
  else
    ok 'completion excludes worktrees outside the managed root'
  fi
  if printf '%s\n' "$opens" | grep -qx 'feat/completion-stray'; then
    not_ok 'completion excludes worktrees under another managed repository root'
  else
    ok 'completion excludes worktrees under another managed repository root'
  fi

  removes=$(complete_for pwt remove '')
  if printf '%s\n' "$removes" | grep -qx 'feat/alpha'; then
    ok 'completion offers managed worktree branches for remove'
  else
    not_ok 'completion offers managed worktree branches for remove'
  fi
  if printf '%s\n' "$removes" | grep -qx 'feat/completion-stray'; then
    not_ok 'remove completion excludes another repository managed root'
  else
    ok 'remove completion excludes another repository managed root'
  fi

  # Positive controls for the complete flag matrix come before its negative
  # assertions. Each supported flag must be observable on its owning command.
  pr_flags=$(complete_for pwt pr 701 '--')
  remove_flags=$(complete_for pwt remove feat/alpha '--')
  prune_flags=$(complete_for pwt prune '--')
  if printf '%s\n' "$pr_flags" | grep -qx -- '--force' &&
    printf '%s\n' "$remove_flags" | grep -qx -- '--delete-branch' &&
    printf '%s\n' "$prune_flags" | grep -qx -- '--yes'; then
    ok 'completion offers each supported flag to its owning command'
  else
    not_ok 'completion offers each supported flag to its owning command'
  fi

  all_flags=''
  for sub in new branch open pr root list remove prune install help; do
    command_flags=$(complete_for pwt "$sub" operand '--')
    all_flags=$(printf '%s\n%s\n' "$all_flags" "$command_flags")
    case $sub in
      pr) expected_flag='--force' ;;
      remove) expected_flag='--delete-branch' ;;
      prune) expected_flag='--yes' ;;
      *) expected_flag='' ;;
    esac
    actual_flags=$(printf '%s\n' "$command_flags" | sed '/^$/d')
    if [ "$actual_flags" = "$expected_flag" ]; then
      ok "completion limits flags to pwt $sub"
    else
      not_ok "completion limits flags to pwt $sub (got: $actual_flags)"
    fi
  done
  if printf '%s\n' "$all_flags" | grep -qx -- '--yolo'; then
    not_ok 'completion never offers yolo mode'
  else
    ok 'completion never offers yolo mode'
  fi

  # Once `--` has been entered, following options belong to Pi, not pwt. The
  # working pr flag check above prevents this negative from passing vacuously.
  forwarded=$(complete_for pwt pr 701 -- '--f')
  if [ -z "$(printf '%s' "$forwarded" | tr -d '[:space:]')" ]; then
    ok 'completion leaves arguments after -- to Pi'
  else
    not_ok 'completion leaves arguments after -- to Pi'
  fi

  # Never put Git output through compgen -W: it re-expands command substitutions
  # embedded in a valid branch name. Assert the safe matcher exists before the
  # negative source check so a missing implementation cannot pass silently.
  if sed 's/#.*//' "$COMPLETION" | grep -q '_pwt_add_matches'; then
    ok 'completion routes untrusted branch names through the inert matcher'
  else
    not_ok 'completion routes untrusted branch names through the inert matcher'
  fi
  if sed 's/#.*//' "$COMPLETION" | grep -q 'compgen -W "$('; then
    not_ok 'completion never passes command output to compgen -W'
  else
    ok 'completion never passes command output to compgen -W'
  fi

  if sed 's/#.*//' "$COMPLETION" |
    grep -q "printf -v quoted '%q' \"\$candidate\"" &&
    sed 's/#.*//' "$COMPLETION" |
      grep -q 'complete -o nospace -F _pwt pwt'; then
    ok 'untrusted completion candidates are shell-escaped before insertion'
  else
    not_ok 'untrusted completion candidates are shell-escaped before insertion'
  fi

  # This branch is valid Git data but dangerous if a completion implementation
  # asks the shell to expand it. Prove the fixture exists and is offered in its
  # Bash-escaped form before driving a real interactive Tab followed by Enter.
  RCE_MARKER="$PRIMARY/completion-rce-marker"
  HOSTILE_BRANCH='feat/x$(touch${IFS}completion-rce-marker)'
  HOSTILE_WORKTREE="$MANAGED/hostile-completion"
  rm -f "$RCE_MARKER"
  hostile_branch_err=$(git -C "$PRIMARY" worktree add -q -b "$HOSTILE_BRANCH" \
    "$HOSTILE_WORKTREE" HEAD 2>&1)
  if git -C "$PRIMARY" show-ref --verify --quiet "refs/heads/$HOSTILE_BRANCH"; then
    ok 'the hostile completion branch fixture exists'
  else
    not_ok "the hostile completion branch fixture exists ($hostile_branch_err)"
  fi

  printf -v HOSTILE_QUOTED '%q' "$HOSTILE_BRANCH"
  hostile_completion=$(complete_for pwt open 'feat/x')
  if printf '%s\n' "$hostile_completion" | grep -qxF "$HOSTILE_QUOTED"; then
    ok 'completion offers the hostile branch as shell-escaped inert data'
  else
    not_ok "completion offers the hostile branch as shell-escaped inert data (got: $hostile_completion)"
  fi
  if [ -e "$RCE_MARKER" ]; then
    not_ok 'completing a hostile branch does not execute it'
  else
    ok 'completing a hostile branch does not execute it'
  fi

  # COMPREPLY-only tests cannot observe how Readline inserts a unique match. A
  # real Bash 3.2 PTY catches the historical failure where Tab inserted `$()`
  # unquoted and Enter executed it. `expect` ships with macOS; keep a graceful
  # skip for other environments while the source-level guard remains mandatory.
  if command -v expect >/dev/null 2>&1; then
    launch_reset
    completion_pty_status=0
    COMPLETION_PTY_LOG="$TMP/completion-pty.log"
    PWT_TEST_COMPLETION_PATH="$COMPLETION" \
      PWT_TEST_COMPLETION_PRIMARY="$PRIMARY" expect -c '
      set timeout 10
      spawn -noecho /bin/bash --noprofile --norc -i
      expect -re {[$#] $}
      send -- "PS1=\u0027PWT-PTY> \u0027\r"
      expect "PWT-PTY> "
      send -- "source $env(PWT_TEST_COMPLETION_PATH)\r"
      expect "PWT-PTY> "
      send -- "cd $env(PWT_TEST_COMPLETION_PRIMARY)\r"
      expect "PWT-PTY> "
      send -- "pwt open feat/x\t\r"
      expect "PWT-PTY> "
      send -- "exit\r"
      expect eof
    ' >"$COMPLETION_PTY_LOG" 2>&1 || \
      completion_pty_status=$?
    if [ "$completion_pty_status" -ne 0 ]; then
      sed 's/^/    PTY: /' "$COMPLETION_PTY_LOG" >&2
    fi
    check_equals 'Bash 3.2 completes and executes the hostile branch safely' \
      '0' "$completion_pty_status"
    check_equals 'interactive completion launches the literal hostile worktree' \
      "$HOSTILE_WORKTREE" "$(launched pwd)"
    if [ -e "$RCE_MARKER" ]; then
      not_ok 'interactive Tab and Enter keep the hostile branch inert'
    else
      ok 'interactive Tab and Enter keep the hostile branch inert'
    fi
  else
    skip 'interactive hostile-branch completion (expect unavailable)'
  fi

  # Completion must also refuse cwd-provided Git helpers when PATH contains a
  # relative entry. Existing branch results above are the positive control.
  COMPLETION_PATH_MARKER="$TMP/completion-path-marker"
  cat >"$OUTSIDE/git" <<'STUB'
#!/bin/bash
: >"$PWT_TEST_COMPLETION_PATH_MARKER"
exit 70
STUB
  chmod +x "$OUTSIDE/git"
  path_attack_completion=$(
    cd "$OUTSIDE" || exit 1
    PWT_TEST_COMPLETION_PATH_MARKER="$COMPLETION_PATH_MARKER" \
      PATH=".:$PATH" complete_for pwt branch ''
  )
  if [ -z "$(printf '%s' "$path_attack_completion" | tr -d '[:space:]')" ]; then
    ok 'completion returns no dynamic candidates for a relative PATH'
  else
    not_ok 'completion returns no dynamic candidates for a relative PATH'
  fi
  check 'completion never executes a cwd-provided Git helper' \
    test ! -e "$COMPLETION_PATH_MARKER"
  rm -f "$OUTSIDE/git"

  # Run every completion context with only its allowed local tools available.
  # Positive controls first prove both rejection paths record a forbidden call.
  COMPLETION_AUDIT_BIN="$TMP/completion-audit-bin"
  COMPLETION_AUDIT_LOG="$TMP/completion-audit-log"
  mkdir -p "$COMPLETION_AUDIT_BIN"
  for tool in bash env sed grep sort; do
    ln -s "$(command -v "$tool")" "$COMPLETION_AUDIT_BIN/$tool"
  done
  ln -s "$BIN/git" "$COMPLETION_AUDIT_BIN/git"
  cat >"$COMPLETION_AUDIT_BIN/network-tripwire" <<'STUB'
#!/bin/bash
printf 'UNEXPECTED COMMAND: %s\n' "${0##*/}" >>"$PWT_TEST_COMPLETION_AUDIT_LOG"
exit 97
STUB
  chmod +x "$COMPLETION_AUDIT_BIN/network-tripwire"
  for tool in gh curl wget nc netcat ssh scp sftp ftp telnet rsync; do
    ln -s "$COMPLETION_AUDIT_BIN/network-tripwire" "$COMPLETION_AUDIT_BIN/$tool"
  done
  : >"$COMPLETION_AUDIT_LOG"
  (
    export PATH="$COMPLETION_AUDIT_BIN"
    export PWT_TEST_COMPLETION_AUDIT_LOG="$COMPLETION_AUDIT_LOG"
    curl example.invalid >/dev/null 2>&1 || true
  )
  check 'completion audit tripwire records a forbidden executable' \
    grep -qxF 'UNEXPECTED COMMAND: curl' "$COMPLETION_AUDIT_LOG"
  : >"$COMPLETION_AUDIT_LOG"
  (
    export PATH="$COMPLETION_AUDIT_BIN"
    export PWT_TEST_COMPLETION_AUDIT_LOG="$COMPLETION_AUDIT_LOG"
    git remote update >/dev/null 2>&1 || true
  )
  check 'completion Git audit rejects a network-capable subcommand' \
    grep -qxF 'UNEXPECTED GIT: remote update' "$COMPLETION_AUDIT_LOG"
  : >"$COMPLETION_AUDIT_LOG"
  (
    export PATH="$COMPLETION_AUDIT_BIN"
    export PWT_TEST_COMPLETION_AUDIT_LOG="$COMPLETION_AUDIT_LOG"
    for sub in new branch open pr root list remove prune install help; do
      complete_for pwt "$sub" '' >/dev/null
      complete_for pwt "$sub" operand '' >/dev/null
      complete_for pwt "$sub" operand '--' >/dev/null
    done
  )
  check 'completion audit observes the local branch query' \
    grep -qxF 'for-each-ref --format=%(refname) refs/heads refs/remotes/origin' \
      "$COMPLETION_AUDIT_LOG"
  check 'completion audit observes the local origin query' \
    grep -qxF 'config --get remote.origin.url' "$COMPLETION_AUDIT_LOG"
  check 'completion audit observes the local worktree query' \
    grep -qxF 'worktree list --porcelain -z' "$COMPLETION_AUDIT_LOG"
  if grep -q '^UNEXPECTED ' "$COMPLETION_AUDIT_LOG"; then
    not_ok 'completion uses only the allowlisted local commands'
  else
    ok 'completion uses only the allowlisted local commands'
  fi

  git -C "$PRIMARY" worktree remove --force "$HOSTILE_WORKTREE" >/dev/null 2>&1
  git -C "$PRIMARY" branch -D "$HOSTILE_BRANCH" >/dev/null 2>&1
  git -C "$PRIMARY" worktree remove --force "$SIBLING_WORKTREE" >/dev/null 2>&1
  git -C "$PRIMARY" branch -D feat/completion-stray >/dev/null 2>&1

  cd "$OUTSIDE" || exit 1
  outside=$(complete_for pwt '')
  if printf '%s\n' "$outside" | grep -qx 'new'; then
    ok 'completion still offers subcommands outside a Git repository'
  else
    not_ok 'completion still offers subcommands outside a Git repository'
  fi
  outside_branches=$(complete_for pwt open '')
  if [ -z "$(printf '%s' "$outside_branches" | tr -d '[:space:]')" ]; then
    ok 'completion returns no branches outside a Git repository'
  else
    not_ok 'completion returns no branches outside a Git repository'
  fi
fi

# ------------------------------------------------------------- suite contract

section 'suite contract'

# This specifically fails if pwt_in records an attempted command before its
# requested working directory has been entered successfully.
command_count_before=$(wc -l <"$PWT_TEST_COMMAND_LOG" | tr -d '[:space:]')
pwt_in "$TMP/missing-command-log-cwd" help >/dev/null 2>&1 || true
command_count_after=$(wc -l <"$PWT_TEST_COMMAND_LOG" | tr -d '[:space:]')
check_equals 'command coverage records only invocations reached after directory entry' \
  "$command_count_before" "$command_count_after"

missing=''
for sub in $SUBCOMMANDS; do
  grep -qxF "$sub" "$PWT_TEST_COMMAND_LOG" || missing="$missing $sub"
done
if [ -z "$missing" ]; then
  ok 'the suite executes every public subcommand'
else
  not_ok "the suite executes every public subcommand (missing:$missing)"
fi

source_has_normalized_term() {
  local first=$1 second=${2-}
  awk -v first="$first" -v second="$second" '
    BEGIN {
      first = tolower(first)
      second = tolower(second)
    }
    {
      normalized = tolower($0)
      gsub(/["\047]/, "", normalized)
      if (index(normalized, first) ||
          (second != "" && index(normalized, second))) {
        print NR ":" $0
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  '
}
old_harness_lower=code
old_harness_lower=${old_harness_lower}x
old_harness_upper=C
old_harness_upper=${old_harness_upper}WT
source_has_stale_harness_term() {
  source_has_normalized_term "$old_harness_lower" "$old_harness_upper"
}
if printf '%s\n' "$old_harness_lower" | \
    source_has_stale_harness_term >/dev/null &&
  printf '%s\n' "$old_harness_upper" | \
    source_has_stale_harness_term >/dev/null; then
  ok 'the stale-harness detector recognizes its literal tokens'
else
  not_ok 'the stale-harness detector recognizes its literal tokens'
fi
split_harness_lower="${old_harness_lower%dex}''${old_harness_lower#co}"
split_harness_upper="${old_harness_upper%WT}''${old_harness_upper#C}"
if printf '%s\n' "$split_harness_lower" | \
    source_has_stale_harness_term >/dev/null &&
  printf '%s\n' "$split_harness_upper" | \
    source_has_stale_harness_term >/dev/null; then
  ok 'the stale-harness detector recognizes split shell tokens'
else
  not_ok 'the stale-harness detector recognizes split shell tokens'
fi
stale_harness_mentions=''
for source_file in "$PWT" "$COMPLETION" "$TEST_SOURCE"; do
  mentions=$(source_has_stale_harness_term <"$source_file" 2>/dev/null || true)
  if [ -n "$mentions" ]; then
    stale_harness_mentions="$stale_harness_mentions
$source_file:
$mentions"
  fi
done
if [ -z "$stale_harness_mentions" ]; then
  ok 'runtime, completion, and suite contain no stale harness terminology'
else
  not_ok "runtime, completion, and suite contain stale harness terminology:$stale_harness_mentions"
fi

permission_alias=yo
permission_alias=${permission_alias}lo
source_has_permission_alias() {
  source_has_normalized_term "$permission_alias"
}
# Awk normally exits zero even when it prints no matching lines. Pin the
# detector's explicit no-match status so its positive controls cannot lie.
if printf '%s\n' 'ordinary source line' | \
  source_has_permission_alias >/dev/null; then
  not_ok 'the normalized-term detector returns non-zero without a match'
else
  ok 'the normalized-term detector returns non-zero without a match'
fi
permission_mention_is_negative() {
  local source_line
  source_line=$(printf '%s\n' "${1#*:}" | sed 's/^[[:space:]]*//')
  case $source_line in
    "check_not_contains 'pwt help omits $permission_alias mode' '$permission_alias' \"\$help_text\"" | \
      "check_fails 'an unknown pwt-side flag fails before pi launches' pwt root --$permission_alias" | \
      "check_output 'the unknown pwt-side flag is named in the error' '$permission_alias' pwt root --$permission_alias" | \
      "if printf '%s\n' \"\$all_flags\" | grep -qx -- '--$permission_alias'; then" | \
      "not_ok 'completion never offers $permission_alias mode'" | \
      "ok 'completion never offers $permission_alias mode'")
      return 0
      ;;
  esac
  return 1
}
if printf '%s\n' "$permission_alias" | source_has_permission_alias >/dev/null; then
  ok 'the permission-bypass detector recognizes its literal token'
else
  not_ok 'the permission-bypass detector recognizes its literal token'
fi
split_permission_alias="${permission_alias%lo}''${permission_alias#yo}"
if printf '%s\n' "$split_permission_alias" | \
  source_has_permission_alias >/dev/null; then
  ok 'the permission-bypass detector recognizes a split shell token'
else
  not_ok 'the permission-bypass detector recognizes a split shell token'
fi
if permission_mention_is_negative \
  "launch Pi with --$permission_alias enabled"; then
  not_ok 'the permission-bypass classifier rejects a launch expectation'
else
  ok 'the permission-bypass classifier rejects a launch expectation'
fi
stale_permission_mentions=''
while IFS= read -r mention; do
  [ -n "$mention" ] || continue
  permission_mention_is_negative "$mention" ||
    stale_permission_mentions="$stale_permission_mentions
$mention"
done <<MENTIONS
$(source_has_permission_alias <"$TEST_SOURCE" 2>/dev/null || true)
MENTIONS
if [ -z "$stale_permission_mentions" ]; then
  ok 'the suite contains no stale permission-bypass launch expectation'
else
  not_ok "the suite contains a stale permission-bypass launch expectation:$stale_permission_mentions"
fi

# -------------------------------------------------------------------- summary

section "results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
