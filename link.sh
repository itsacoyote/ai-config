#!/usr/bin/env bash
# link.sh — link this config library into the harness homes instead of copying it.
#
# Symlinks every top-level entry of the repo's harness trees, and of a private
# directory with the same layout (~/.ai-private), into ~/.claude, ~/.agents/skills,
# ~/.codex, and ~/.pi/agent. Links replace copies so that `git pull` on main is the
# update: a copied file goes stale the moment the repo moves on, a link cannot.
#
# Inside the managed directories everything the script did not link is deleted,
# except a short allowlist of harness-owned entries. The plan is computed before
# anything is written; --dry-run prints it, including every deletion. Settings
# files, config.toml, and auth files are never touched (ADR 0013).
#
# Run this yourself, not through an agent: the harness homes are human-owned, and
# links point into THIS checkout, so run it from the primary checkout on main.
#
# Usage:
#   bash link.sh             link, clean, and install the worktree CLIs
#   bash link.sh --dry-run   print the full plan, write nothing

set -euo pipefail
# Nothing here globs; entry names come from find. Off, so an unquoted word-split
# loop can never expand a name into a pattern.
set -f

die()  { printf 'link.sh: %s\n' "$*" >&2; exit 2; }
note() { printf '%s\n' "$*"; }
warn() { printf 'link.sh: warning: %s\n' "$*" >&2; }

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
}

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

# Physical path of the checkout this script lives in, never $PWD: the maintainer
# runs tooling from wherever the shell happens to be.
REPO="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_P="$(cd "$HOME" && pwd -P)"

# ------------------------------------------------------------------ guards

# The links point into $REPO, so the repo must be the thing that stays put.
for root in claude agents/skills pi/AGENTS.md codex/rules/ai-config.rules; do
  [ -e "$REPO/$root" ] || die "missing source root $REPO/$root — run from a complete checkout"
done

# A copy of this script living inside a harness home would link the homes to
# themselves. Compare physical to physical: $REPO is resolved, so an unresolved
# home (itself a symlink) would never match and the guard would pass exactly
# where it matters.
for home in .claude .agents .codex .pi; do
  home_p="$(cd "$HOME/$home" 2>/dev/null && pwd -P)" || home_p="$HOME_P/$home"
  case "$REPO/" in
    "$home_p"/*) die "refusing to run from inside $HOME/$home — run from the repository checkout" ;;
  esac
done

# Primary-checkout guard. `git worktree remove` on a linked worktree would leave
# every link dangling, so links may only point into the primary checkout. In a
# primary checkout the common dir IS $REPO/.git; in a linked worktree it is the
# primary's .git elsewhere. Compare physical absolute paths: git prints the
# relative string ".git" for a primary checkout, and comparing that against an
# absolute path would fail exactly where the script is allowed to run.
common_dir="$(cd "$REPO" && git rev-parse --git-common-dir 2>/dev/null)" || common_dir=''
if [ -z "$common_dir" ]; then
  warn "$REPO is not a git repository; skipping the primary-checkout check"
else
  case "$common_dir" in
    /*) ;;
    *) common_dir="$REPO/$common_dir" ;;
  esac
  common_p="$(cd -P "$common_dir" && pwd -P)"
  if [ -d "$REPO/.git" ]; then
    own_p="$(cd -P "$REPO/.git" && pwd -P)"
  else
    own_p=''
  fi
  if [ "$common_p" != "$own_p" ]; then
    die "refusing to run from a linked worktree ($REPO) — run from the primary checkout: $(dirname "$common_p")"
  fi
fi

# -------------------------------------------------------------------- plan
#
# Every action is classified before anything is written, in dry-run and real mode
# alike, so the printed plan is the whole plan and a fatal entry stops the run
# with nothing changed. Classes: delete, link, repoint, replace, unchanged, FATAL.
# Within one managed directory the deletes are planned before the links, and the
# apply loop runs the plan in order, so a hook path is never absent for longer
# than the gap between two consecutive commands.

PLAN_CLASS=()
PLAN_SRC=()
PLAN_DST=()
PLAN_WHY=()
fatal_count=0

add_plan() {
  PLAN_CLASS[${#PLAN_CLASS[@]}]="$1"
  PLAN_SRC[${#PLAN_SRC[@]}]="$2"
  PLAN_DST[${#PLAN_DST[@]}]="$3"
  PLAN_WHY[${#PLAN_WHY[@]}]="${4:-}"
  [ "$1" = FATAL ] && fatal_count=$((fatal_count + 1))
  return 0
}

is_planned_delete() {
  local i=0
  while [ "$i" -lt "${#PLAN_CLASS[@]}" ]; do
    [ "${PLAN_CLASS[$i]}" = delete ] && [ "${PLAN_DST[$i]}" = "$1" ] && return 0
    i=$((i + 1))
  done
  return 1
}

# Walk the target path from $HOME down through every existing PARENT component.
# A symlinked component that resolves outside the physical home would redirect
# the write somewhere the script has no business touching. readlink -f and
# realpath are avoided on purpose: this library lands on machines we do not
# control, and stock macOS shipped without them for years.
contained_reason() {
  local target="$1" rel cursor="$HOME" component parent resolved old_ifs
  case "$target" in
    "$HOME"/*) rel="${target#"$HOME"/}" ;;
    *) printf 'target is outside HOME'; return ;;
  esac
  parent="$(dirname "$rel")"
  [ "$parent" = . ] && return
  old_ifs="$IFS"; IFS='/'
  for component in $parent; do
    IFS="$old_ifs"
    cursor="$cursor/$component"
    if [ -L "$cursor" ]; then
      resolved="$(cd -P "$cursor" 2>/dev/null && pwd -P)" || { printf 'parent %s is a dangling symlink' "$cursor"; return; }
      case "$resolved/" in
        "$HOME_P"/*) ;;
        *) printf 'parent %s resolves outside HOME (%s)' "$cursor" "$resolved"; return ;;
      esac
    elif [ -e "$cursor" ] && [ ! -d "$cursor" ]; then
      printf 'parent %s is not a directory' "$cursor"; return
    fi
    IFS='/'
  done
  IFS="$old_ifs"
}

# plan_entry SOURCE TARGET — classify one desired symlink and record it.
plan_entry() {
  local src="$1" dst="$2" why current
  why="$(contained_reason "$dst")"
  if [ -n "$why" ]; then
    add_plan FATAL "$src" "$dst" "$why"
  elif is_planned_delete "$dst"; then
    add_plan link "$src" "$dst"
  elif [ -L "$dst" ]; then
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      add_plan unchanged "$src" "$dst"
    else
      add_plan repoint "$src" "$dst"
    fi
  elif [ -d "$dst" ]; then
    add_plan FATAL "$src" "$dst" 'a real directory is in the way'
  elif [ -e "$dst" ]; then
    if [ -f "$dst" ] && [ -f "$src" ] && cmp -s "$src" "$dst"; then
      add_plan replace "$src" "$dst"
    else
      add_plan FATAL "$src" "$dst" 'a real file with different contents is in the way'
    fi
  else
    add_plan link "$src" "$dst"
  fi
}

# Top-level names of a directory. find sees dot entries; the repo's placeholder
# .gitkeep files and Finder's .DS_Store are not library content. Entries are
# NUL-delimited: a name containing a newline would otherwise be read as two
# names, the second a bare relative path.
names_in() {
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z | while IFS= read -r -d '' entry; do
    case "$(basename "$entry")" in
      .gitkeep|.DS_Store) ;;
      *) basename "$entry" ;;
    esac
  done
}

CLAUDE_DIRS='skills agents rules references scripts hooks'

# Second source root with the same layout. A name present in both roots is a hard
# error rather than an override: which one wins would depend on plan order, and
# a private copy of a library skill is exactly the drift this script removes.
PRIVATE="$HOME/.ai-private"

check_conflicts() {
  local d rel conflicts='' name
  for d in $CLAUDE_DIRS; do
    rel="claude/$d"
    while IFS= read -r name; do
      [ -n "$name" ] && conflicts="$conflicts  $rel/$name"$'\n'
    done < <(comm -12 <(names_in "$REPO/$rel") <(names_in "$PRIVATE/$rel"))
  done
  while IFS= read -r name; do
    [ -n "$name" ] && conflicts="$conflicts  agents/skills/$name"$'\n'
  done < <(comm -12 <(names_in "$REPO/agents/skills") <(names_in "$PRIVATE/agents/skills"))
  if [ -n "$conflicts" ]; then
    printf 'link.sh: the same name exists in %s and %s:\n%s' "$REPO" "$PRIVATE" "$conflicts" >&2
    die "conflict between the repo and the private directory; nothing written"
  fi
}

if [ -d "$PRIVATE" ]; then
  check_conflicts
else
  note "private directory $PRIVATE not found; linking the repo only"
fi

# Harness-owned entries inside managed directories that the clean must keep.
# Compared by literal path under $HOME. Keep this list short: anything else in a
# managed directory belongs to the repo or the private directory.
ALLOWLIST="$HOME/.claude/skills/synced
$HOME/.codex/rules/default.rules"

is_allowlisted() {
  printf '%s\n' "$ALLOWLIST" | grep -qxF -- "$1"
}

# Hook names registered in either settings file. Read-only: the settings files
# are never edited (ADR 0013). A substring scan is enough here because a false
# positive can only protect an entry that exists and would otherwise be deleted.
registered_hooks=''
for settings_file in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"; do
  [ -f "$settings_file" ] || continue
  # `|| :` because under pipefail a settings file with no hook is a grep exit 1,
  # which would end the run here with no message.
  registered_hooks="$registered_hooks$(grep -o 'hooks/[A-Za-z0-9_.-]*\.sh' "$settings_file" | sed 's#^hooks/##' || :)"$'\n'
done

is_registered_hook() {
  printf '%s\n' "$registered_hooks" | grep -qxF -- "$1"
}

# plan_clean MANAGED_DIR DESIRED_NAMES — every entry that is not a desired-name
# symlink and not allowlisted is an extra and is planned for deletion. A real file
# or directory with a desired name is an extra too: the copy installers left real
# files where links belong, and a hand-edited copy is still a copy.
plan_clean() {
  local dir="$1" desired="$2" entry name kind why
  [ -e "$dir" ] || [ -L "$dir" ] || return 0
  if [ -L "$dir" ]; then
    add_plan FATAL '' "$dir" 'managed directory is a symlink'
    return 0
  fi
  # Containment is a property of the clean itself, not of whatever happens to be
  # linked into the directory afterwards.
  why="$(contained_reason "$dir/.")"
  if [ -n "$why" ]; then
    add_plan FATAL '' "$dir" "$why"
    return 0
  fi
  while IFS= read -r -d '' entry; do
    case "$entry" in
      "$dir"/*) ;;
      *) add_plan FATAL '' "$entry" 'entry is not inside the managed directory'; continue ;;
    esac
    name="$(basename "$entry")"
    [ "$name" = .DS_Store ] && continue
    is_allowlisted "$entry" && continue
    if [ -L "$entry" ]; then
      kind=symlink
      printf '%s\n' "$desired" | grep -qxF -- "$name" && continue
    elif [ -d "$entry" ]; then
      kind=dir
    else
      kind=file
    fi
    if [ "$dir" = "$HOME/.claude/hooks" ] && is_registered_hook "$name" &&
       ! printf '%s\n' "$desired" | grep -qxF -- "$name"; then
      add_plan FATAL '' "$entry" 'hook is registered in settings and no source root provides it'
      continue
    fi
    add_plan delete '' "$entry" "$kind"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z)
}

# plan_managed_dir REL TARGET_DIR — clean first, then one link per desired name,
# from whichever root provides it.
plan_managed_dir() {
  local rel="$1" dir="$2" desired name
  # `|| :`: an empty desired set is a grep exit 1, which pipefail would turn into
  # a silent abort.
  desired="$(printf '%s\n%s\n' "$(names_in "$REPO/$rel")" "$(names_in "$PRIVATE/$rel")" | { grep -v '^$' || :; } | LC_ALL=C sort)"
  plan_clean "$dir" "$desired"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -e "$REPO/$rel/$name" ] || [ -L "$REPO/$rel/$name" ]; then
      plan_entry "$REPO/$rel/$name" "$dir/$name"
    else
      plan_entry "$PRIVATE/$rel/$name" "$dir/$name"
    fi
  done <<EOF
$desired
EOF
}

for d in $CLAUDE_DIRS; do
  plan_managed_dir "claude/$d" "$HOME/.claude/$d"
done
plan_managed_dir "agents/skills" "$HOME/.agents/skills"
plan_managed_dir "codex/rules" "$HOME/.codex/rules"
plan_entry "$REPO/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
plan_entry "$REPO/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
plan_entry "$REPO/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
plan_entry "$REPO/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"

# ------------------------------------------------------------------- print

print_plan() {
  local i
  i=0
  while [ "$i" -lt "${#PLAN_CLASS[@]}" ]; do
    case "${PLAN_CLASS[$i]}" in
      unchanged) ;;
      FATAL) printf 'FATAL     %s: %s\n' "${PLAN_DST[$i]}" "${PLAN_WHY[$i]}" ;;
      delete) printf 'delete    %s (%s)\n' "${PLAN_DST[$i]}" "${PLAN_WHY[$i]}" ;;
      *) printf '%-9s %s -> %s\n' "${PLAN_CLASS[$i]}" "${PLAN_DST[$i]}" "${PLAN_SRC[$i]}" ;;
    esac
    i=$((i + 1))
  done
}

print_plan

if [ "$fatal_count" -gt 0 ]; then
  die "$fatal_count fatal entr$( [ "$fatal_count" = 1 ] && printf 'y' || printf 'ies'); nothing written"
fi

# ------------------------------------------------------------------- apply

# Create the link under a temporary name beside the target and rename it into
# place, so a hook path registered in settings never stops resolving. rename(2)
# replaces a symlink-to-file atomically, but mv onto a symlink-to-DIRECTORY
# follows the link and moves the temp file INTO that directory; directory links
# are repointed with ln -sfn instead (a shorter, non-atomic window, and no hook
# is a directory).
place_link() {
  local src="$1" dst="$2" tmp
  mkdir -p "$(dirname "$dst")" || die "cannot create $(dirname "$dst")"
  # -n and an unguessable suffix: a pre-planted symlink-to-directory at the temp
  # name would otherwise receive the link inside it instead of being replaced.
  tmp="$(dirname "$dst")/.$(basename "$dst").link.$$.$RANDOM"
  ln -sfn "$src" "$tmp" || die "cannot link $tmp -> $src"
  # Re-tested right before the rename to shrink the window; GNU mv -T would close
  # it, but BSD mv has no equivalent.
  if [ -L "$dst" ] && [ -d "$dst" ]; then
    rm -f "$tmp"
    ln -sfn "$src" "$dst" || die "cannot link $dst -> $src"
    return
  fi
  mv -f "$tmp" "$dst" || die "cannot move $tmp onto $dst"
}

# Never a trailing slash on the path: rm -rf on "link/" follows the link and
# empties its target. A symlink is removed as a symlink whatever it points at.
# A planned directory that is no longer a real directory is skipped with a
# warning, not deleted and not fatal: the plan was computed moments ago.
remove_entry() {
  local path="$1" kind="$2"
  case "$kind" in
    symlink|file) rm -f "$path" || die "cannot remove $path" ;;
    dir)
      if [ ! -L "$path" ] && [ -d "$path" ]; then
        rm -rf "$path" || die "cannot remove $path"
      else
        warn "skipping $path: no longer a real directory"
      fi
      ;;
  esac
}

n_delete=0; n_link=0; n_repoint=0; n_replace=0; n_unchanged=0
i=0
while [ "$i" -lt "${#PLAN_CLASS[@]}" ]; do
  case "${PLAN_CLASS[$i]}" in
    delete)    n_delete=$((n_delete + 1)) ;;
    link)      n_link=$((n_link + 1)) ;;
    repoint)   n_repoint=$((n_repoint + 1)) ;;
    replace)   n_replace=$((n_replace + 1)) ;;
    unchanged) n_unchanged=$((n_unchanged + 1)) ;;
  esac
  if [ "$DRY_RUN" = 0 ]; then
    case "${PLAN_CLASS[$i]}" in
      delete) remove_entry "${PLAN_DST[$i]}" "${PLAN_WHY[$i]}" ;;
      link|repoint|replace) place_link "${PLAN_SRC[$i]}" "${PLAN_DST[$i]}" ;;
    esac
  fi
  i=$((i + 1))
done

# ----------------------------------------------------------------- summary

if [ $((n_delete + n_link + n_repoint + n_replace)) -eq 0 ]; then
  note "no changes ($n_unchanged unchanged)"
elif [ "$DRY_RUN" = 1 ]; then
  note "dry run: nothing written; would delete $n_delete, link $n_link, repoint $n_repoint, replace $n_replace ($n_unchanged unchanged)"
else
  note "deleted $n_delete, linked $n_link, repointed $n_repoint, replaced $n_replace, unchanged $n_unchanged"
fi
