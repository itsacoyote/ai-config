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
  : > "$fix/claude/hooks/.gitkeep"
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

# ---------------------------------------------------------------- linking

section 'linking'

# run_link_home <home> <fixture-dir> [args...] — like run_link with its own HOME,
# so each scenario starts from an empty fake home.
run_link_home() {
  local h="$1" fix="$2"; shift 2
  mkdir -p "$h"
  OUT="$(cd "$TMP" && HOME="$h" bash "$fix/link.sh" "$@" 2>&1)"
  STATUS=$?
}

H1="$TMP/h1"
run_link_home "$H1" "$FIX"
all_linked=1
for p in skills/foo agents/a.md rules/r.md references/ref.md scripts/s.sh hooks/h.sh; do
  [ -L "$H1/.claude/$p" ] || all_linked=0
done
if [ "$STATUS" = 0 ] && [ "$all_linked" = 1 ]; then
  ok 'links every top-level entry of the six claude dirs'
else
  not_ok "links every top-level entry of the six claude dirs (status=$STATUS): $OUT"
fi

singles_linked=1
for p in .claude/CLAUDE.md .claude/statusline-command.sh .codex/AGENTS.md .codex/rules/ai-config.rules .pi/agent/AGENTS.md; do
  [ -L "$H1/$p" ] || singles_linked=0
done
if [ "$singles_linked" = 1 ]; then
  ok 'links CLAUDE.md, statusline, codex AGENTS.md, codex rules, pi AGENTS.md as single files'
else
  not_ok 'links CLAUDE.md, statusline, codex AGENTS.md, codex rules, pi AGENTS.md as single files'
fi

if [ -L "$H1/.agents/skills/bar" ] && [ -f "$H1/.agents/skills/bar/SKILL.md" ]; then
  ok 'links agents/skills entries into ~/.agents/skills'
else
  not_ok 'links agents/skills entries into ~/.agents/skills'
fi

case "$(readlink "$H1/.claude/skills/foo")" in
  /*) ok 'writes absolute symlink targets' ;;
  *) not_ok "writes absolute symlink targets (got $(readlink "$H1/.claude/skills/foo"))" ;;
esac

if [ ! -e "$H1/.claude/hooks/.gitkeep" ] && [ ! -L "$H1/.claude/hooks/.gitkeep" ]; then
  ok 'does not link .gitkeep from a source dir'
else
  not_ok 'does not link .gitkeep from a source dir'
fi

run_link_home "$H1" "$FIX"
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q '^no changes'; then
  ok 'second run reports no changes'
else
  not_ok "second run reports no changes (status=$STATUS): $OUT"
fi

# The repoint target is a managed-dir entry on purpose: Task 6's clean must keep
# treating a desired-name symlink as a repoint, never a delete, so this test keeps
# its meaning after that task lands.
ELSEWHERE="$TMP/elsewhere"; mkdir -p "$ELSEWHERE"
ln -sfn "$ELSEWHERE" "$H1/.claude/skills/foo"
run_link_home "$H1" "$FIX"
if [ "$STATUS" = 0 ] && [ "$(readlink "$H1/.claude/skills/foo")" = "$FIX_P/claude/skills/foo" ] &&
   printf '%s' "$OUT" | grep -q '^repoint'; then
  ok 'repoints a symlink whose target moved'
else
  not_ok "repoints a symlink whose target moved (status=$STATUS): $OUT"
fi

if [ -z "$(find "$H1" -name '.*.link.*' 2>/dev/null)" ] && [ -e "$H1/.claude/skills/foo/SKILL.md" ]; then
  ok 'never leaves a target unresolvable during repoint'
else
  not_ok 'never leaves a target unresolvable during repoint'
fi

H2="$TMP/h2"; mkdir -p "$H2/.claude"
cp "$FIX/claude/CLAUDE.md" "$H2/.claude/CLAUDE.md"
run_link_home "$H2" "$FIX"
if [ "$STATUS" = 0 ] && [ -L "$H2/.claude/CLAUDE.md" ] && printf '%s' "$OUT" | grep -q '^replace'; then
  ok 'replaces a byte-identical real file at a single-file target'
else
  not_ok "replaces a byte-identical real file at a single-file target (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): a differing real file is someone else's data. Remove the
# fatal-count exit and both of the next two go red: the real run writes links
# next to the untouched file, and dry-run exits 0.
H3="$TMP/h3"; mkdir -p "$H3/.claude"
echo "hand-edited" > "$H3/.claude/CLAUDE.md"
run_link_home "$H3" "$FIX" --dry-run
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q '^FATAL .*CLAUDE.md' && [ ! -e "$H3/.claude/skills" ]; then
  ok 'dry-run exits 2 and lists the FATAL pair when a differing real file exists'
else
  not_ok "dry-run exits 2 and lists the FATAL pair when a differing real file exists (status=$STATUS): $OUT"
fi
run_link_home "$H3" "$FIX"
if [ "$STATUS" = 2 ] && [ ! -e "$H3/.claude/skills" ] && [ ! -L "$H3/.claude/CLAUDE.md" ] &&
   [ "$(cat "$H3/.claude/CLAUDE.md")" = "hand-edited" ]; then
  ok 'reports a differing real file at a single-file target as FATAL and changes nothing'
else
  not_ok "reports a differing real file at a single-file target as FATAL and changes nothing (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): a symlinked parent that resolves outside HOME would
# redirect every write. Make contained_reason return nothing and this goes red:
# the marker directory outside HOME fills with links.
H4="$TMP/h4"; mkdir -p "$H4"
OUTSIDE="$TMP/outside"; mkdir -p "$OUTSIDE"
ln -s "$OUTSIDE" "$H4/.claude"
run_link_home "$H4" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'outside HOME' && [ -z "$(ls -A "$OUTSIDE")" ]; then
  ok 'dies when a parent component is a symlink resolving outside HOME'
else
  not_ok "dies when a parent component is a symlink resolving outside HOME (status=$STATUS): $OUT"
fi

H5="$TMP/h5"
run_link_home "$H5" "$FIX" --dry-run
if [ "$STATUS" = 0 ] && [ ! -e "$H5/.claude" ] && [ ! -e "$H5/.agents" ] && [ ! -e "$H5/.codex" ] && [ ! -e "$H5/.pi" ] &&
   printf '%s' "$OUT" | grep -q '^link ' && printf '%s' "$OUT" | grep -q 'dry run: nothing written'; then
  ok 'dry-run prints the plan and writes nothing'
else
  not_ok "dry-run prints the plan and writes nothing (status=$STATUS): $OUT"
fi

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
