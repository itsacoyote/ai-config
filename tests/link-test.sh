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
  echo "dot-rule-body" > "$fix/claude/rules/.dotrule.md"
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

# run_link_home <home> <fixture-dir> [args...] — like run_link with its own HOME,
# so each scenario starts from an empty fake home.
run_link_home() {
  local h="$1" fix="$2"; shift 2
  mkdir -p "$h"
  OUT="$(cd "$TMP" && HOME="$h" bash "$fix/link.sh" "$@" 2>&1)"
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

# Same guard through a symlinked home: ~/.claude -> realclaude, checkout under
# realclaude. An unresolved home path never matches the resolved $REPO.
H17="$TMP/h17"; mkdir -p "$H17" "$TMP/realclaude"
ln -s "$TMP/realclaude" "$H17/.claude"
make_fixture "$TMP/realclaude/fixture"
run_link_home "$H17" "$TMP/realclaude/fixture" --dry-run
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'refusing to run from inside'; then
  ok 'dies when link.sh lives under a harness home reached through a symlink'
else
  not_ok "dies when link.sh lives under a harness home reached through a symlink (status=$STATUS): $OUT"
fi

# ---------------------------------------------------------------- linking

section 'linking'

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

# ----------------------------------------------------------- private root

section 'private root'

make_private() {
  local h="$1"
  mkdir -p "$h/.ai-private/claude/skills/priv" "$h/.ai-private/agents/skills/pbar"
  echo "private-skill" > "$h/.ai-private/claude/skills/priv/SKILL.md"
  echo "private-shared-skill" > "$h/.ai-private/agents/skills/pbar/SKILL.md"
}

H6="$TMP/h6"; mkdir -p "$H6"; make_private "$H6"
run_link_home "$H6" "$FIX"
if [ "$STATUS" = 0 ] && [ -L "$H6/.claude/skills/priv" ] && [ -L "$H6/.agents/skills/pbar" ] &&
   [ -L "$H6/.claude/skills/foo" ]; then
  ok 'links entries from the private root alongside the repo'
else
  not_ok "links entries from the private root alongside the repo (status=$STATUS): $OUT"
fi

H7="$TMP/h7"
run_link_home "$H7" "$FIX" --dry-run
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q 'private directory .* not found'; then
  ok 'exits 0 with a note when the private dir is absent'
else
  not_ok "exits 0 with a note when the private dir is absent (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): a name in both roots must stop the run before any write.
# Remove the die in check_conflicts and this goes red: the run proceeds and links.
H8="$TMP/h8"; mkdir -p "$H8/.ai-private/claude/skills/foo"
echo "shadow" > "$H8/.ai-private/claude/skills/foo/SKILL.md"
run_link_home "$H8" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'claude/skills/foo' &&
   printf '%s' "$OUT" | grep -qi 'conflict' && [ ! -e "$H8/.claude" ]; then
  ok 'fails with the conflicting name and changes nothing when both roots ship the same entry'
else
  not_ok "fails with the conflicting name and changes nothing when both roots ship the same entry (status=$STATUS): $OUT"
fi

H9="$TMP/h9"; mkdir -p "$H9/.ai-private/claude/skills/foo" "$H9/.ai-private/agents/skills/bar"
echo "shadow" > "$H9/.ai-private/claude/skills/foo/SKILL.md"
echo "shadow" > "$H9/.ai-private/agents/skills/bar/SKILL.md"
run_link_home "$H9" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'claude/skills/foo' &&
   printf '%s' "$OUT" | grep -q 'agents/skills/bar'; then
  ok 'reports every conflict, not just the first'
else
  not_ok "reports every conflict, not just the first (status=$STATUS): $OUT"
fi

# ------------------------------------------------------------------ clean

section 'clean'

# A linked home to dirty up: everything below starts from a correct first run.
H10="$TMP/h10"
run_link_home "$H10" "$FIX"
[ "$STATUS" = 0 ] || not_ok "fixture: first run into h10 failed: $OUT"

KEEP="$TMP/keep"; mkdir -p "$KEEP"; echo marker > "$KEEP/marker"
ln -s "$KEEP" "$H10/.claude/skills/stale"
run_link_home "$H10" "$FIX" --dry-run
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q "^delete    $H10/.claude/skills/stale (symlink)" && [ -L "$H10/.claude/skills/stale" ]; then
  ok 'lists a stale symlink for deletion in dry-run and leaves it in place'
else
  not_ok "lists a stale symlink for deletion in dry-run and leaves it in place (status=$STATUS): $OUT"
fi
run_link_home "$H10" "$FIX"
if [ "$STATUS" = 0 ] && [ ! -L "$H10/.claude/skills/stale" ] && [ ! -e "$H10/.claude/skills/stale" ]; then
  ok 'deletes a stale symlink the plan does not produce'
else
  not_ok "deletes a stale symlink the plan does not produce (status=$STATUS): $OUT"
fi

# GUARD: rm on a symlinked directory must remove the link, not its target.
if [ -f "$KEEP/marker" ]; then
  ok 'removing a symlinked directory removes the link, not its target'
else
  not_ok 'removing a symlinked directory removes the link, not its target'
fi

echo stray > "$H10/.claude/rules/stray.md"
mkdir -p "$H10/.claude/skills/straydir"; echo x > "$H10/.claude/skills/straydir/x"
mkdir -p "$H10/.claude/skills/.hidden"; echo x > "$H10/.claude/skills/.hidden/x"
run_link_home "$H10" "$FIX" --dry-run
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q "^delete    $H10/.claude/rules/stray.md (file)" && [ -f "$H10/.claude/rules/stray.md" ]; then
  ok 'lists a stray real file for deletion in dry-run first'
else
  not_ok "lists a stray real file for deletion in dry-run first (status=$STATUS): $OUT"
fi
if printf '%s' "$OUT" | grep -q "^delete    $H10/.claude/skills/straydir (dir)" && [ -d "$H10/.claude/skills/straydir" ]; then
  ok 'lists a stray real directory for deletion in dry-run first'
else
  not_ok "lists a stray real directory for deletion in dry-run first: $OUT"
fi
# GUARD (mutation-tested): the managed-dir pass must see dot entries. Swap its
# find for a glob and this goes red while every other clean test stays green.
if printf '%s' "$OUT" | grep -q "^delete    $H10/.claude/skills/.hidden (dir)"; then
  ok 'lists a stray dot-directory for deletion in dry-run'
else
  not_ok "lists a stray dot-directory for deletion in dry-run: $OUT"
fi
run_link_home "$H10" "$FIX"
if [ "$STATUS" = 0 ] && [ ! -e "$H10/.claude/rules/stray.md" ] && [ ! -e "$H10/.claude/skills/straydir" ] && [ ! -e "$H10/.claude/skills/.hidden" ]; then
  ok 'deletes stray file, directory, and dot-directory'
else
  not_ok "deletes stray file, directory, and dot-directory (status=$STATUS): $OUT"
fi

if [ -L "$H10/.claude/rules/.dotrule.md" ]; then
  ok 'links a dot entry from a source root'
else
  not_ok 'links a dot entry from a source root'
fi

# GUARD (mutation-tested): a real file with a desired name inside a managed dir is
# an extra, deleted then linked. The contents DIFFER from the source on purpose:
# an identical file would take plan_entry's replace branch and pass this without
# the clean doing anything. Remove the "non-symlink is an extra" rule and this
# exits 2 with a FATAL.
H11="$TMP/h11"; mkdir -p "$H11/.codex/rules"
echo "old-copy" > "$H11/.codex/rules/ai-config.rules"
run_link_home "$H11" "$FIX"
if [ "$STATUS" = 0 ] && [ -L "$H11/.codex/rules/ai-config.rules" ] &&
   printf '%s' "$OUT" | grep -q "^delete    $H11/.codex/rules/ai-config.rules (file)"; then
  ok 'replaces a differing real file that shares a desired name and does not exit 2'
else
  not_ok "replaces a differing real file that shares a desired name and does not exit 2 (status=$STATUS): $OUT"
fi
if printf '%s\n' "$OUT" | grep -A1 "^delete    $H11/.codex/rules/ai-config.rules" | tail -1 | grep -q "^link      $H11/.codex/rules/ai-config.rules"; then
  ok 'delete and link for one entry are consecutive plan lines'
else
  not_ok "delete and link for one entry are consecutive plan lines: $OUT"
fi

# GUARD (mutation-tested): harness-owned entries survive. Empty the allowlist and
# this goes red.
H12="$TMP/h12"; mkdir -p "$H12/.claude/skills/synced/abc" "$H12/.codex/rules" "$H12/.codex/skills/.system" "$H12/.codex/skills/foo"
echo manifest > "$H12/.claude/skills/synced/abc/manifest.json"
echo approved > "$H12/.codex/rules/default.rules"
echo marker > "$H12/.codex/skills/.system/marker"
echo f > "$H12/.codex/skills/foo/f"
: > "$H12/.claude/skills/.DS_Store"
echo notes > "$H12/.claude/notes.txt"
echo toml > "$H12/.codex/config.toml"
run_link_home "$H12" "$FIX"
if [ "$STATUS" = 0 ] && [ -f "$H12/.claude/skills/synced/abc/manifest.json" ] && [ -f "$H12/.codex/rules/default.rules" ] &&
   ! printf '%s' "$OUT" | grep -q 'synced' && ! printf '%s' "$OUT" | grep -q 'default.rules'; then
  ok 'keeps allowlisted entries through a full clean'
else
  not_ok "keeps allowlisted entries through a full clean (status=$STATUS): $OUT"
fi
if [ -f "$H12/.codex/skills/.system/marker" ] && [ -f "$H12/.codex/skills/foo/f" ] && ! printf '%s' "$OUT" | grep -q 'codex/skills'; then
  ok 'never enumerates ~/.codex/skills'
else
  not_ok "never enumerates ~/.codex/skills: $OUT"
fi
if [ -f "$H12/.claude/notes.txt" ] && [ -f "$H12/.codex/config.toml" ]; then
  ok "never enumerates a managed dir's parent"
else
  not_ok "never enumerates a managed dir's parent"
fi
run_link_home "$H12" "$FIX"
if [ "$STATUS" = 0 ] && [ -f "$H12/.claude/skills/.DS_Store" ] && printf '%s' "$OUT" | grep -q '^no changes'; then
  ok 'ignores .DS_Store and still reports no changes on the second run'
else
  not_ok "ignores .DS_Store and still reports no changes on the second run (status=$STATUS): $OUT"
fi

# Desired-name symlinks are repointed, never deleted: a moved checkout repairs
# with repoints instead of a wall of deletes at the destructive gate.
ln -sfn "$ELSEWHERE" "$H12/.claude/skills/foo"
run_link_home "$H12" "$FIX"
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q "^repoint   $H12/.claude/skills/foo" &&
   ! printf '%s' "$OUT" | grep -q "^delete    $H12/.claude/skills/foo"; then
  ok 'repoints a stale symlink whose name is in the desired set instead of deleting it'
else
  not_ok "repoints a stale symlink whose name is in the desired set instead of deleting it (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): a managed dir that is itself a symlink is never cleaned
# through. Remove the -L check in plan_clean and this goes red.
H13="$TMP/h13"; mkdir -p "$H13/.claude" "$H13/rulesdir"
echo keep > "$H13/rulesdir/keep.md"
ln -s "$H13/rulesdir" "$H13/.claude/rules"
run_link_home "$H13" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'managed directory is a symlink' &&
   [ -f "$H13/rulesdir/keep.md" ] && [ ! -e "$H13/.claude/skills" ]; then
  ok 'refuses to clean when the managed dir is itself a symlink'
else
  not_ok "refuses to clean when the managed dir is itself a symlink (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): containment is a property of the clean itself. With
# ~/.claude a symlink to a directory outside HOME that already holds entries, no
# delete may be planned through it. Remove the contained_reason call at the top
# of plan_clean and this goes red: the plan lists deletes under the outside dir
# (the run still exits 2 via plan_entry, which is why the assertion is on the
# plan lines, not on the files).
H15="$TMP/h15"; mkdir -p "$H15"
OUTSIDE2="$TMP/outside2"; mkdir -p "$OUTSIDE2/skills/victim" "$OUTSIDE2/rules"
echo x > "$OUTSIDE2/skills/victim/x"; echo precious > "$OUTSIDE2/rules/precious.md"
ln -s "$OUTSIDE2" "$H15/.claude"
run_link_home "$H15" "$FIX"
if [ "$STATUS" = 2 ] && ! printf '%s\n' "$OUT" | grep -q '^delete ' &&
   [ -f "$OUTSIDE2/skills/victim/x" ] && [ -f "$OUTSIDE2/rules/precious.md" ]; then
  ok 'never plans a delete through a managed dir whose parent resolves outside HOME'
else
  not_ok "never plans a delete through a managed dir whose parent resolves outside HOME (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): an entry name containing a newline must stay one
# entry. Switch the managed-dir reader back to newline-delimited find|read and
# this goes red: the second fragment "victim" is planned as a relative delete
# and removed from the cwd link.sh runs in ($TMP).
VICTIM="$TMP/victim"; mkdir -p "$VICTIM"; echo marker > "$VICTIM/marker"
EVIL="$H10/.claude/skills/$(printf 'evil\nvictim')"
mkdir -p "$EVIL"
run_link_home "$H10" "$FIX"
if [ "$STATUS" = 0 ] && [ ! -e "$EVIL" ] && [ -f "$VICTIM/marker" ] &&
   ! printf '%s\n' "$OUT" | grep -q '^delete    victim'; then
  ok 'treats an entry name containing a newline as one entry'
else
  not_ok "treats an entry name containing a newline as one entry (status=$STATUS): $OUT"
fi

# Under pipefail a grep that matches nothing is exit 1; both of these once ended
# the run with no message.
H16="$TMP/h16"; mkdir -p "$H16/.claude"
printf '{"permissions":{"allow":[]}}\n' > "$H16/.claude/settings.json"
run_link_home "$H16" "$FIX"
if [ "$STATUS" = 0 ] && [ -L "$H16/.claude/skills/foo" ]; then
  ok 'runs with a settings file that registers no hook'
else
  not_ok "runs with a settings file that registers no hook (status=$STATUS): $OUT"
fi

NOGK="$TMP/nogk"
make_fixture "$NOGK"
rm -f "$NOGK/claude/references/ref.md"; : > "$NOGK/claude/references/.gitkeep"
run_link_home "$TMP/h16b" "$NOGK" --dry-run
if [ "$STATUS" = 0 ] && ! printf '%s\n' "$OUT" | grep -q 'references/'; then
  ok 'runs when a source dir holds only .gitkeep'
else
  not_ok "runs when a source dir holds only .gitkeep (status=$STATUS): $OUT"
fi

# Registered-hook guard. Positive control first: a registered hook that a source
# root provides is deleted then linked like any other real file.
H14="$TMP/h14"; mkdir -p "$H14/.claude/hooks"
echo "old-hook" > "$H14/.claude/hooks/h.sh"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash ~/.claude/hooks/h.sh"}]}]}}\n' > "$H14/.claude/settings.json"
run_link_home "$H14" "$FIX"
if [ "$STATUS" = 0 ] && [ -L "$H14/.claude/hooks/h.sh" ]; then
  ok 'a registered hook that a source root provides is replaced normally'
else
  not_ok "a registered hook that a source root provides is replaced normally (status=$STATUS): $OUT"
fi
# GUARD (mutation-tested): a registered hook with no source is never deleted.
# Remove is_registered_hook from plan_clean and this goes red: orphan.sh is gone.
echo "orphan" > "$H14/.claude/hooks/orphan.sh"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash ~/.claude/hooks/orphan.sh"}]}]}}\n' > "$H14/.claude/settings.json"
run_link_home "$H14" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'orphan.sh.*registered' && [ -f "$H14/.claude/hooks/orphan.sh" ]; then
  ok 'refuses to delete a hook that settings.json references and the plan does not re-create'
else
  not_ok "refuses to delete a hook that settings.json references and the plan does not re-create (status=$STATUS): $OUT"
fi
rm -f "$H14/.claude/settings.json"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash ~/.claude/hooks/orphan.sh"}]}]}}\n' > "$H14/.claude/settings.local.json"
run_link_home "$H14" "$FIX"
if [ "$STATUS" = 2 ] && [ -f "$H14/.claude/hooks/orphan.sh" ]; then
  ok 'reads hook registrations from settings.local.json too'
else
  not_ok "reads hook registrations from settings.local.json too (status=$STATUS): $OUT"
fi
rm -f "$H14/.claude/settings.local.json"
run_link_home "$H14" "$FIX"
if [ "$STATUS" = 0 ] && [ ! -e "$H14/.claude/hooks/orphan.sh" ]; then
  ok 'runs with no settings file present and deletes the now-unregistered hook'
else
  not_ok "runs with no settings file present and deletes the now-unregistered hook (status=$STATUS): $OUT"
fi

# -------------------------------------------------------------- links.txt

section 'links.txt'

TAB="$(printf '\t')"

# make_links <home> <lines...> — private dir with a work-rules file and a links.txt
make_links() {
  local h="$1"; shift
  mkdir -p "$h/.ai-private"
  echo "work-rules" > "$h/.ai-private/work-rules.md"
  printf '%s\n' "$@" > "$h/.ai-private/links.txt"
}

H18="$TMP/h18"; mkdir -p "$H18"
make_links "$H18" \
  "# work-scope rules" \
  "" \
  "$H18/.ai-private/work-rules.md${TAB}$H18/work/CLAUDE.md" \
  "~/.ai-private/work-rules.md${TAB}~/work2/CLAUDE.md"
run_link_home "$H18" "$FIX"
if [ "$STATUS" = 0 ] && [ -L "$H18/work/CLAUDE.md" ] && [ -L "$H18/work2/CLAUDE.md" ] &&
   [ "$(cat "$H18/work/CLAUDE.md")" = "work-rules" ]; then
  ok 'links each source-tab-target pair and skips blank and comment lines'
else
  not_ok "links each source-tab-target pair and skips blank and comment lines (status=$STATUS): $OUT"
fi
if [ "$(readlink "$H18/work2/CLAUDE.md")" = "$H18/.ai-private/work-rules.md" ]; then
  ok 'expands a leading tilde in source and target'
else
  not_ok "expands a leading tilde in source and target (got $(readlink "$H18/work2/CLAUDE.md"))"
fi
if [ -d "$H18/work" ]; then
  ok 'creates a missing target parent directory'
else
  not_ok 'creates a missing target parent directory'
fi
run_link_home "$H18" "$FIX"
if [ "$STATUS" = 0 ] && printf '%s' "$OUT" | grep -q '^no changes'; then
  ok 'links.txt pairs are idempotent'
else
  not_ok "links.txt pairs are idempotent (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): a target outside HOME is rejected before anything is
# planned from the file. Remove the outside-HOME case and this goes red: the
# link lands under $TMP/outside3.
H19="$TMP/h19"; mkdir -p "$H19"; OUTSIDE3="$TMP/outside3"; mkdir -p "$OUTSIDE3"
make_links "$H19" "$H19/.ai-private/work-rules.md${TAB}$OUTSIDE3/CLAUDE.md"
run_link_home "$H19" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 1: target is outside HOME' &&
   [ ! -e "$OUTSIDE3/CLAUDE.md" ] && [ ! -L "$OUTSIDE3/CLAUDE.md" ] && [ ! -e "$H19/.claude" ]; then
  ok 'rejects a target outside HOME and changes nothing'
else
  not_ok "rejects a target outside HOME and changes nothing (status=$STATUS): $OUT"
fi

H20="$TMP/h20"; mkdir -p "$H20"
make_links "$H20" "# comment" "$H20/.ai-private/work-rules.md $H20/work/CLAUDE.md"
run_link_home "$H20" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 2: no tab'; then
  ok 'rejects a line without a tab, naming the line number'
else
  not_ok "rejects a line without a tab, naming the line number (status=$STATUS): $OUT"
fi

make_links "$H20" "rules/work-rules.md${TAB}~/work/CLAUDE.md"
run_link_home "$H20" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 1: source is not an absolute path'; then
  ok 'rejects a relative path'
else
  not_ok "rejects a relative path (status=$STATUS): $OUT"
fi

make_links "$H20" \
  "~/.ai-private/work-rules.md${TAB}~/work/CLAUDE.md" \
  "~/.ai-private/work-rules.md${TAB}~/work/CLAUDE.md"
run_link_home "$H20" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 2: target is already planned'; then
  ok 'rejects a duplicate target within links.txt'
else
  not_ok "rejects a duplicate target within links.txt (status=$STATUS): $OUT"
fi

# GUARD (mutation-tested): a links.txt line may not silently repoint a target
# the repo already claims. Remove the is_planned_target check and this goes red.
make_links "$H20" "~/.ai-private/work-rules.md${TAB}~/.claude/CLAUDE.md"
run_link_home "$H20" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 1: target is already planned' && [ ! -e "$H20/.claude" ]; then
  ok 'rejects a links.txt target that a repo-derived link already claims'
else
  not_ok "rejects a links.txt target that a repo-derived link already claims (status=$STATUS): $OUT"
fi

make_links "$H20" "~/.ai-private/nope.md${TAB}~/work/CLAUDE.md"
run_link_home "$H20" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 1: source does not exist'; then
  ok 'rejects a missing source'
else
  not_ok "rejects a missing source (status=$STATUS): $OUT"
fi

# Every bad line is reported, not just the first.
make_links "$H20" "no tab here" "~/.ai-private/nope.md${TAB}~/work/CLAUDE.md"
run_link_home "$H20" "$FIX"
if [ "$STATUS" = 2 ] && printf '%s' "$OUT" | grep -q 'line 1:' && printf '%s' "$OUT" | grep -q 'line 2:'; then
  ok 'reports every invalid line'
else
  not_ok "reports every invalid line (status=$STATUS): $OUT"
fi

# H6 has a private dir and no links.txt.
run_link_home "$H6" "$FIX"
if [ "$STATUS" = 0 ] && ! printf '%s' "$OUT" | grep -q 'links.txt'; then
  ok 'silently skips when links.txt is absent'
else
  not_ok "silently skips when links.txt is absent (status=$STATUS): $OUT"
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
