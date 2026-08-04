#!/bin/sh
# beads-preflight.sh — is beads (bd) set up and usable in this checkout?
#
# The required gate for every workflow skill: run it, and if it exits non-zero,
# STOP and tell the user to run the `setup-beads` skill before doing workflow work.
#
# Why a script and not `test -d .beads && command -v bd`: that one-liner is WRONG
# in a git worktree. Worktrees deliberately do NOT get their own `.beads/` (it would
# fork the database — see .worktreeinclude); `bd` instead resolves the main repo's
# single `.beads/` through the shared git common dir. So `.beads` is absent from the
# worktree's own root even though beads works there. This script resolves `.beads`
# via the git common dir, so it returns success in worktrees too.
#
# Exit: 0 beads available; 1 not available (message on stderr).

set -u

if ! command -v bd >/dev/null 2>&1; then
  echo "beads: \`bd\` is not installed. Run the setup-beads skill to install and initialize it, then retry." >&2
  exit 1
fi

# Resolve the repo's shared .beads — works in the main tree, in subdirectories,
# and in worktrees (where .beads lives only in the main tree, shared via the git
# common dir). The common dir's parent is the main working tree root.
if [ -d .beads ]; then
  exit 0
fi
common="$(git rev-parse --git-common-dir 2>/dev/null)" || common=""
if [ -n "$common" ] && [ -d "$common/../.beads" ]; then
  exit 0
fi

echo "beads: no .beads/ found for this repository. Run the setup-beads skill to initialize it, then retry." >&2
echo "       (If you are in a git worktree, run setup-beads from the MAIN working tree, never the worktree.)" >&2
exit 1
