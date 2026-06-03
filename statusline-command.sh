#!/usr/bin/env bash
# Claude Code status line script

input=$(cat)

# --- Extract fields ---
model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // ""')
thinking=$(echo "$input" | jq -r '.thinking.enabled // false')
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

# --- Effort color: low=green, medium=yellow, high=magenta, xhigh=red ---
effort_color="$DIM"
case "$effort" in
  low)   effort_color="$GREEN"   ;;
  medium) effort_color="$YELLOW" ;;
  high)  effort_color="$MAGENTA" ;;
  xhigh|max) effort_color="$RED" ;;
esac

# --- Line 1: model [effort] | project (linked) | branch ---
printf '%b' "${DIM}${model}${RESET}"

if [ -n "$effort" ]; then
  printf '%b' " ${effort_color}${effort}${RESET}"
fi

if [ "$thinking" = "true" ]; then
  printf '%b' " ${DIM}~thinking${RESET}"
fi

if [ -n "$project_name" ]; then
  printf '%b' " ${DIM}|${RESET} "
  if [ -n "$repo_host" ] && [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
    pr_url="https://${repo_host}/${repo_owner}/${repo_name}/pulls"
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

# --- Progress bar builder ---
# build_bar PCT [label]  -> prints a 20-char filled bar with color
build_bar() {
  local pct_raw="$1"
  local label="$2"
  local bar_width=20

  # No data yet — show a grey placeholder bar
  if [ -z "$pct_raw" ]; then
    local bar_empty=""
    local i
    for (( i=0; i<bar_width; i++ )); do bar_empty="${bar_empty}░"; done
    printf '%b' "${DIM}${bar_empty}${RESET}"
    if [ -n "$label" ]; then
      printf '%b' " ${DIM}${label}${RESET}"
    fi
    return
  fi

  local pct_int
  pct_int=$(printf '%.0f' "$pct_raw")

  # Choose color
  local color
  if [ "$pct_int" -ge 90 ]; then
    color="$RED"
  elif [ "$pct_int" -ge 70 ]; then
    color="$YELLOW"
  else
    color="$GREEN"
  fi

  # Filled and empty cells
  local filled=$(( pct_int * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  local empty=$(( bar_width - filled ))

  local bar_filled=""
  local bar_empty=""
  local i
  for (( i=0; i<filled; i++ )); do bar_filled="${bar_filled}█"; done
  for (( i=0; i<empty; i++ )); do bar_empty="${bar_empty}░"; done

  printf '%b' "${color}${bar_filled}${DIM}${bar_empty}${RESET}"
  printf '%b' " ${color}${pct_int}%${RESET}"
  if [ -n "$label" ]; then
    printf '%b' " ${DIM}${label}${RESET}"
  fi
}

# --- Line 2: context bar (always shown) | rate limit ---
ctx_part=$(build_bar "$used_pct" "ctx")
line2="${ctx_part}"

if [ -n "$five_hour_pct" ]; then
  pct_int=$(printf '%.0f' "$five_hour_pct")
  if [ "$pct_int" -ge 90 ]; then
    rate_color="$RED"
  elif [ "$pct_int" -ge 70 ]; then
    rate_color="$YELLOW"
  else
    rate_color="$GREEN"
  fi
  rate_part=$(printf '%b' "${rate_color}${pct_int}%${RESET} ${DIM}5h${RESET}")
  line2="${line2}$(printf '%b' "  ${DIM}|${RESET}  ")${rate_part}"
fi

printf '%b\n' "$line2"
