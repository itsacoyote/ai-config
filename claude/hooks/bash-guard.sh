#!/usr/bin/env bash
# bash-guard.sh — PreToolUse (Bash) security hook.
#
# Purpose: turn the brittle prefix-based Bash permission rules into a real wall
# for the highest-value targets. Prefix rules like `Bash(gh secret *)` are
# bypassable via `bash -c`, chaining, and env-var prefixes; this hook scans the
# whole command string so those tricks still get caught.
#
# It hard-blocks (PreToolUse permissionDecision: "deny"):
#   1. gh subcommands that touch secrets / auth tokens / keys, or are destructive
#   2. shell reads of credential files (.ssh, .aws, gh config, gnupg, netrc,
#      npmrc, docker config) and the macOS keychain
#
# On no match it exits 0 with no output, deferring to the normal permission flow.
# NOTE: intentionally does NOT block `gh api` — that is routed to an `ask` rule
# so the user can approve specific read-only calls.
#
# Residual gap (documented, not a bug): deliberate variable indirection such as
# `X=secret; gh $X list` defeats string scanning. The bulletproof layers for
# that are reduced gh token scopes and the OS sandbox.

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"

# Empty / unparseable command: nothing to check.
[ -z "$cmd" ] && exit 0

emit_deny() {
  jq -nc --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# --- gh: secrets / auth / keys / destructive --------------------------------
# Anchored so the subcommand directly follows `gh` — avoids false positives like
# `gh pr create -t "add secret"`.
gh_patterns=(
  'gh[[:space:]]+auth[[:space:]]+token'
  'gh[[:space:]]+auth[[:space:]]+(login|logout|refresh|setup-git)'
  'gh[[:space:]]+secret([[:space:]]|$)'
  'gh[[:space:]]+variable[[:space:]]+(set|delete|remove)'
  'gh[[:space:]]+ssh-key[[:space:]]+(add|delete)'
  'gh[[:space:]]+gpg-key[[:space:]]+(add|delete)'
  'gh[[:space:]]+codespace([[:space:]]|$)'
  'gh[[:space:]]+alias[[:space:]]+(set|import)'
  'gh[[:space:]]+gist[[:space:]]+(create|edit|delete)'
  'gh[[:space:]]+repo[[:space:]]+(delete|archive)'
  'gh[[:space:]]+release[[:space:]]+delete'
)
for p in "${gh_patterns[@]}"; do
  if printf '%s' "$cmd" | grep -Eiq "$p"; then
    emit_deny "bash-guard: blocked a gh command in the secrets/credentials/destructive class. Denied by security policy — do not retry. Use an allowed gh subcommand, or ask the user to run this one manually in their own terminal."
  fi
done

# --- credential file / keychain reads ---------------------------------------
cred_patterns=(
  '\.ssh/'
  '\.aws/(credentials|config)'
  '\.config/gh/'
  '\.gnupg/'
  '\.netrc'
  '\.npmrc'
  '\.docker/config\.json'
  'security[[:space:]]+(find-generic-password|find-internet-password|dump-keychain)'
)
for p in "${cred_patterns[@]}"; do
  if printf '%s' "$cmd" | grep -Eiq "$p"; then
    emit_deny "bash-guard: blocked access to a credential file or the keychain. Denied by security policy — do not retry. If this file is genuinely needed, ask the user to read it or hand you the relevant non-secret part."
  fi
done

exit 0
