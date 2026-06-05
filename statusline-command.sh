#!/usr/bin/env bash
# Claude Code status line script

input=$(cat)

# --- Extract fields ---
model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // ""')
project_name=$(basename "$project_dir")
repo_host=$(echo "$input" | jq -r '.workspace.repo.host // empty')
repo_owner=$(echo "$input" | jq -r '.workspace.repo.owner // empty')
repo_name=$(echo "$input" | jq -r '.workspace.repo.name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# --- Git branch (skip optional locks) ---
branch=""
if [ -n "$project_dir" ]; then
  branch=$(git -C "$project_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# --- ANSI colors ---
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
WHITE='\033[37m'
MAGENTA='\033[35m'

# --- OSC 8 hyperlink helper ---
# hyperlink TEXT URL
hyperlink() {
  local text="$1"
  local url="$2"
  printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$text"
}

# --- Resolve the repo's PR page URL ---
# Prefer the JSON repo fields; fall back to the git remote (the JSON fields are
# often absent, in which case there'd be no link at all without this fallback).
pr_url=""
if [ -n "$repo_host" ] && [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
  pr_url="https://${repo_host}/${repo_owner}/${repo_name}/pulls"
elif [ -n "$project_dir" ]; then
  remote=$(git -C "$project_dir" --no-optional-locks remote get-url origin 2>/dev/null)
  if [ -n "$remote" ]; then
    # Normalize SSH/HTTPS remotes to an https base, strip a trailing .git
    base=$(printf '%s' "$remote" | sed -E \
      -e 's#^git@([^:]+):#https://\1/#' \
      -e 's#^ssh://git@([^/]+)/#https://\1/#' \
      -e 's#\.git$##')
    case "$base" in
      https://*|http://*) pr_url="${base}/pulls" ;;
    esac
  fi
fi

# --- Effort color: low=green, medium=yellow, high=magenta, xhigh=red ---
effort_color="$DIM"
case "$effort" in
  low)   effort_color="$GREEN"   ;;
  medium) effort_color="$YELLOW" ;;
  high)  effort_color="$MAGENTA" ;;
  xhigh|max) effort_color="$RED" ;;
esac

# --- Colored percentage (no bar) ---
# colored_pct PCT LABEL  -> "NN% label" colored by threshold, or "--% label" when no data
colored_pct() {
  local pct_raw="$1"
  local label="$2"

  if [ -z "$pct_raw" ]; then
    printf '%b' "${DIM}--% ${label}${RESET}"
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

  printf '%b' "${color}${pct_int}%${RESET} ${DIM}${label}${RESET}"
}

# --- Line 1: model [effort] | ctx% | 5h% ---
printf '%b' "${DIM}${model}${RESET}"

if [ -n "$effort" ]; then
  printf '%b' " ${effort_color}${effort}${RESET}"
fi

# context window (always shown)
printf '%b' " ${DIM}|${RESET} "
colored_pct "$used_pct" "ctx"

# 5-hour rate limit (when available)
if [ -n "$five_hour_pct" ]; then
  printf '%b' " ${DIM}|${RESET} "
  colored_pct "$five_hour_pct" "5h"
fi

printf '\n'

# --- Line 2: project (linked to its PR page) | branch ---
if [ -n "$project_name" ]; then
  if [ -n "$pr_url" ]; then
    printf '%b' "${BOLD}${CYAN}"
    hyperlink "$project_name" "$pr_url"
    printf '%b' "${RESET}"
  else
    printf '%b' "${BOLD}${CYAN}${project_name}${RESET}"
  fi
fi

if [ -n "$branch" ]; then
  printf '%b' " ${DIM}|${RESET} ${DIM}${branch}${RESET}"
fi

printf '\n'
