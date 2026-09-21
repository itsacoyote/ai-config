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

dir="${1:-$PWD}"
cd "$dir" 2>/dev/null || { echo "wt-status: cannot cd to $dir"; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "dir:    $dir"
  echo "(not a git working tree)"
  exit 0
fi

echo "dir:    $dir"
echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
echo "head:   $(git rev-parse --short HEAD 2>/dev/null)"

echo "--- status ---"
git status --short

echo "--- rebase in progress? ---"
if [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] \
   || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  echo "REBASE ACTIVE"
else
  echo "no rebase active"
fi
