#!/usr/bin/env bash
# beads-gate-test.sh — self-contained test suite for claude/hooks/beads-gate.sh
#
# The hook runs globally (from ~/.claude/hooks) in EVERY repo, so its silence
# where beads is absent is the load-bearing behavior: any output here lands in
# unrelated projects' sessions. This suite exists because the pre-hardening
# hook warned loudly in every non-beads repo — and its jq-missing warning fired
# BEFORE beads detection, so a jq-less machine warned everywhere too. Both
# regressions are pinned below.
#
# Usage:  bash claude/scripts/tests/beads-gate-test.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

set -u

pass=0
fail=0

ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOOKS_SRC="$REPO_ROOT/claude/hooks"
REFS_SRC="$REPO_ROOT/claude/references"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/beads-gate-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Install-shaped copy: the hook resolves beads-preflight.sh relative to its own
# location (../references), so the fixture mirrors the ~/.claude layout rather
# than running the hook in place — running in place would also pick up THIS
# repo's real .beads and make the absent-beads cases impossible to stage.
FAKE_CLAUDE="$TMP/dot-claude"
mkdir -p "$FAKE_CLAUDE/hooks" "$FAKE_CLAUDE/references"
cp "$HOOKS_SRC/beads-gate.sh" "$FAKE_CLAUDE/hooks/"
cp "$REFS_SRC/beads-preflight.sh" "$FAKE_CLAUDE/references/"
GATE="$FAKE_CLAUDE/hooks/beads-gate.sh"

# Stub bd: detection needs `command -v bd` to succeed and the present-case
# output comes from `bd ready`. A stub keeps the suite independent of a real
# beads install.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/bd" <<'EOF'
#!/bin/sh
echo "stub-ready-output"
EOF
chmod +x "$STUB_BIN/bd"
PATH_WITH_BD="$STUB_BIN:$PATH"

# A PATH with every tool the hook legitimately needs EXCEPT jq — dropping the
# whole system PATH would break the hook for the wrong reason (no sh/dirname/git)
# and pass the silence assertion vacuously.
NOJQ_BIN="$TMP/nojq-bin"
mkdir -p "$NOJQ_BIN"
for tool in sh bash dirname git grep sed; do
  src="$(command -v "$tool")" && ln -s "$src" "$NOJQ_BIN/$tool"
done
PATH_NO_JQ="$STUB_BIN:$NOJQ_BIN"

# Isolate git so fixtures never see the developer's config.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

run_gate() {
  # $1 = dir to run from, rest = PATH to use. Captures stdout+stderr and exit.
  _dir="$1"; _path="$2"
  GATE_OUT="$(cd "$_dir" && PATH="$_path" bash "$GATE" 2>&1)"
  GATE_STATUS=$?
}

section 'silence where beads is absent'

NONGIT="$TMP/plain-dir"
mkdir -p "$NONGIT"
run_gate "$NONGIT" "$PATH_WITH_BD"
# Regression pin: pre-hardening, this printed a "requires beads" WARNING in
# every non-beads directory. Silence (not just exit 0) is the assertion.
if [ "$GATE_STATUS" = 0 ] && [ -z "$GATE_OUT" ]; then
  ok 'non-git directory: silent, exit 0'
else
  not_ok "non-git directory: silent, exit 0 (status=$GATE_STATUS out='$GATE_OUT')"
fi

PLAINREPO="$TMP/plain-repo"
git init -q "$PLAINREPO"
run_gate "$PLAINREPO" "$PATH_WITH_BD"
if [ "$GATE_STATUS" = 0 ] && [ -z "$GATE_OUT" ]; then
  ok 'git repo without beads: silent, exit 0'
else
  not_ok "git repo without beads: silent, exit 0 (status=$GATE_STATUS out='$GATE_OUT')"
fi

# Regression pin: the jq-missing warning used to fire BEFORE beads detection,
# so a jq-less machine warned in every repo. Detection must come first — this
# fails if the early jq branch is restored. PATH carries the bd stub and core
# tools, but no jq.
run_gate "$PLAINREPO" "$PATH_NO_JQ"
if [ "$GATE_STATUS" = 0 ] && [ -z "$GATE_OUT" ]; then
  ok 'git repo without beads, jq absent: still silent, exit 0'
else
  not_ok "git repo without beads, jq absent: still silent, exit 0 (status=$GATE_STATUS out='$GATE_OUT')"
fi

section 'output where beads is present'

BEADSREPO="$TMP/beads-repo"
git init -q "$BEADSREPO"
mkdir -p "$BEADSREPO/.beads"
run_gate "$BEADSREPO" "$PATH_WITH_BD"
if [ "$GATE_STATUS" = 0 ] && printf '%s' "$GATE_OUT" | grep -q 'stub-ready-output' &&
  printf '%s' "$GATE_OUT" | grep -q '"hookEventName":"SessionStart"'; then
  ok 'beads repo: emits ready-summary JSON'
else
  not_ok "beads repo: emits ready-summary JSON (status=$GATE_STATUS out='$GATE_OUT')"
fi

# Worktrees have no .beads/ of their own — detection must go through the git
# common dir (the naive `test -d .beads` fallback fails exactly here).
( cd "$BEADSREPO" && git commit -q --allow-empty -m init &&
  git worktree add -q "$TMP/beads-wt" -b wt-branch ) 2>/dev/null
run_gate "$TMP/beads-wt" "$PATH_WITH_BD"
if [ "$GATE_STATUS" = 0 ] && printf '%s' "$GATE_OUT" | grep -q 'stub-ready-output'; then
  ok 'worktree of a beads repo: still detects beads'
else
  not_ok "worktree of a beads repo: still detects beads (status=$GATE_STATUS out='$GATE_OUT')"
fi

if [ "$GATE_STATUS" = 0 ] && command -v jq >/dev/null 2>&1; then
  # The context payload must be valid JSON (jq -Rs encoding, not hand-rolled).
  if printf '%s' "$GATE_OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    ok 'present-case output parses as the hook JSON schema'
  else
    not_ok 'present-case output parses as the hook JSON schema'
  fi
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
