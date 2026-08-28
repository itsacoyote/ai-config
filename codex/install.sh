#!/usr/bin/env bash
# install.sh — install ai-config Codex command rules into ~/.codex.
# Run this yourself: ~/.codex is user-owned. This manages only ai-config.rules.

set -euo pipefail
set -f
die() { printf 'codex/install.sh: %s\n' "$*" >&2; exit 2; }
note() { printf '%s\n' "$*"; }
usage() { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; }
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done
SRC="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="$SRC/rules/ai-config.rules"
TARGET_ROOT="$HOME/.codex"
TARGET_RULES="$TARGET_ROOT/rules"
TARGET="$TARGET_RULES/ai-config.rules"
[ -f "$SOURCE" ] && [ ! -L "$SOURCE" ] || die "rules source is missing or a symlink ($SOURCE)"
[ -L "$TARGET_ROOT" ] && die "guard: $TARGET_ROOT is a symlink — refusing to install"
[ -L "$TARGET_RULES" ] && die "guard: $TARGET_RULES is a symlink — refusing to install"
[ -L "$TARGET" ] && die "guard: $TARGET is a symlink — refusing to overwrite it"
[ -e "$TARGET" ] && [ ! -f "$TARGET" ] && die "guard: $TARGET is not a regular file — refusing to overwrite it"
if [ "$DRY_RUN" -eq 1 ]; then
  if [ ! -e "$TARGET" ]; then note "would create: $TARGET"
  elif cmp -s "$SOURCE" "$TARGET"; then note "already current: $TARGET"
  else note "would update: $TARGET"; fi
  exit 0
fi
mkdir -p "$TARGET_RULES"
[ -d "$TARGET_RULES" ] && [ ! -L "$TARGET_RULES" ] || die "guard: rules directory is not safe"
TEMP="$(mktemp "$TARGET_RULES/.ai-config.rules.XXXXXX")" || die "cannot create temporary rules file"
cleanup() { [ -z "$TEMP" ] || rm -f "$TEMP"; }
trap cleanup EXIT
cp -pP "$SOURCE" "$TEMP"
[ -f "$TEMP" ] && [ ! -L "$TEMP" ] || die "rules source did not produce a regular file"
mv -f "$TEMP" "$TARGET"
TEMP=''
note "installed: $TARGET"
