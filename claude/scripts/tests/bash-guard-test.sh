#!/usr/bin/env bash
# bash-guard-test.sh — self-contained test suite for claude/hooks/bash-guard.sh
#
# The hook is a PreToolUse deny wall for every Bash call. Its two unrecoverable
# failures are opposite: silently allowing when it cannot inspect the command
# (jq missing, payload unparseable), and denying everything. The fail-closed
# guard is mutation-tested below, and the empty-command case is the positive
# control that proves a deny is not just "denies whatever it sees". Command
# strings live in payload files, never in this script's own command lines, so a
# live instance of the hook does not block running the suite.
#
# Usage:  bash claude/scripts/tests/bash-guard-test.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

set -u

pass=0
fail=0
ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
HOOK="${BASH_GUARD_UNDER_TEST:-$REPO_ROOT/claude/hooks/bash-guard.sh}"

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
TMP=$(mktemp -d "$TMPBASE/bash-guard-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp produced no directory" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 1; }

# payload <name> <command> — writes the hook's stdin JSON for one command.
payload() {
  jq -nc --arg c "$2" '{tool_input:{command:$c}}' > "$TMP/$1.json"
}

# run_hook <payload-file> [PATH override] — OUT and STATUS as usual.
OUT=''; STATUS=0
run_hook() {
  if [ -n "${2:-}" ]; then
    OUT="$(PATH="$2" /bin/bash "$HOOK" < "$1" 2>&1)"
  else
    OUT="$(bash "$HOOK" < "$1" 2>&1)"
  fi
  STATUS=$?
}
denies() { printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"'; }

section 'decisions'

payload secret 'gh secret list'
run_hook "$TMP/secret.json"
if [ "$STATUS" = 0 ] && denies && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null; then
  ok 'denies a gh secrets subcommand with well-formed hook JSON'
else
  not_ok "denies a gh secrets subcommand with well-formed hook JSON (status=$STATUS): $OUT"
fi

payload sshread 'cat ~/.ssh/id_rsa'
run_hook "$TMP/sshread.json"
if denies; then
  ok 'denies a credential-file read'
else
  not_ok "denies a credential-file read: $OUT"
fi

# Positive controls: documented non-blocks stay silent.
payload api 'gh api /user'
run_hook "$TMP/api.json"
if [ "$STATUS" = 0 ] && [ -z "$OUT" ]; then
  ok 'does not block gh api (routed to an ask rule instead)'
else
  not_ok "does not block gh api (status=$STATUS): $OUT"
fi

payload prtitle 'gh pr create -t "add secret"'
run_hook "$TMP/prtitle.json"
if [ "$STATUS" = 0 ] && [ -z "$OUT" ]; then
  ok 'does not block a gh command whose argument merely contains a blocked word'
else
  not_ok "does not block a gh command whose argument merely contains a blocked word (status=$STATUS): $OUT"
fi

printf '{"tool_input":{}}\n' > "$TMP/empty.json"
run_hook "$TMP/empty.json"
if [ "$STATUS" = 0 ] && [ -z "$OUT" ]; then
  ok 'stays silent on an empty command'
else
  not_ok "stays silent on an empty command (status=$STATUS): $OUT"
fi

section 'fail closed'

# GUARD (mutation-tested): with jq absent the command cannot be inspected, so the
# hook must deny, not fall through. Remove the `command -v jq` check and this goes
# red on the message: the parse branch still denies (jq is "not found", exit 127),
# so this assertion pins the reason, and the parse-branch test below pins the deny
# itself. A PATH with only the shells on it; the deny path itself must not need jq.
BIN="$TMP/bin"; mkdir -p "$BIN"
ln -s /bin/bash "$BIN/bash"; ln -s /bin/sh "$BIN/sh"; ln -s /bin/cat "$BIN/cat"
run_hook "$TMP/api.json" "$BIN"
if [ "$STATUS" = 0 ] && denies && printf '%s' "$OUT" | grep -q 'jq is not on PATH'; then
  ok 'denies every command when jq is not on PATH'
else
  not_ok "denies every command when jq is not on PATH (status=$STATUS): $OUT"
fi

printf 'not json\n' > "$TMP/garbage.txt"
run_hook "$TMP/garbage.txt"
if [ "$STATUS" = 0 ] && denies && printf '%s' "$OUT" | grep -q 'could not be parsed'; then
  ok 'denies when the payload is not JSON'
else
  not_ok "denies when the payload is not JSON (status=$STATUS): $OUT"
fi

# The deny JSON is produced without jq and must still be valid JSON.
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok 'emits valid JSON on the deny path without jq'
else
  not_ok "emits valid JSON on the deny path without jq: $OUT"
fi

section 'portability'

if sed 's/#.*//' "$HOOK" | grep -Eq '(^|[[:space:]])(mapfile|readarray|(declare|local)[[:space:]]+-A)([[:space:]]|$)'; then
  not_ok 'uses no bash 4 builtins'
else
  ok 'uses no bash 4 builtins'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
