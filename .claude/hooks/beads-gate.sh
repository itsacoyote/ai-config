#!/bin/sh
# beads-gate.sh — SessionStart hook for the ai-config beads workflow
#
# Emits a SessionStart hook JSON response:
#   - If beads ABSENT: warns that the project requires beads and directs user to run setup-beads.
#   - If beads PRESENT: injects a one-line reminder + bd ready output as additionalContext.
#
# Never exits non-zero (SessionStart hooks must not abort the session).
# Requires jq for safe JSON encoding. Falls back to a minimal static message if jq is absent.
#
# Schema: { "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "..." } }

if ! command -v jq >/dev/null 2>&1; then
  # jq unavailable — emit safe static JSON and exit cleanly
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: jq not found; beads gate could not run. Install jq so the full beads-gate check can execute."}}\n'
  exit 0
fi

# Detect beads the worktree-correct way: a worktree's own root has no .beads/
# (it shares the main tree's via the git common dir), so a bare `test -d .beads`
# would falsely report "absent" in worktree sessions. Defer to the shared
# preflight script, with a bare-check fallback if it isn't present.
preflight="$(dirname "$0")/../references/beads-preflight.sh"
if [ -f "$preflight" ]; then
  sh "$preflight" >/dev/null 2>&1 && beads_ok=1 || beads_ok=0
else
  { test -d .beads && command -v bd >/dev/null 2>&1; } && beads_ok=1 || beads_ok=0
fi

if [ "$beads_ok" = 1 ]; then
  # Beads present — inject reminder + bd ready output
  bd_output="$(bd ready 2>&1)"
  context="$(printf 'This project uses beads (bd) as the system of record.\n\n%s' "$bd_output" | jq -Rs .)"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$context"
else
  # Beads absent — warn user and instruct them to set up beads
  msg="WARNING: This project requires beads (bd) for workflow tracking, but beads is not active in this directory. Run the \`setup-beads\` skill to initialize beads before starting workflow tasks."
  context="$(printf '%s' "$msg" | jq -Rs .)"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$context"
fi

exit 0
