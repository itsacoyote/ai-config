#!/usr/bin/env bash
# Claude Code status line script

set -u

# The directory comes from session JSON and may be a repository whose own
# config this script has never vetted; see git_safe.
export GIT_CONFIG_NOSYSTEM=1

input=$(cat)

# Display values are printed with %s, so terminal escape sequences in a folder
# name or model string would otherwise reach the terminal as-is.
strip_ctl() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'
}

field() {
  printf '%s' "$input" | jq -r "$1" 2>/dev/null
}

git_safe() {
  git -C "$dir" -c core.fsmonitor=false -c core.hooksPath=/dev/null --no-optional-locks "$@"
}

model=$(strip_ctl "$(field '.model.display_name // "Unknown Model"')")
effort=$(strip_ctl "$(field '.effort.level // ""')")
dir=$(field '.workspace.current_dir // .workspace.project_dir // ""')
repo_host=$(strip_ctl "$(field '.workspace.repo.host // empty')")
repo_owner=$(strip_ctl "$(field '.workspace.repo.owner // empty')")
repo_name=$(strip_ctl "$(field '.workspace.repo.name // empty')")
used_pct=$(field '.context_window.used_percentage // empty')
five_hour_pct=$(field '.rate_limits.five_hour.used_percentage // empty')

project_name=""
branch=""
worktree_name=""
remote=""

if [ -n "$dir" ]; then
  project_name=$(basename "$dir")
  toplevel=$(git_safe rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$toplevel" ]; then
    git_dir=$(git_safe rev-parse --path-format=absolute --git-dir 2>/dev/null)
    common_dir=$(git_safe rev-parse --path-format=absolute --git-common-dir 2>/dev/null)

    # A linked worktree's toplevel is the worktree folder, so the primary
    # checkout's name has to come from the shared git directory.
    if [ "$(basename "$common_dir")" = ".git" ]; then
      project_name=$(basename "$(dirname "$common_dir")")
    else
      project_name=$(basename "$toplevel")
    fi

    branch=$(git_safe symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$git_dir" ] && [ "$git_dir" != "$common_dir" ]; then
      worktree_name=$(basename "$toplevel")
      if [ "$worktree_name" = "$branch" ] || [ "$worktree_name" = "${branch//\//-}" ]; then
        worktree_name=""
      fi
    fi
    remote=$(git_safe remote get-url origin 2>/dev/null)
  fi
fi

project_name=$(strip_ctl "$project_name")
branch=$(strip_ctl "$branch")
worktree_name=$(strip_ctl "$worktree_name")

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'

hyperlink() {
  printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"
}

# The JSON repo fields are often absent, so the git remote is the fallback.
pr_url=""
if [ -n "$repo_host" ] && [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
  pr_url="https://${repo_host}/${repo_owner}/${repo_name}/pulls"
elif [ -n "$remote" ]; then
  base=$(printf '%s' "$remote" | sed -E \
    -e 's#^git@([^:]+):#https://\1/#' \
    -e 's#^ssh://git@([^/]+)/#https://\1/#' \
    -e 's#^(https?://)[^/]*@#\1#' \
    -e 's#\.git$##')
  case "$base" in
    https://*|http://*) pr_url=$(strip_ctl "${base}/pulls") ;;
  esac
fi

effort_color="$DIM"
case "$effort" in
  low)   effort_color="$GREEN"   ;;
  medium) effort_color="$YELLOW" ;;
  high)  effort_color="$MAGENTA" ;;
  xhigh|max) effort_color="$RED" ;;
esac

colored_pct() {
  local pct_raw="$1"
  local label="$2"

  if [ -z "$pct_raw" ]; then
    printf '%b--%% %s%b' "$DIM" "$label" "$RESET"
    return
  fi

  local pct_int
  pct_int=$(printf '%.0f' "$pct_raw")

  local color
  if [ "$pct_int" -ge 90 ]; then
    color="$RED"
  elif [ "$pct_int" -ge 70 ]; then
    color="$YELLOW"
  else
    color="$GREEN"
  fi

  printf '%b%s%%%b %b%s%b' "$color" "$pct_int" "$RESET" "$DIM" "$label" "$RESET"
}

printf '%b%s%b' "$DIM" "$model" "$RESET"

if [ -n "$effort" ]; then
  printf ' %b%s%b' "$effort_color" "$effort" "$RESET"
fi

printf ' %b|%b ' "$DIM" "$RESET"
colored_pct "$used_pct" "ctx"

if [ -n "$five_hour_pct" ]; then
  printf ' %b|%b ' "$DIM" "$RESET"
  colored_pct "$five_hour_pct" "5h"
fi

printf '\n'

if [ -n "$project_name" ]; then
  printf '📁 %b' "${BOLD}${CYAN}"
  if [ -n "$pr_url" ]; then
    hyperlink "$pr_url" "$project_name"
  else
    printf '%s' "$project_name"
  fi
  printf '%b' "$RESET"
fi

if [ -n "$branch" ]; then
  printf ' %b|%b 🌿 %b%s%b' "$DIM" "$RESET" "$DIM" "$branch" "$RESET"
fi

if [ -n "$worktree_name" ]; then
  printf ' %b|%b %b%s%b' "$DIM" "$RESET" "$DIM" "$worktree_name" "$RESET"
fi

printf '\n'
