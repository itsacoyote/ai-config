#!/usr/bin/env bash
# install.sh — additively install portable Agent Skills into ~/.agents/skills.
#
# Run this yourself, not through an agent: the global ~/.agents directory is
# human-owned. This script manages skills only. It never reads, creates, copies,
# merges, or modifies AGENTS.md, ~/.codex, or Pi configuration.
#
# Usage:
#   agents/install.sh             install or update shared skills
#   agents/install.sh --dry-run   report changes without writing

set -euo pipefail
set -f

die()  { printf 'install.sh: %s\n' "$*" >&2; exit 2; }
note() { printf '%s\n' "$*"; }

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

SRC="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_SKILLS="$SRC/skills"
TARGET_ROOT="$HOME/.agents"
TARGET_SKILLS="$TARGET_ROOT/skills"

[ -d "$SOURCE_SKILLS" ] || die "no skills content next to this script ($SOURCE_SKILLS) — run the repository copy"
[ ! -L "$SOURCE_SKILLS" ] || die "skills content root is a symlink ($SOURCE_SKILLS) — refusing to install"

HOME_P="$(CDPATH='' cd "$HOME" 2>/dev/null && pwd -P)" || die "cannot resolve HOME ($HOME)"
TARGET_ROOT_P="$(CDPATH='' cd "$TARGET_ROOT" 2>/dev/null && pwd -P || printf '%s' "$TARGET_ROOT")"

case "$(pwd -P)/" in
  "$TARGET_ROOT_P"|"$TARGET_ROOT_P"/*)
    die "refusing to run from inside $TARGET_ROOT — run the repository copy"
    ;;
esac
case "$SRC/" in
  "$TARGET_ROOT_P"/*)
    die "refusing to run an installed copy against itself — run the repository copy"
    ;;
esac

# Refuse a redirected managed root before inventory or writes. The source tree may contain
# symlinks, but find deliberately inventories only regular files without following them.
[ -L "$TARGET_ROOT" ] && die "guard: $TARGET_ROOT is a symlink — refusing to install"
[ -L "$TARGET_SKILLS" ] && die "guard: $TARGET_SKILLS is a symlink — refusing to install"

MANIFEST="$(mktemp "${TMPDIR:-/tmp}/agents-install-manifest.XXXXXX")" || die "cannot create manifest"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/agents-install-stage.XXXXXX")" || die "cannot create staging directory"
TEMP_DEST=""

cleanup() {
  [ -z "$TEMP_DEST" ] || rm -f "$TEMP_DEST"
  rm -f "$MANIFEST"
  rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 2' HUP INT TERM

find "$SOURCE_SKILLS" -type f -print0 | sort -z >"$MANIFEST"
[ -s "$MANIFEST" ] || die "no regular skill files found under $SOURCE_SKILLS"

assert_safe_relative() {
  rel="$1"
  case "$rel" in
    ''|/*|../*|*/../*|*/..|.) die "guard: unsafe source path: $rel" ;;
  esac
}

assert_destination_safe() {
  rel="$1"
  dest="$TARGET_SKILLS/$rel"
  parent="$(dirname "$dest")"

  assert_safe_relative "$rel"
  [ -L "$dest" ] && die "guard: $rel is a destination symlink — refusing to write through it"
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    die "guard: $rel is not a regular destination file — refusing to overwrite it"
  fi

  # Walk every existing component. This catches dangling parent symlinks, which cannot be
  # detected by resolving only the final existing directory.
  cursor="$TARGET_ROOT"
  remainder="skills/$rel"
  old_ifs="$IFS"
  IFS='/'
  for component in $remainder; do
    IFS="$old_ifs"
    cursor="$cursor/$component"
    [ -L "$cursor" ] && die "guard: $rel has a symlinked destination component ($cursor)"
    if [ "$cursor" != "$dest" ] && [ -e "$cursor" ] && [ ! -d "$cursor" ]; then
      die "guard: $rel has a non-directory destination parent ($cursor)"
    fi
    IFS='/'
  done
  IFS="$old_ifs"

  # Resolve the nearest existing parent and ensure it stays inside the physical HOME. Once
  # ~/.agents exists, require its physical path as the stricter containment boundary.
  existing="$parent"
  while [ ! -d "$existing" ]; do
    next="$(dirname "$existing")"
    [ "$next" != "$existing" ] || die "guard: cannot find an existing parent for $rel"
    existing="$next"
  done
  existing_p="$(CDPATH='' cd "$existing" 2>/dev/null && pwd -P)" || die "guard: cannot resolve parent of $rel"
  [ -w "$existing" ] && [ -x "$existing" ] || die "guard: parent for $rel is not writable and searchable ($existing)"

  if [ -d "$TARGET_ROOT" ]; then
    managed_p="$(CDPATH='' cd "$TARGET_ROOT" 2>/dev/null && pwd -P)" || die "guard: cannot resolve $TARGET_ROOT"
    case "$managed_p/" in
      "$HOME_P"/*) : ;;
      *) die "guard: $TARGET_ROOT resolves outside HOME — refusing to install" ;;
    esac
    case "$existing_p/" in
      "$managed_p"/|"$managed_p"/*) : ;;
      *) die "guard: $rel resolves outside $TARGET_ROOT — refusing to write" ;;
    esac
  else
    case "$existing_p/" in
      "$HOME_P"/|"$HOME_P"/*) : ;;
      *) die "guard: $rel resolves outside HOME — refusing to write" ;;
    esac
  fi
}

is_managed_relative() {
  wanted="$SOURCE_SKILLS/$1"
  while IFS= read -r -d '' managed_source; do
    [ "$managed_source" = "$wanted" ] && return 0
  done <"$MANIFEST"
  return 1
}

# Snapshot every source into a private tree before touching the destination. `cp -P` does
# not follow a source that is swapped to a symlink during staging; the post-copy check then
# rejects that staged link. Phase two reads only this stable snapshot.
while IFS= read -r -d '' source_file; do
  rel="${source_file#"$SOURCE_SKILLS"/}"
  assert_safe_relative "$rel"
  [ -f "$source_file" ] && [ ! -L "$source_file" ] || die "source changed during inventory: $rel"
  staged="$STAGE/$rel"
  mkdir -p "$(dirname "$staged")"
  cp -pP "$source_file" "$staged"
  [ -f "$staged" ] && [ ! -L "$staged" ] || die "source is not a stable regular file: $rel"
done <"$MANIFEST"

# Phase one: validate the complete source/destination plan before mkdir or cp. Do not move
# this check into the copy loop; a late unsafe path must prevent every earlier overwrite.
while IFS= read -r -d '' source_file; do
  rel="${source_file#"$SOURCE_SKILLS"/}"
  assert_destination_safe "$rel"
done <"$MANIFEST"

created=0
updated=0
unchanged=0

note "installing $SOURCE_SKILLS -> $TARGET_SKILLS$([ "$DRY_RUN" = 1 ] && printf ' (dry run)')"

# Phase two: every planned destination is safe, so perform the additive copies.
while IFS= read -r -d '' source_file; do
  rel="${source_file#"$SOURCE_SKILLS"/}"
  staged="$STAGE/$rel"
  dest="$TARGET_SKILLS/$rel"
  parent="$(dirname "$dest")"

  # Re-check immediately around directory creation so a change after the full preflight is
  # caught before file content is copied. Portable Bash cannot make path traversal fully
  # race-free against a malicious same-user process, but it must not rely only on stale data.
  assert_destination_safe "$rel"

  if [ ! -e "$dest" ]; then
    created=$((created + 1))
    if [ "$DRY_RUN" = 1 ]; then
      note "  would create: $rel"
    else
      mkdir -p "$parent"
      assert_destination_safe "$rel"
      TEMP_DEST="$(mktemp "$parent/.agents-install.XXXXXX")" || die "cannot create temporary destination for $rel"
      cp -p "$staged" "$TEMP_DEST"
      assert_destination_safe "$rel"
      mv -f "$TEMP_DEST" "$dest"
      TEMP_DEST=""
      note "  new: $rel"
    fi
  elif ! cmp -s "$staged" "$dest"; then
    updated=$((updated + 1))
    if [ "$DRY_RUN" = 1 ]; then
      note "  would overwrite: $rel"
    else
      TEMP_DEST="$(mktemp "$parent/.agents-install.XXXXXX")" || die "cannot create temporary destination for $rel"
      cp -p "$staged" "$TEMP_DEST"
      assert_destination_safe "$rel"
      mv -f "$TEMP_DEST" "$dest"
      TEMP_DEST=""
      note "  updated: $rel"
    fi
  else
    unchanged=$((unchanged + 1))
  fi
done <"$MANIFEST"

if [ $((created + updated)) -eq 0 ]; then
  note "no changes — shared skills are current ($unchanged files checked)"
else
  note "skills: $created new, $updated updated, $unchanged unchanged"
fi

# Files below the one managed subtree that are absent from the source are personal or stale.
# Report them for visibility; additive installation never deletes them.
global_only=""
if [ -d "$TARGET_SKILLS" ]; then
  while IFS= read -r -d '' target_file; do
    rel="${target_file#"$TARGET_SKILLS"/}"
    is_managed_relative "$rel" || global_only="$global_only  $rel"$'\n'
  done < <(find "$TARGET_SKILLS" -type f -print0 | sort -z)
fi

if [ -n "$global_only" ]; then
  note ""
  note "global-only skill paths (personal customization or stale copy — left untouched):"
  printf '%s' "$global_only"
fi
