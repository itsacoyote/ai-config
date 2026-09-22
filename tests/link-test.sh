#!/usr/bin/env bash
# link-test.sh — self-contained test suite for link.sh
#
# link.sh deletes inside the harness homes and points them at the checkout it
# runs from. The two unrecoverable failures are: running from a linked worktree
# (every link dangles when the worktree is removed) and writing or deleting
# outside a managed directory. Every such guard is mutation-tested below — the
# suite must go red if the guard is removed. Positive controls come before the
# refusal they pair with, so a guard that fires everywhere cannot pass its own
# refusal test for the wrong reason.
#
# Usage:  bash tests/link-test.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

set -u

pass=0
fail=0

ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LINK_SRC="${LINK_UNDER_TEST:-$REPO_ROOT/link.sh}"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/link-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp produced no directory" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Fake HOME. Nothing in this suite may touch the real one.
export HOME="$TMP/home"
mkdir -p "$HOME"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# Mini repo fixture mirroring the real top-level layout. The three worktree CLIs
# are stubs that log their invocation, so the suite can assert link.sh calls
# `<cli> install` without running the real CLIs.
STUB_LOG="$TMP/stub.log"
make_stub() {
  cat > "$1" <<EOF
#!/bin/sh
printf '%s %s\n' "\$(basename "\$0")" "\$*" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "$1"
}

make_fixture() {
  local fix="$1"
  mkdir -p "$fix"/claude/skills/foo "$fix"/claude/agents "$fix"/claude/rules \
    "$fix"/claude/references "$fix"/claude/scripts "$fix"/claude/hooks \
    "$fix"/agents/skills/bar "$fix"/pi/scripts "$fix"/codex/rules "$fix"/codex/scripts
  echo "skill-body" > "$fix/claude/skills/foo/SKILL.md"
  echo "agent-body" > "$fix/claude/agents/a.md"
  echo "rule-body" > "$fix/claude/rules/r.md"
  echo "ref-body" > "$fix/claude/references/ref.md"
  printf '#!/bin/sh\necho s\n' > "$fix/claude/scripts/s.sh" && chmod +x "$fix/claude/scripts/s.sh"
  printf '#!/bin/sh\necho h\n' > "$fix/claude/hooks/h.sh" && chmod +x "$fix/claude/hooks/h.sh"
  echo "claude-user-file" > "$fix/claude/CLAUDE.md"
  echo "statusline-body" > "$fix/claude/statusline-command.sh"
  echo "shared-skill-body" > "$fix/agents/skills/bar/SKILL.md"
  echo "agents-user-file" > "$fix/agents/AGENTS.md"
  echo "pi-user-file" > "$fix/pi/AGENTS.md"
  echo "rules-body" > "$fix/codex/rules/ai-config.rules"
  make_stub "$fix/claude/scripts/clwt"
  make_stub "$fix/codex/scripts/cwt"
  make_stub "$fix/pi/scripts/pwt"
  cp "$LINK_SRC" "$fix/link.sh"
}

# A fixture that is a real primary repository, because the primary-checkout
# guard reads git state.
make_repo_fixture() {
  local fix="$1"
  make_fixture "$fix"
  ( cd "$fix" && git init -q . && git add -A && git commit -qm init ) || return 1
}

FIX="$TMP/repo"
make_repo_fixture "$FIX" || { echo "fixture setup failed" >&2; exit 1; }

# run_link <fixture-dir> [args...] — runs that fixture's link.sh from an unrelated
# cwd, captures stdout+stderr in OUT and the exit status in STATUS.
OUT=''
STATUS=0
run_link() {
  local fix="$1"; shift
  OUT="$(cd "$TMP" && bash "$fix/link.sh" "$@" 2>&1)"
  STATUS=$?
}

# ---------------------------------------------------------------- arguments

section 'arguments'

run_link "$FIX" --help
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q 'Usage:'; then
  ok 'prints usage with --help'
else
  not_ok "prints usage with --help (status=$STATUS)"
fi

run_link "$FIX" --bogus
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'unknown argument'; then
  ok 'dies on unknown flag'
else
  not_ok "dies on unknown flag (status=$STATUS)"
fi

# ----------------------------------------------------------------- guards

section 'repo resolution and guards'

# run_link always runs from $TMP, so a link.sh that resolved its repo from $PWD
# would fail the source-root guard here.
run_link "$FIX" --dry-run
if [ "$STATUS" = 0 ]; then
  ok 'resolves repo root from BASH_SOURCE when invoked from another cwd'
else
  not_ok "resolves repo root from BASH_SOURCE when invoked from another cwd (status=$STATUS): $OUT"
fi

# Positive control for the worktree refusal below. Without it, a guard that
# compares git's relative ".git" against an absolute path fires in every primary
# checkout, and the refusal test still goes green — for the wrong reason.
if [ "$STATUS" = 0 ] && ! printf '%s' "$OUT" | grep -q 'linked worktree'; then
  ok 'runs from a primary checkout'
else
  not_ok "runs from a primary checkout (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): links point into the checkout link.sh runs from, and a
# linked worktree is disposable. Remove the common-dir comparison and this goes red.
WT="$TMP/wt"
( cd "$FIX" && git worktree add -q "$WT" -b wt-branch ) || not_ok 'fixture: worktree add'
run_link "$WT" --dry-run
FIX_P="$(cd "$FIX" && pwd -P)"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'linked worktree' &&
   printf '%s' "$OUT" | grep -qF -- "$FIX_P"; then
  ok 'refuses to run from a linked worktree and names the primary checkout'
else
  not_ok "refuses to run from a linked worktree and names the primary checkout (status=$STATUS): $OUT"
fi

NOGIT="$TMP/nogit"
make_fixture "$NOGIT"
run_link "$NOGIT" --dry-run
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q 'not a git repository'; then
  ok 'warns and continues outside any repository'
else
  not_ok "warns and continues outside any repository (status=$STATUS): $OUT"
fi

# GUARD: a partial checkout must not be linked, or the clean would delete what
# the missing tree should have provided.
NOSRC="$TMP/nosrc"
make_fixture "$NOSRC"
rm -rf "$NOSRC/claude"
run_link "$NOSRC" --dry-run
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'missing source root'; then
  ok 'dies when the claude source root is missing'
else
  not_ok "dies when the claude source root is missing (status=$STATUS): $OUT"
fi

# GUARD: a copy of the library inside a harness home would link the home to itself.
INHOME="$HOME/.claude/fixture"
make_fixture "$INHOME"
run_link "$INHOME" --dry-run
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'inside'; then
  ok 'dies when link.sh itself lives under a harness home'
else
  not_ok "dies when link.sh itself lives under a harness home (status=$STATUS): $OUT"
fi
rm -rf "$HOME/.claude"

# ------------------------------------------------------------- portability

section 'portability'

# macOS ships bash 3.2, where mapfile/readarray and associative arrays do not
# exist; a bash 4 builtin fails silently there rather than loudly. Positive
# control first: prove the pattern matches before trusting its negative.
BASH4_RE='(^|[[:space:]])(mapfile|readarray|(declare|local)[[:space:]]+-A)([[:space:]]|$)'
if printf 'mapfile -t x\n' | grep -Eq "$BASH4_RE"; then
  if sed 's/#.*//' "$LINK_SRC" | grep -Eq "$BASH4_RE"; then
    not_ok 'link.sh uses no bash 4 builtins'
  else
    ok 'link.sh uses no bash 4 builtins'
  fi
else
  not_ok 'link.sh uses no bash 4 builtins (positive control failed: pattern did not match its own sample)'
fi

# Same rule as clwt: the tooling stays pure bash.
if grep -q 'python' "$LINK_SRC"; then
  not_ok 'no python dependency'
else
  ok 'no python dependency'
fi

# git -C is denied by the maintainer's settings; a script that used it would be
# unrunnable by an agent asked to check it and confusing in the allowlist.
if grep -Eq 'git[[:space:]]+-C' "$LINK_SRC"; then
  not_ok 'link.sh never uses git -C'
else
  ok 'link.sh never uses git -C'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
