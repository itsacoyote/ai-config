#!/bin/bash
# Notification hook: pings when Claude Code is waiting on the user.
# Differentiates two cases via the notification message:
#   - needs tool permission  -> Glass sound, "needs permission"
#   - prompt idle (~60s)      -> Tink sound,  "waiting for input"
# Uses terminal-notifier for reliable banners from the VSCode terminal
# (click the banner to jump back to VSCode); falls back to osascript.
input=$(cat)
message=$(echo "$input" | jq -r '.message // "Claude is waiting on you"' 2>/dev/null) || message="Claude is waiting on you"
cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)

project="Claude Code"
[ -n "$cwd" ] && project="Claude Code — $(basename "$cwd")"

# Branch on the message content.
case "$message" in
  *[Pp]ermission*)
    sound="Glass"
    title="$project · needs permission"
    ;;
  *)
    sound="Tink"
    title="$project · waiting for input"
    ;;
esac

tn=$(command -v terminal-notifier)
if [ -n "$tn" ]; then
  # terminal-notifier plays the sound AND shows the banner; clicking it
  # activates VSCode. -group collapses repeats from the same project.
  "$tn" \
    -title "$title" \
    -message "$message" \
    -sound "$sound" \
    -activate "com.microsoft.VSCode" \
    -group "claude-code-$project" \
    >/dev/null 2>&1 &
else
  # Fallback: audible ping via afplay + osascript banner.
  afplay "/System/Library/Sounds/$sound.aiff" >/dev/null 2>&1 &
  osascript - "$title" "$message" >/dev/null 2>&1 <<'APPLESCRIPT' &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
fi

exit 0
