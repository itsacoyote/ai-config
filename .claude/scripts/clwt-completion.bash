# bash completion for clwt
#
# Install by symlinking this file as `clwt` into
#   ${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/
# which bash-completion 2.x autoloads on first Tab. `clwt install` does that.
#
# HARD RULE: no completion path may touch the network. Tab has to feel instant,
# and a completion that occasionally hangs while a request times out is worse
# than one that stays quiet. That is why `pr` completes nothing — offering PR
# numbers would mean a `gh` API call on every keypress.

# Branches with a worktree under the managed root. Any worktree of *this*
# repository living under ~/github/.worktrees is by definition one clwt manages,
# so the owner/repo path does not need re-deriving here.
_clwt_managed_branches() {
  # $HOME resolved, because `git worktree list` reports resolved paths — the same
  # mismatch that made clwt disown its own worktrees on a symlinked home.
  local home
  home=$(cd "$HOME" 2>/dev/null && pwd -P) || return 0
  git worktree list --porcelain 2>/dev/null |
    awk -v root="$home/github/.worktrees/" '
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
      mapfile -t COMPREPLY < <(compgen -W "$(_clwt_all_branches)" -- "$cur")
      ;;
    open | remove)
      mapfile -t COMPREPLY < <(compgen -W "$(_clwt_managed_branches)" -- "$cur")
      ;;
    *)
      # pr, root, list, prune, install, help take no completable operand.
      ;;
  esac
  return 0
}

complete -F _clwt clwt
