#!/usr/bin/env bash
# wt-status.sh — quick worktree orientation snapshot (branch / head / status / rebase).
#
# Why this exists: ad-hoc one-liners like `cd X && echo "$(git rev-parse …)" ; git status …`
# contain command substitution, so the sandbox can NEVER auto-approve them and they
# prompt every time. Wrapping the sequence in one audited script means a single,
# allow-listed invocation runs the whole thing with no prompts.
#
# LOCAL git only — a sandboxed script cannot reach the network or a hardware signing
# device, so DO NOT add fetch/pull/push/remote or signing operations here; those must run
# as native `git` on the command line.
#
# Usage:  bash ~/.claude/scripts/wt-status.sh [dir]
#   dir   optional worktree/repo directory to inspect (defaults to the current dir)
#
# Allow-list this in ~/.claude/settings.json permissions.allow:
#   "Bash(bash /Users/sf/.claude/scripts/wt-status.sh*)"

set -uo pipefail

# This script is allow-listed with an arbitrary directory argument, so it must
# never execute anything the target repository's own .git/config asks for.
# core.fsmonitor runs a command during status and rev-parse; hooksPath covers the
# rest. Without these, a hand-written .git/config in any directory is code
# execution with no permission prompt.
export GIT_CONFIG_NOSYSTEM=1
g() { git -c core.fsmonitor=false -c core.hooksPath=/dev/null --no-optional-locks "$@"; }

dir="${1:-$PWD}"
cd "$dir" 2>/dev/null || { echo "wt-status: cannot cd to $dir"; exit 1; }

if ! g rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "dir:    $dir"
  echo "(not a git working tree)"
  exit 0
fi

echo "dir:    $dir"
echo "branch: $(g rev-parse --abbrev-ref HEAD 2>/dev/null)"
echo "head:   $(g rev-parse --short HEAD 2>/dev/null)"

echo "--- status ---"
g status --short

echo "--- rebase in progress? ---"
if [ -d "$(g rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   || [ -d "$(g rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  echo "REBASE ACTIVE"
else
  echo "no rebase active"
fi
