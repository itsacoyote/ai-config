#!/usr/bin/env bash
# statusline-test.sh — self-contained test suite for claude/statusline-command.sh
#
# The script renders from JSON on stdin and runs git inside whatever directory
# that JSON names, so the suite builds real repositories (a primary checkout,
# linked worktrees, a detached HEAD, a hostile config) under a fake HOME and
# asserts on the rendered text with terminal escapes removed.
#
# Usage:  bash claude/scripts/tests/statusline-test.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

set -u
exec </dev/null

pass=0
fail=0
ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SCRIPT="${STATUSLINE_UNDER_TEST:-$REPO_ROOT/claude/statusline-command.sh}"

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
TMP=$(mktemp -d "$TMPBASE/statusline-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp produced no directory" >&2; exit 1; }
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

ESC=$'\033'
BEL=$'\a'

# plain — drops OSC 8 hyperlinks and SGR colour codes, leaving the visible text.
plain() {
  LC_ALL=C sed -E -e "s/${ESC}\\]8;;[^${ESC}]*${ESC}\\\\//g" -e "s/${ESC}\\[[0-9;]*m//g"
}

# run_statusline <json> — stdout+stderr in OUT, exit status in STATUS.
OUT=''; STATUS=0
run_statusline() {
  OUT="$(printf '%s' "$1" | bash "$SCRIPT" 2>&1)"
  STATUS=$?
}
json_dir() { jq -n --arg d "$1" '{workspace:{current_dir:$d}}'; }
line2()      { printf '%s\n' "$OUT" | sed -n 2p | plain; }
line2_raw()  { printf '%s\n' "$OUT" | sed -n 2p; }

check_line2() {
  local name="$1" dir="$2" expected="$3" got
  run_statusline "$(json_dir "$dir")"
  got="$(line2)"
  if [ "$STATUS" = 0 ] && [ "$got" = "$expected" ]; then
    ok "$name"
  else
    not_ok "$name (status=$STATUS): expected [$expected] got [$got]"
  fi
}

# Primary checkout, with an https origin that carries credentials.
PRIMARY="$TMP/primary-proj"; mkdir -p "$PRIMARY"
( cd "$PRIMARY" && git init -q . && echo a > a.txt && git add a.txt && git commit -qm init &&
  git remote add origin 'https://example.invalid/owner/project.git' ) || { echo "fixture setup failed" >&2; exit 1; }

# Linked worktrees: folder equals branch / branch with / -> - / differs.
( cd "$PRIMARY" &&
  git worktree add -q "$TMP/feature-a" -b feature-a &&
  git worktree add -q "$TMP/feat-login" -b feat/login &&
  git worktree add -q "$TMP/scratch" -b feat/other ) || { echo "worktree fixture setup failed" >&2; exit 1; }

DETACHED="$TMP/detached-proj"; mkdir -p "$DETACHED"
( cd "$DETACHED" && git init -q . && echo a > a.txt && git add a.txt && git commit -qm init &&
  git checkout -q --detach ) || { echo "detached fixture setup failed" >&2; exit 1; }

NONGIT="$TMP/plain-folder"; mkdir -p "$NONGIT"

section 'line 2: project, branch, worktree'

check_line2 'line 2 in the primary checkout shows the folder and branch' \
  "$PRIMARY" '📁 primary-proj | 🌿 main'

check_line2 "line 2 in a linked worktree shows the primary checkout's folder name" \
  "$TMP/scratch" '📁 primary-proj | 🌿 feat/other | scratch'

check_line2 'worktree name is hidden when it equals the branch' \
  "$TMP/feature-a" '📁 primary-proj | 🌿 feature-a'

check_line2 'worktree name is hidden when it equals the branch with slashes replaced by dashes' \
  "$TMP/feat-login" '📁 primary-proj | 🌿 feat/login'

check_line2 'worktree name is shown when it differs from the branch' \
  "$TMP/scratch" '📁 primary-proj | 🌿 feat/other | scratch'

check_line2 'detached HEAD omits the branch item' \
  "$DETACHED" '📁 detached-proj'

check_line2 'a non-git directory shows only the folder name' \
  "$NONGIT" '📁 plain-folder'

run_statusline "$(jq -n --arg c "$PRIMARY" --arg p "$NONGIT" '{workspace:{current_dir:$c,project_dir:$p}}')"
if [ "$(line2)" = '📁 primary-proj | 🌿 main' ]; then
  ok 'current_dir wins over project_dir'
else
  not_ok "current_dir wins over project_dir: $(line2)"
fi

run_statusline "$(jq -n --arg p "$PRIMARY" '{workspace:{project_dir:$p}}')"
if [ "$(line2)" = '📁 primary-proj | 🌿 main' ]; then
  ok 'project_dir is used when current_dir is absent'
else
  not_ok "project_dir is used when current_dir is absent: $(line2)"
fi

section 'line 2: links'

run_statusline "$(json_dir "$PRIMARY")"
if printf '%s' "$(line2_raw)" | grep -qF "${ESC}]8;;https://example.invalid/owner/project/pulls${ESC}\\"; then
  ok "the project name links to the repo's pull request list"
else
  not_ok "the project name links to the repo's pull request list: $(line2_raw | od -c | head -5)"
fi

run_statusline "$(jq -n --arg d "$NONGIT" '{workspace:{current_dir:$d,repo:{host:"example.invalid",owner:"acme",name:"widgets"}}}')"
if printf '%s' "$(line2_raw)" | grep -qF "${ESC}]8;;https://example.invalid/acme/widgets/pulls${ESC}\\"; then
  ok 'the project link uses workspace.repo fields when present'
else
  not_ok 'the project link uses workspace.repo fields when present'
fi

CRED="$TMP/cred-proj"; mkdir -p "$CRED"
( cd "$CRED" && git init -q . && git remote add origin 'https://someuser:hunter2token@example.invalid/owner/project.git' ) ||
  { echo "credential fixture setup failed" >&2; exit 1; }
# The positive control (the clean link is present) keeps a script that drops
# the link entirely from passing the leak assertion for the wrong reason.
run_statusline "$(json_dir "$CRED")"
if printf '%s' "$OUT" | grep -qF 'https://example.invalid/owner/project/pulls' &&
   ! printf '%s' "$OUT" | grep -qF 'hunter2token' &&
   ! printf '%s' "$OUT" | grep -qF 'someuser'; then
  ok 'credentials in an https origin remote are not printed'
else
  not_ok "credentials in an https origin remote are not printed: $(printf '%s' "$OUT" | od -c | head -8)"
fi

section 'output hardening'

BADDIR="$TMP/bad${ESC}[31mname${BEL}"; mkdir -p "$BADDIR"
run_statusline "$(json_dir "$BADDIR")"
case "$OUT" in *"$BEL"*) bel=yes ;; *) bel=no ;; esac
if [ "$(line2)" = '📁 bad[31mname' ] && [ "$bel" = no ]; then
  ok 'control characters in the folder name are stripped'
else
  not_ok "control characters in the folder name are stripped (bel=$bel): $(line2)"
fi

BSDIR="$TMP"'/a\033b\nc'; mkdir -p "$BSDIR"
run_statusline "$(json_dir "$BSDIR")"
if [ "$(line2)" = '📁 a\033b\nc' ]; then
  ok 'literal backslash escapes in the folder name are printed literally'
else
  not_ok "literal backslash escapes in the folder name are printed literally: $(line2)"
fi

section 'line 1'

# Captured from the script as it was before line 2 changed, run from a non-git
# directory so later additions to line 2 cannot reach it.
GOLDEN_HEX='1b5b326d4f7075731b5b306d201b5b33356d686967681b5b306d201b5b326d7c1b5b306d201b5b33326d3432251b5b306d201b5b326d6374781b5b306d201b5b326d7c1b5b306d201b5b33336d3735251b5b306d201b5b326d35681b5b306d0a'
run_statusline "$(jq -n --arg d "$NONGIT" '{model:{display_name:"Opus"},effort:{level:"high"},workspace:{current_dir:$d},context_window:{used_percentage:42.4},rate_limits:{five_hour:{used_percentage:75}}}')"
got_hex="$(printf '%s\n' "$OUT" | sed -n 1p | od -An -tx1 | tr -d ' \n')"
if [ "$got_hex" = "$GOLDEN_HEX" ]; then
  ok 'line 1 is unchanged for a fixed input'
else
  not_ok "line 1 is unchanged for a fixed input: $got_hex"
fi

section 'git config hardening'

# A repo-local core.fsmonitor command must never run. The marker is the
# payload's only effect.
HOSTILE="$TMP/hostile"; mkdir -p "$HOSTILE"
( cd "$HOSTILE" && git init -q . && echo data > f.txt && git add f.txt && git commit -qm init &&
  git config core.fsmonitor "sh -c 'touch $TMP/PWNED_FSMON; exit 1'" &&
  echo changed > f.txt ) || { echo "hostile fixture setup failed" >&2; exit 1; }
rm -f "$TMP/PWNED_FSMON"
run_statusline "$(json_dir "$HOSTILE")"
if [ "$STATUS" = 0 ] && [ ! -e "$TMP/PWNED_FSMON" ] && [ "$(line2)" = '📁 hostile | 🌿 main' ]; then
  ok 'a repo-local core.fsmonitor command is not executed'
else
  not_ok "a repo-local core.fsmonitor command is not executed (status=$STATUS): $(line2)"
fi

# Source-level pin: the marker test above only fires if some git subcommand
# the script runs happens to consult fsmonitor, so the flags are pinned directly.
if grep -q 'GIT_CONFIG_NOSYSTEM=1' "$SCRIPT" &&
   grep -q 'core.fsmonitor=false' "$SCRIPT" &&
   grep -q 'core.hooksPath=/dev/null' "$SCRIPT" &&
   grep -q -- '--no-optional-locks' "$SCRIPT"; then
  ok 'git runs with system config, fsmonitor, hooks and optional locks disabled'
else
  not_ok 'git runs with system config, fsmonitor, hooks and optional locks disabled'
fi

section 'portability'

if sed 's/#.*//' "$SCRIPT" | grep -Eq '(^|[[:space:]])(mapfile|readarray|(declare|local)[[:space:]]+-A)([[:space:]]|$)'; then
  not_ok 'uses no bash 4 builtins'
else
  ok 'uses no bash 4 builtins'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
