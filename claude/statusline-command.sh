#!/usr/bin/env bash
# Claude Code status line script

set -u

# The directory may hold a repository whose config is untrusted; git_safe
# disables the config paths that can run commands.
export GIT_CONFIG_NOSYSTEM=1

# Display values are printed with %s, so terminal escape sequences in a folder
# name or model string would otherwise reach the terminal as-is.
# Also removes UTF-8 C1 controls (U+0080-U+009F) and bidi overrides
# (U+202A-U+202E, U+2066-U+2069), which tr cannot match as multibyte sequences.
strip_ctl() {
  local LC_ALL=C
  # Printable ASCII needs no stripping; skipping the tr/sed forks keeps the render fast.
  case "$1" in
    *[!\ -~]*) ;;
    *) printf '%s' "$1"; return ;;
  esac
  local c2=$'\xc2' e2=$'\xe2' x80=$'\x80' x81=$'\x81'
  local x9f=$'\x9f' xa6=$'\xa6' xa9=$'\xa9' xaa=$'\xaa' xae=$'\xae'
  # Loops until nothing matches: removing one sequence can join the bytes around
  # it into a new one (c2 [c2 9b] 9b -> c2 9b).
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed \
    -e ':a' \
    -e "s/${c2}[${x80}-${x9f}]//g" \
    -e "s/${e2}${x80}[${xaa}-${xae}]//g" \
    -e "s/${e2}${x81}[${xa6}-${xa9}]//g" \
    -e 'ta'
}

AUTHORITY_RE='^[A-Za-z0-9.-]+(:[0-9]+)?$'
# Builds a link base from a candidate URL: removes userinfo from the authority,
# drops query and fragment from the path, and emits nothing unless the host is
# plain and the path has no @.
safe_repo_url() {
  local url="$1" scheme rest authority path
  case "$url" in
    https://*) scheme=https ;;
    http://*) scheme=http ;;
    *) return ;;
  esac
  rest="${url#*://}"
  authority="${rest%%/*}"
  path="${rest#"$authority"}"
  authority="${authority##*@}"
  path="${path%%[?#]*}"
  # An @ after the first / is either a password containing a slash or a path
  # pretending to be a host; neither yields a link worth the risk.
  case "$path" in *@*) return ;; esac
  [[ $authority =~ $AUTHORITY_RE ]] || return
  printf '%s://%s%s' "$scheme" "$authority" "$path"
}

NUMERIC_RE='^[0-9]+(\.[0-9]+)?$'
numeric_or_empty() {
  [[ $1 =~ $NUMERIC_RE ]] && printf '%s' "$1"
}

git_safe() {
  git -C "$dir" -c core.fsmonitor=false -c core.hooksPath=/dev/null --no-optional-locks "$@"
}

CACHE_DIR="${HOME:-}/.cache/claude-statusline"
PR_FIELDS='number,url,state,author,reviewDecision,reviews'
PR_NUMBER_RE='^[0-9]+$'
PR_URL_RE='^https://[A-Za-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$'
PR_STATE_RE='^(OPEN|MERGED)$'
PR_CODE_RE='^(approved|changes|commented|merged|none)$'
EPOCH_RE='^[1-9][0-9]{0,11}$'
# The brackets admit bot logins such as dependabot[bot].
LOGIN_RE='^[A-Za-z0-9][][A-Za-z0-9_.-]*$'
VIEWER_TTL=86400

# gh runs inside a repository whose config is untrusted, and shells out to git.
# The enterprise token variables are dropped so a hostile host in a request
# cannot receive them; gh still uses its stored per-host credentials.
run_gh() {
  (
    cd "$top" || exit 1
    unset GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GH_PAGER=cat NO_COLOR=1 \
    GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false \
    GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
      gh "$@" 2>/dev/null
  )
}

# Refuses a destination that is not a regular file: mv would move the
# temp file into a directory, or through a symlink.
atomic_write() {
  local dest="$1" tmp
  tmp=$(mktemp "$CACHE_DIR/.tmp.XXXXXX") || return 1
  if { [ ! -e "$dest" ] && [ ! -L "$dest" ]; } || { [ -f "$dest" ] && [ ! -L "$dest" ]; }; then
    printf '%s\n' "$2" >"$tmp" && mv -f "$tmp" "$dest" && return 0
  fi
  rm -f "$tmp"
  return 1
}

# A host is trusted when gh already knows it: github.com or a top-level key
# of gh's hosts.yml.
host_allowed() {
  local host="$1" hosts_file line
  [ "$host" = github.com ] && return 0
  hosts_file="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/gh}/hosts.yml"
  [ -f "$hosts_file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ ^[A-Za-z0-9.-]+:$ ]] && [ "${line%:}" = "$host" ] && return 0
  done <"$hosts_file"
  return 1
}

viewer_login() {
  local host="$1" file v_epoch="" v_login="" login
  file="$CACHE_DIR/viewer.$host"
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    IFS=$'\t' read -r v_epoch v_login <"$file"
    if [[ $v_epoch =~ $EPOCH_RE ]] && [[ $v_login =~ $LOGIN_RE ]] &&
       [ $((now - v_epoch)) -ge 0 ] && [ $((now - v_epoch)) -lt "$VIEWER_TTL" ]; then
      printf '%s' "$v_login"
      return 0
    fi
  fi
  login=$(run_gh api --hostname "$host" user --jq .login) || return 1
  [[ $login =~ $LOGIN_RE ]] || return 1
  atomic_write "$file" "$now"$'\t'"$login" || return 1
  printf '%s' "$login"
}

# reviews, not latestReviews: latestReviews lets a later COMMENTED review
# replace an APPROVED one. reviewDecision is "" (not null) when there is none.
REVIEW_CODE_JQ='
  ((.author.login // "") | ascii_downcase) as $author
  | ($v | ascii_downcase) as $viewer
  | [.reviews[]? | {who: ((.author.login // "") | ascii_downcase), state: .state}] as $rv
  | if $author == $viewer then
      if .reviewDecision == "APPROVED" then "approved"
      elif .reviewDecision == "CHANGES_REQUESTED" then "changes"
      elif ([$rv[] | select(.state == "COMMENTED" and .who != $author)] | length) > 0 then "commented"
      else "none" end
    else
      [$rv[] | select(.who == $viewer)] as $mine
      | ([$mine[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")] | last | .state) as $last
      | if $last == "APPROVED" then "approved"
        elif $last == "CHANGES_REQUESTED" then "changes"
        elif ([$mine[] | select(.state == "COMMENTED")] | length) > 0 then "commented"
        else "none" end
    end'

# The target of refs/remotes/origin/HEAD, else main or master when it is absent.
is_default_branch() {
  local default
  default=$(git_safe symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  default="${default#origin/}"
  if [ -z "$default" ]; then
    case "$branch" in main|master) return 0 ;; esac
    return 1
  fi
  [ "$branch" = "$default" ]
}

ensure_cache_dir() {
  [ -n "${HOME:-}" ] || return 1
  [ -L "$CACHE_DIR" ] && return 1
  mkdir -p "$CACHE_DIR" && chmod 700 "$CACHE_DIR" && [ -O "$CACHE_DIR" ]
}

# Sets pr_number/pr_url/pr_state/pr_code, all empty meaning no PR. Returns 1
# when gh could not answer, so the caller keeps the previous cache fields.
lookup_pr() {
  local marker merge json number url host viewer code state want_host=""
  pr_number=""; pr_url=""; pr_state=""; pr_code=""

  is_default_branch && return 0

  command -v gh >/dev/null 2>&1 || return 0

  marker=$(git_safe config --get "branch.$branch.worktree-pr-url" 2>/dev/null)
  merge=$(git_safe config --get "branch.$branch.merge" 2>/dev/null)
  if [[ $marker =~ $PR_URL_RE ]] && want_host="${marker#https://}" && want_host="${want_host%%/*}" &&
     host_allowed "$want_host"; then
    json=$(run_gh pr view "$marker" --json "$PR_FIELDS") || return 1
  elif [[ $merge =~ ^refs/pull/([0-9]+)/head$ ]]; then
    want_host=""
    json=$(run_gh pr view "${BASH_REMATCH[1]}" --json "$PR_FIELDS") || return 1
  else
    want_host=""
    json=$(run_gh pr list --head "$branch" --state all --json "$PR_FIELDS" --limit 10) || return 1
    json=$(printf '%s' "$json" | jq -c '
      [.[] | select(.state == "OPEN")][0]
      // ([.[] | select(.state == "MERGED")] | sort_by(.number) | last)' 2>/dev/null) || return 1
  fi

  [ "$json" = null ] && return 0
  printf '%s' "$json" | jq -e 'type == "object"' >/dev/null 2>&1 || return 1

  state=$(printf '%s' "$json" | jq -r '.state // ""')
  [[ $state =~ $PR_STATE_RE ]] || return 0
  number=$(printf '%s' "$json" | jq -r '.number | tostring')
  url=$(printf '%s' "$json" | jq -r '.url // ""')
  [[ $number =~ $PR_NUMBER_RE ]] && [[ $url =~ $PR_URL_RE ]] || return 0
  [ "${url##*/pull/}" = "$number" ] || return 0

  host="${url#https://}"
  host="${host%%/*}"
  host_allowed "$host" || return 0
  [ -z "$want_host" ] || [ "$host" = "$want_host" ] || return 0

  if [ "$state" = MERGED ]; then
    code=merged
  else
    viewer=$(viewer_login "$host") || return 1
    code=$(printf '%s' "$json" | jq -r --arg v "$viewer" "$REVIEW_CODE_JQ" 2>/dev/null) || return 1
    [[ $code =~ $PR_CODE_RE ]] || return 1
  fi

  pr_number="$number"; pr_url="$url"; pr_state="$state"; pr_code="$code"
}

write_pr_line() {
  if [ -n "$pr_number" ]; then
    atomic_write "$cache_file" "$now"$'\t'"$pr_number"$'\t'"$pr_state"$'\t'"$pr_code"$'\t'"$pr_url"
  else
    atomic_write "$cache_file" "$now"$'\tNONE'
  fi
}

# The cache line is untrusted: it is read as tab-separated text, never sourced
# or evaluated, and every field is validated. Sets p_epoch, and p_number,
# p_state, p_code and p_url only when they form a consistent PR record; all are
# empty otherwise. Returns 0 when the epoch is valid.
parse_pr_line() {
  local LC_ALL=C
  p_epoch=""; p_number=""; p_state=""; p_code=""; p_url=""
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  IFS=$'\t' read -r p_epoch p_number p_state p_code p_url <"$1"
  if ! [[ $p_epoch =~ $EPOCH_RE ]]; then
    p_epoch=""; p_number=""; p_state=""; p_code=""; p_url=""
    return 1
  fi
  if [[ $p_number =~ $PR_NUMBER_RE ]] && [[ $p_state =~ $PR_STATE_RE ]] &&
     [[ $p_code =~ $PR_CODE_RE ]] && [[ $p_url =~ $PR_URL_RE ]] &&
     [ "${p_url##*/pull/}" = "$p_number" ] &&
     { { [ "$p_state" = MERGED ] && [ "$p_code" = merged ]; } ||
       { [ "$p_state" = OPEN ] && [ "$p_code" != merged ]; }; }; then
    return 0
  fi
  p_number=""; p_state=""; p_code=""; p_url=""
  return 0
}

keep_previous_line() {
  local p_epoch p_number p_state p_code p_url
  parse_pr_line "$cache_file"
  pr_number="$p_number"; pr_state="$p_state"; pr_code="$p_code"; pr_url="$p_url"
  write_pr_line
}

# Removes the lock only while it still holds this process's PID: a render may
# have replaced it as stale while this refresher was still running.
release_lock() {
  local owner=""
  [ -f "$refresh_lock/pid" ] && read -r owner <"$refresh_lock/pid"
  [ "$owner" = "$$" ] && rm -rf "$refresh_lock"
}

# --refresh <repo toplevel> <branch> <cache file>
# The helpers above read these through dynamic scope: top, branch, cache_file,
# now, and dir (for git_safe); they set pr_number, pr_url, pr_state, pr_code.
refresh_main() {
  local top="$1" branch="$2" cache_file="$3" now
  local pr_number pr_url pr_state pr_code
  export LC_ALL=C

  [ -n "${HOME:-}" ] || return 1
  [ "${cache_file%/*}" = "$CACHE_DIR" ] || return 1
  [[ ${cache_file##*/} =~ ^k-[0-9a-f]{64}$ ]] || return 1

  # A global, not a local: the EXIT trap runs after this function has returned.
  refresh_lock="$cache_file.lock"
  [ -d "$refresh_lock" ] && printf '%s\n' "$$" >"$refresh_lock/pid"
  trap 'release_lock' EXIT

  case "$top" in /*) ;; *) return 1 ;; esac
  [ -d "$top" ] || return 1
  [ -n "$branch" ] && [ "${branch#-}" = "$branch" ] || return 1
  ensure_cache_dir || return 1

  dir="$top"
  now=$(date +%s)
  # A failed write keeps the lock so the two-minute stale rule limits retries.
  if lookup_pr; then
    write_pr_line
  else
    keep_previous_line
  fi || { trap - EXIT; return 1; }
}

# Sets shown_* from a valid cache line and returns 0 only when the cache is
# fresh (not older than 60s, not in the future).
read_pr_cache() {
  local p_epoch p_number p_state p_code p_url age
  parse_pr_line "$cache_file" || return 1
  shown_number="$p_number"; shown_url="$p_url"; shown_code="$p_code"
  age=$(($(date +%s) - p_epoch))
  [ "$age" -ge 0 ] && [ "$age" -le 60 ]
}

# A lock directory older than two minutes belongs to a dead refresher. Renaming
# it first lets only one render win the replacement.
take_lock() {
  local lock="$1" stale="$1.stale.$$"
  mkdir "$lock" 2>/dev/null && return 0
  [ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ] || return 1
  mv "$lock" "$stale" 2>/dev/null || return 1
  if [ -z "$(find "$stale" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    # Another render refreshed the lock after the check: put it back. mv would
    # nest the directory inside a lock that has been recreated since.
    if [ -e "$lock" ]; then rm -rf "$stale"; else mv "$stale" "$lock" 2>/dev/null || rm -rf "$stale"; fi
    return 1
  fi
  rm -rf "$stale"
  mkdir "$lock" 2>/dev/null
}

# set -m runs the refresher in its own process group, and the subshell keeps
# job control (and bash 3.2's "Done" notice) away from the rest of the script.
start_refresh() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in /*) ;; *) self="$PWD/$self" ;; esac
  ensure_cache_dir || return 1
  take_lock "$cache_file.lock" || return 1
  ( set -m; nohup bash "$self" --refresh "$toplevel" "$branch" "$cache_file" </dev/null >/dev/null 2>&1 & )
}

if [ "${1:-}" = "--refresh" ]; then
  refresh_main "${2:-}" "${3:-}" "${4:-}"
  exit $?
fi

input=$(cat)

# One jq call for every field. The separator is \037, not a tab: a whitespace
# IFS character would collapse empty fields and shift the ones after them.
IFS=$'\037' read -r -d '' model effort dir repo_host repo_owner repo_name used_raw five_raw < <(
  # try per field: one value of an unexpected type must blank only that field.
  printf '%s' "$input" | jq -j '[
      ((try .model.display_name catch null) // "Unknown Model"),
      ((try .effort.level catch null) // ""),
      ((try (.workspace.current_dir // .workspace.project_dir) catch null) // ""),
      ((try .workspace.repo.host catch null) // ""),
      ((try .workspace.repo.owner catch null) // ""),
      ((try .workspace.repo.name catch null) // ""),
      ((try .context_window.used_percentage catch null) // ""),
      ((try .rate_limits.five_hour.used_percentage catch null) // "")
    ] | map(tostring | gsub("[\u0000\u001f]"; "")) | join("\u001f")' 2>/dev/null
)
model=$(strip_ctl "$model")
effort=$(strip_ctl "$effort")
repo_host=$(strip_ctl "$repo_host")
repo_owner=$(strip_ctl "$repo_owner")
repo_name=$(strip_ctl "$repo_name")
used_pct=$(numeric_or_empty "$used_raw")
five_hour_pct=$(numeric_or_empty "$five_raw")

project_name=""
branch=""
worktree_name=""
remote=""
toplevel=""
common_dir=""

if [ -n "$dir" ]; then
  project_name=$(basename "$dir")
  git_dir=""
  paths=$(git_safe rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir 2>/dev/null)
  # Exactly three lines; a path containing a newline would shift the others.
  case "$paths" in
    *$'\n'*$'\n'*$'\n'*) paths="" ;;
    *$'\n'*$'\n'*) ;;
    *) paths="" ;;
  esac
  { IFS= read -r toplevel; IFS= read -r git_dir; IFS= read -r common_dir; } <<EOF
$paths
EOF
  if [ -n "$toplevel" ]; then

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

shown_number=""; shown_url=""; shown_code=""
if [ -n "$toplevel" ] && [ -n "$common_dir" ] && [ -n "$branch" ] && [ "${branch#-}" = "$branch" ] && [ -n "${HOME:-}" ] && ! is_default_branch; then
  key=$(printf '%s\n%s' "$common_dir" "$branch" | shasum -a 256)
  key="${key%% *}"
  if [[ $key =~ ^[0-9a-f]{64}$ ]]; then
    cache_file="$CACHE_DIR/k-$key"
    read_pr_cache || start_refresh
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
pulls_url=""
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
  pulls_url=$(strip_ctl "${safe_base%.git}/pulls")
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

if [ -n "$shown_number" ]; then
  printf ' %b|%b ' "$DIM" "$RESET"
  hyperlink "$shown_url" "PR #$shown_number"
  case "$shown_code" in
    approved)  printf ' ✅' ;;
    changes)   printf ' 🔴' ;;
    commented) printf ' 💬' ;;
    merged)    printf ' 🟣' ;;
  esac
fi

printf '\n'

if [ -n "$project_name" ]; then
  printf '📁 %b' "${BOLD}${CYAN}"
  if [ -n "$pulls_url" ]; then
    hyperlink "$pulls_url" "$project_name"
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
