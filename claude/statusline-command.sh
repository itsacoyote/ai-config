#!/usr/bin/env bash
# Claude Code status line script

set -u

# The directory may hold a repository whose config is untrusted; git_safe
# disables the config paths that can run commands.
export GIT_CONFIG_NOSYSTEM=1

input=$(cat)

# Display values are printed with %s, so terminal escape sequences in a folder
# name or model string would otherwise reach the terminal as-is.
# Also removes UTF-8 C1 controls (U+0080-U+009F) and bidi overrides
# (U+202A-U+202E, U+2066-U+2069), which tr cannot match as multibyte sequences.
strip_ctl() {
  local c2=$'\xc2' e2=$'\xe2' x80=$'\x80' x81=$'\x81'
  local x9f=$'\x9f' xa6=$'\xa6' xa9=$'\xa9' xaa=$'\xaa' xae=$'\xae'
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed \
    -e "s/${c2}[${x80}-${x9f}]//g" \
    -e "s/${e2}${x80}[${xaa}-${xae}]//g" \
    -e "s/${e2}${x81}[${xa6}-${xa9}]//g"
}

# Builds a link base from a candidate URL: drops query and fragment, removes
# userinfo (up to the last @), and emits nothing unless the host is plain.
safe_repo_url() {
  local url="$1" scheme rest
  url="${url%%#*}"
  url="${url%%\?*}"
  case "$url" in
    https://*) scheme=https ;;
    http://*) scheme=http ;;
    *) return ;;
  esac
  rest="${url#*://}"
  rest="${rest##*@}"
  printf '%s' "${rest%%/*}" | grep -Eq '^[A-Za-z0-9.-]+(:[0-9]+)?$' || return
  printf '%s://%s' "$scheme" "$rest"
}

numeric_or_empty() {
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && printf '%s' "$1"
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
used_pct=$(numeric_or_empty "$(field '.context_window.used_percentage // empty')")
five_hour_pct=$(numeric_or_empty "$(field '.rate_limits.five_hour.used_percentage // empty')")

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
  candidate="https://${repo_host}/${repo_owner}/${repo_name}"
elif [ -n "$remote" ]; then
  candidate=$(printf '%s' "$remote" | sed -E \
    -e 's#^git@([^:]+):#https://\1/#' \
    -e 's#^ssh://git@([^/]+)/#https://\1/#')
else
  candidate=""
fi
safe_base=$(safe_repo_url "$candidate")
if [ -n "$safe_base" ]; then
  pr_url=$(strip_ctl "${safe_base%.git}/pulls")
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
