# bash completion for clwt
#
# Install by symlinking this file as `clwt` into
#   ${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/
# which bash-completion 2.x autoloads on first Tab. `clwt install` does that.
#
# HARD RULE 1: no completion path may touch the network. Tab has to feel instant,
# and a completion that occasionally hangs while a request times out is worse
# than one that stays quiet. That is why `pr` completes nothing — offering PR
# numbers would mean a `gh` API call on every keypress.
#
# HARD RULE 2: never pass branch names — or anything else that came from a remote
# — through `compgen -W`. `compgen -W` performs full word expansion on its word
# list, INCLUDING command substitution, and `git check-ref-format` happily accepts
# a branch named `feat/x$(...)`. So `compgen -W "$(git for-each-ref ...)"` executes
# attacker-chosen code the moment the developer presses Tab, with no subcommand
# ever run and no confirmation. Untrusted candidates go through
# _clwt_add_matches, which only ever compares them as data.

# Prefix-matches candidates from stdin into COMPREPLY without re-expanding them.
_clwt_add_matches() {
  local cur=$1 candidate
  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    if [[ $candidate == "$cur"* ]]; then
      COMPREPLY+=("$candidate")
    fi
  done
}

# Branches with a worktree under the managed root. Any worktree of *this*
# repository living under ~/github/.worktrees is by definition one clwt manages,
# so the owner/repo path does not need re-deriving here.
_clwt_managed_branches() {
  # The whole root is resolved, not just $HOME: `git worktree list` reports fully
  # resolved paths, and ~/github or ~/github/.worktrees may themselves be
  # symlinks. Resolving a prefix only halfway is the same mismatch that made clwt
  # disown its own worktrees.
  local root
  root=$(cd "$HOME/github/.worktrees" 2>/dev/null && pwd -P) || return 0
  git worktree list --porcelain 2>/dev/null |
    awk -v root="$root/" '
      /^worktree / { path = substr($0, 10) }
      /^branch refs\/heads\// {
        if (index(path, root) == 1) print substr($0, 19)
      }
    '
}

# Local branches plus origin's, deduplicated, with origin/ stripped so both
# forms complete to the name `clwt branch` actually wants.
_clwt_all_branches() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null |
    sed 's|^origin/||' |
    grep -v '^HEAD$' |
    sort -u
}

_clwt() {
  local cur cmd flags
  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]-}
  cmd=${COMP_WORDS[1]-}

  local subcommands='new branch open pr root list remove prune install help'

  # Conventional-commit types, matching the branch-names skill. `new` requires a
  # typed name, so these are exactly what it accepts.
  local types='feat/ fix/ refactor/ docs/ test/ chore/ perf/ style/ ci/'

  # compgen -W is safe for the three lists below and only those: every word is a
  # literal defined in this file. Do not extend them with anything from git, gh,
  # the filesystem, or the environment.
  if [[ $COMP_CWORD -le 1 ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$subcommands" -- "$cur")
    return 0
  fi

  if [[ $cur == -* ]]; then
    case $cmd in
      new | branch | open | pr | root) flags='--yolo' ;;
      remove) flags='--delete-branch' ;;
      prune) flags='--yes' ;;
      *) flags='' ;;
    esac
    mapfile -t COMPREPLY < <(compgen -W "$flags" -- "$cur")
    return 0
  fi

  case $cmd in
    new)
      # Type prefixes, never branch names: `new` creates a branch that does not
      # exist yet, and completing to an existing one lands you straight in its
      # "local branch already exists, use clwt branch" error.
      mapfile -t COMPREPLY < <(compgen -W "$types" -- "$cur")
      compopt -o nospace 2>/dev/null || true
      ;;
    branch)
      _clwt_add_matches "$cur" < <(_clwt_all_branches)
      # readline inserts an accepted match into the command line unquoted, so on a
      # *unique* match Tab silently rewrites the line and Enter expands it — a
      # branch named `feat/x$(...)` then runs on Enter. `-o filenames` makes
      # readline quote the insertion, so it arrives at clwt as literal text. Git's
      # own completion has the same exposure; this makes clwt strictly safer.
      compopt -o filenames 2>/dev/null || true
      ;;
    open | remove)
      _clwt_add_matches "$cur" < <(_clwt_managed_branches)
      compopt -o filenames 2>/dev/null || true
      ;;
    *)
      # pr, root, list, prune, install, help take no completable operand.
      ;;
  esac
  return 0
}

complete -F _clwt clwt
