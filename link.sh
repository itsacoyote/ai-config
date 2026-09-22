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
# themselves.
for home in .claude .agents .codex .pi; do
  case "$REPO/" in
    "$HOME_P/$home"/*) die "refusing to run from inside $HOME_P/$home — run from the repository checkout" ;;
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

# ------------------------------------------------------------------ summary

if [ "$DRY_RUN" = 1 ]; then
  note "dry run: nothing written"
fi
note "no changes"
