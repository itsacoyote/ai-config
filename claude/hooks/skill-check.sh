#!/bin/bash
# Injects a reminder when Claude is about to run git commit or gh pr create/edit
# without having invoked the required skill first.
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

if echo "$cmd" | grep -qE '(^|[[:space:]])git\b.*[[:space:]]commit([[:space:]]|$)'; then
  cat <<'JSON'
{
  "systemMessage": "[skill-check] Invoke Skill(git-commit) before this commit if you have not already done so this turn.",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "REQUIRED: You must invoke Skill({\"skill\":\"git-commit\"}) before running git commit. If you have not done so this turn, cancel this Bash call and invoke the skill first, then re-run the commit."
  }
}
JSON
elif echo "$cmd" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+(create|edit)'; then
  cat <<'JSON'
{
  "systemMessage": "[skill-check] Invoke Skill(create-pr) before this PR action if you have not already done so this turn.",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "REQUIRED: You must invoke Skill({\"skill\":\"create-pr\"}) before running gh pr create or gh pr edit. If you have not done so this turn, cancel this Bash call and invoke the skill first, then re-run the command."
  }
}
JSON
fi
