#!/bin/sh
# session-orient.sh — SessionStart hook: injects a compact "where am I" line so a
# fresh or /cleared session immediately knows its worktree, branch, and tree state.
#
# Distinct responsibility from beads-gate.sh (which handles beads). Read-only.
# Never exits non-zero (a SessionStart hook must not abort the session).
#
# Path handling: resolves the helper script relative to this file's own location
# ($HERE), so it always finds the copy in the *current* worktree rather than a
# hardcoded checkout. Each worktree carries its own .claude/, so this stays local.
#
# Schema: {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}

HERE=$(dirname "$0")
WT="$HERE/../scripts/worktree-status.sh"

orient=""
[ -f "$WT" ] && orient=$(bash "$WT" --brief 2>/dev/null)

[ -z "$orient" ] && exit 0

msg="Session orientation (re-ground before starting new work — /reground for the full picture):
$orient"

if command -v jq >/dev/null 2>&1; then
  ctx=$(printf '%s' "$msg" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$ctx"
fi
exit 0
