#!/usr/bin/env bash
# install.sh — install/update this Claude library into the user's global ~/.claude.
#
# Additively copies the content dirs (skills agents rules references scripts
# hooks) plus statusline-command.sh. Additive means: it creates and overwrites
# library files, and never deletes anything — global-only files (local
# customizations, deliberately un-tracked skills) survive every run.
#
# It NEVER creates or modifies ~/.claude/settings.json or settings.local.json:
# a user's global settings file carries personal configuration no script should
# silently rewrite (ADR 0007). Instead it prints a merge report — template
# entries (hooks, permissions, statusLine) missing from BOTH global settings
# files — for the human to apply by hand.
#
# Run this yourself, not through an agent: ~/.claude is human-owned territory.
#
# Usage:
#   claude/install.sh             install/update into ~/.claude + merge report
#   claude/install.sh --dry-run   report everything, write nothing

set -euo pipefail

die()  { printf 'install.sh: %s\n' "$*" >&2; exit 2; }
note() { printf '%s\n' "$*"; }

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

SRC="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET="$HOME/.claude"

[ -d "$SRC/skills" ] || die "no library content next to this script ($SRC) — run it from the repository checkout"
# Compare physical-to-physical: pwd -P resolves symlinks (macOS /tmp ->
# /private/tmp), so an unresolved $TARGET would never match and the guard
# would silently pass exactly where it matters.
TARGET_P="$(cd "$TARGET" 2>/dev/null && pwd -P || printf '%s' "$TARGET")"
case "$(pwd -P)/" in
  "$TARGET_P"/*) die "refusing to run from inside $TARGET — run from the repository checkout" ;;
esac
case "$SRC/" in
  "$TARGET_P"/*) die "refusing to run the installed copy against itself — run from the repository checkout" ;;
esac

# The copy set deliberately excludes settings.json and settings.local.json —
# the merge report below covers that delta. Adding them here is the wrong fix
# for "why isn't my settings installed?" and install_file dies on it.
CONTENT_DIRS=(skills agents rules references scripts hooks)
EXTRA_FILES=(statusline-command.sh)

created=0
updated=0
unchanged=0

# A symlinked PARENT dir would also redirect writes outside the target —
# verify the physically-resolved directory still lives under $TARGET. The
# target is re-resolved here (not reused from startup) because on a fresh
# install ~/.claude doesn't exist yet when the startup guard computed it.
assert_contained() {
  local rel="$1" dir="$2" dir_p target_p
  dir_p="$(cd "$dir" 2>/dev/null && pwd -P)" || die "guard: cannot resolve parent of $rel"
  target_p="$(cd "$TARGET" 2>/dev/null && pwd -P)" || die "guard: cannot resolve $TARGET"
  case "$dir_p/" in
    "$target_p"/*) : ;;
    *) die "guard: $rel resolves to $dir_p, outside $TARGET — refusing to write" ;;
  esac
}

install_file() {
  local rel="$1" src="$2" dest="$3"
  case "$rel" in
    settings.json|settings.local.json)
      die "guard: attempted to write $rel — the installer never touches settings files" ;;
  esac
  # A symlink at $dest makes cp -p write THROUGH to its target — outside the
  # managed set and past the settings guard above, which only sees $rel. A
  # dangling link is even worse: it looks non-existent and takes the create
  # branch, writing wherever it points.
  [ -L "$dest" ] && die "guard: $rel is a symlink under $TARGET — refusing to write through it"
  if [ ! -e "$dest" ]; then
    created=$((created + 1))
    if [ "$DRY_RUN" = 1 ]; then
      note "  would create: $rel"
    else
      mkdir -p "$(dirname "$dest")"
      assert_contained "$rel" "$(dirname "$dest")"
      cp -p "$src" "$dest"
      note "  new: $rel"
    fi
  elif ! cmp -s "$src" "$dest"; then
    assert_contained "$rel" "$(dirname "$dest")"
    updated=$((updated + 1))
    if [ "$DRY_RUN" = 1 ]; then
      note "  would overwrite: $rel"
    else
      cp -p "$src" "$dest"
      note "  updated: $rel"
    fi
  else
    unchanged=$((unchanged + 1))
  fi
}

note "installing $SRC -> $TARGET$([ "$DRY_RUN" = 1 ] && printf ' (dry run)')"
for d in "${CONTENT_DIRS[@]}"; do
  [ -d "$SRC/$d" ] || continue
  while IFS= read -r -d '' f; do
    rel="${f#"$SRC"/}"
    install_file "$rel" "$f" "$TARGET/$rel"
  done < <(find "$SRC/$d" -type f -print0 | sort -z)
  # -type f without -L is deliberate: it skips source symlinks, so a checkout
  # cannot pull arbitrary host files into ~/.claude via a planted link.
  # "Fixing" this to -L reopens that hole.
done
for f in "${EXTRA_FILES[@]}"; do
  [ -f "$SRC/$f" ] && install_file "$f" "$SRC/$f" "$TARGET/$f"
done

if [ $((created + updated)) -eq 0 ]; then
  note "no changes — global content is current ($unchanged files checked)"
else
  note "content: $created new, $updated updated, $unchanged unchanged"
fi

# ── Global-only inventory ─────────────────────────────────────────────────────
# Files under the managed dirs that the library doesn't ship: either deliberate
# local customizations or stale copies of renamed/removed library files. Listed
# for visibility, never touched.
orphans=""
for d in "${CONTENT_DIRS[@]}"; do
  [ -d "$TARGET/$d" ] || continue
  while IFS= read -r -d '' f; do
    rel="${f#"$TARGET"/}"
    [ -e "$SRC/$rel" ] || orphans="$orphans  $rel"$'\n'
  done < <(find "$TARGET/$d" -type f -print0 | sort -z)
done
if [ -n "$orphans" ]; then
  note ""
  note "global-only paths (local customization or stale copy — left untouched):"
  printf '%s' "$orphans"
fi

# ── Settings merge report ─────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  note ""
  note "settings merge report requires jq — skipped (content copy unaffected)."
  exit 0
fi

TEMPLATE="$SRC/settings.json"
[ -f "$TEMPLATE" ] || exit 0

# Path forms differ legitimately between the template (~/.claude/...) and a
# real global settings file (absolute /Users/<name>/.claude/...). Comparing
# hook/statusLine commands verbatim would re-report them forever, so both
# sides collapse any path ending in /.claude/ to a canonical marker.
normalize() { sed 's|[^[:space:]"]*/\.claude/|<claude>/|g'; }

globals_json() {
  # Concatenated jq output of "$1" applied to whichever global files exist.
  local filter="$1" f
  for f in "$TARGET/settings.json" "$TARGET/settings.local.json"; do
    [ -f "$f" ] && jq -r "$filter" "$f" 2>/dev/null
  done
  return 0
}

note ""
note "settings merge report (the installer never edits settings — apply by hand):"
# A malformed global file reads as empty and would report everything missing,
# nudging a hand-merge of duplicates into an already-broken file — warn first.
for f in "$TARGET/settings.json" "$TARGET/settings.local.json"; do
  if [ -f "$f" ] && ! jq -e . "$f" >/dev/null 2>&1; then
    note "  WARNING: $f is not valid JSON — treated as empty; entries below may already be present"
  fi
done
missing=0

# Event + command pairs, so a command registered under a DIFFERENT event
# globally doesn't count as present.
HOOK_FILTER='(.hooks // {}) | to_entries[] | .key as $e | .value[]? | .hooks[]? | "\($e)\t\(.command // empty)"'
global_hooks="$(globals_json "$HOOK_FILTER" | normalize)"
while IFS=$'\t' read -r event cmd; do
  [ -n "$cmd" ] || continue
  pair="$(printf '%s\t%s' "$event" "$cmd" | normalize)"
  if ! printf '%s\n' "$global_hooks" | grep -Fxq "$pair"; then
    note "  missing hook: $cmd (register as a $event hook in your global settings)"
    missing=$((missing + 1))
  fi
done < <(jq -r "$HOOK_FILTER" "$TEMPLATE")

tmpl_status="$(jq -r '.statusLine.command // empty' "$TEMPLATE")"
if [ -n "$tmpl_status" ]; then
  global_status="$(globals_json '.statusLine.command // empty' | normalize)"
  if ! printf '%s\n' "$global_status" | grep -Fxq "$(printf '%s' "$tmpl_status" | normalize)"; then
    note "  missing statusLine: $tmpl_status"
    missing=$((missing + 1))
  fi
fi

global_allow="$(globals_json '.permissions.allow[]? // empty')"
while IFS= read -r perm; do
  [ -n "$perm" ] || continue
  if ! printf '%s\n' "$global_allow" | grep -Fxq "$perm"; then
    note "  missing permission (allow): $perm"
    missing=$((missing + 1))
  fi
done < <(jq -r '.permissions.allow[]? // empty' "$TEMPLATE")

# Deny rules are NOT suggested for migration: a global deny is absolute — no
# project can re-allow it — and the template's git -C deny would break the
# deliberate scoped git -C allow already in the maintainer's global settings.
while IFS= read -r perm; do
  [ -n "$perm" ] || continue
  note "  deny rule '$perm': do NOT migrate — global deny is absolute and overrides scoped allows"
done < <(jq -r '.permissions.deny[]? // empty' "$TEMPLATE")

[ "$missing" -eq 0 ] && note "  nothing missing — global settings cover the template."
exit 0
