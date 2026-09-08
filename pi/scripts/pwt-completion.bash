# bash completion for pwt
#
# Install by symlinking this file as `pwt` into
#   ${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/
# which bash-completion 2.x autoloads on first Tab. `pwt install` does that.
#
# HARD RULE 1: no completion path may touch the network. Tab has to feel instant,
# and a completion that occasionally hangs while a request times out is worse
# than one that stays quiet. That is why `pr` completes no pull request numbers.
#
# HARD RULE 2: never pass branch names — or anything else returned by Git —
# through `compgen -W`. It performs full word expansion on its word list,
# including command substitution, and Git accepts branch names containing that
# syntax. Untrusted candidates go through _pwt_add_matches as inert data.

# Fills COMPREPLY from stdin without Bash 4's `mapfile`. macOS ships Bash 3.2.
# The optional suffix is a real delimiter space under the global `nospace`
# completion registration; type prefixes pass an empty suffix so typing can
# continue after their slash.
_pwt_set_matches() {
  local suffix=$1 match
  COMPREPLY=()
  while IFS= read -r match; do
    COMPREPLY+=("$match$suffix")
  done
}

# Prefix-matches candidates from stdin, shell-escapes each match as data, and
# adds its argument delimiter. `%q` is available in Bash 3.2 and zsh's
# bashcompinit; unlike Bash 4's `compopt -o filenames`, it protects the actual
# Readline insertion on stock macOS.
_pwt_add_matches() {
  local cur=$1 candidate quoted
  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    if [[ $candidate == "$cur"* ]]; then
      printf -v quoted '%q' "$candidate"
      COMPREPLY+=("$quoted ")
    fi
  done
}

# Dynamic candidates call external utilities. If PATH can resolve relative to
# the current checkout, pressing Tab could execute a tracked helper.
_pwt_path_is_absolute() {
  local remaining=${PATH-} entry more
  while :; do
    more=0
    case $remaining in
      *:*)
        entry=${remaining%%:*}
        remaining=${remaining#*:}
        more=1
        ;;
      *) entry=$remaining ;;
    esac
    case $entry in
      /*) ;;
      *) return 1 ;;
    esac
    ((more)) || break
  done
}

# Derives only the filesystem-safe owner/repository pair needed for pwt's
# managed root. `git config` is local; this never contacts the remote.
_pwt_remote_identity() {
  local LC_ALL=C url rest owner repo
  url=$(git config --get remote.origin.url 2>/dev/null) || return 1
  url=${url%.git}
  url=${url%/}
  repo=${url##*/}
  rest=${url%/*}
  owner=${rest##*/}
  owner=${owner##*:}
  case $owner in '' | . | .. | *[!A-Za-z0-9._-]*) return 1 ;; esac
  case $repo in '' | . | .. | *[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s\n' "$owner" "$repo"
}

# Branches with a worktree under this repository's managed root. The full root
# is resolved because HOME, github, or .worktrees may themselves be symlinks
# while `git worktree list` reports physical paths.
_pwt_managed_branches() {
  local identity root field path='' branch=''
  _pwt_path_is_absolute || return 0
  case ${HOME-} in /*) ;; *) return 0 ;; esac
  identity=$(_pwt_remote_identity) || return 0
  root=$(cd "$HOME/github/.worktrees/$identity" 2>/dev/null && pwd -P) || return 0
  while IFS= read -r -d '' field; do
    case $field in
      'worktree '*)
        path=${field#worktree }
        branch=''
        ;;
      'branch refs/heads/'*)
        branch=${field#branch refs/heads/}
        ;;
      '')
        if [[ -n $branch && $path == "$root/"* ]]; then
          printf '%s\n' "$branch"
        fi
        path=''
        branch=''
        ;;
    esac
  done < <(git worktree list --porcelain -z 2>/dev/null)
}

# Local branches plus origin's, deduplicated, with origin/ stripped so both
# forms complete to the branch name accepted by `pwt branch`.
_pwt_all_branches() {
  _pwt_path_is_absolute || return 0
  git for-each-ref --format='%(refname)' refs/heads refs/remotes/origin 2>/dev/null |
    sed -e 's|^refs/heads/||' -e 's|^refs/remotes/origin/||' |
    grep -v '^HEAD$' |
    sort -u
}

_pwt() {
  local cur cmd flags i
  COMPREPLY=()
  cur=${COMP_WORDS[COMP_CWORD]-}
  cmd=${COMP_WORDS[1]-}

  local subcommands='new branch open pr root list remove prune install help'
  local types='feat/ fix/ refactor/ docs/ test/ chore/ perf/ style/ ci/'

  # compgen -W is safe only for literal lists declared in this file. Never add
  # Git, filesystem, network, or environment output to these calls.
  if [[ $COMP_CWORD -le 1 ]]; then
    _pwt_set_matches ' ' < <(compgen -W "$subcommands" -- "$cur")
    return 0
  fi

  # Everything after the separator belongs to Pi. Do not suggest pwt flags in
  # the forwarded argument region.
  i=2
  while [[ $i -lt $COMP_CWORD ]]; do
    [[ ${COMP_WORDS[i]} == -- ]] && return 0
    i=$((i + 1))
  done

  if [[ $cur == -* ]]; then
    case $cmd in
      pr) flags='--force' ;;
      remove) flags='--delete-branch' ;;
      prune) flags='--yes' ;;
      *) flags='' ;;
    esac
    _pwt_set_matches ' ' < <(compgen -W "$flags" -- "$cur")
    return 0
  fi

  case $cmd in
    new)
      # `new` creates a branch that does not exist yet, so complete type prefixes
      # instead of existing branch names.
      _pwt_set_matches '' < <(compgen -W "$types" -- "$cur")
      ;;
    branch)
      _pwt_add_matches "$cur" < <(_pwt_all_branches)
      ;;
    open | remove)
      _pwt_add_matches "$cur" < <(_pwt_managed_branches)
      ;;
    *)
      # pr, root, list, prune, install, and help take no completable operand.
      ;;
  esac
  return 0
}

complete -o nospace -F _pwt pwt
