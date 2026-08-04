#!/usr/bin/env bash
# install-test.sh — self-contained test suite for claude/install.sh
#
# The installer writes into the user's global ~/.claude, where the two
# unrecoverable failures are: touching the settings files (personal config no
# script may rewrite — ADR 0007) and mirror-deleting global-only files (local
# customizations with no copy anywhere else). Both guards are mutation-tested
# below — the suite must go red if either is removed.
#
# Usage:  bash claude/scripts/tests/install-test.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

set -u

pass=0
fail=0

ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
INSTALL_SRC="$REPO_ROOT/claude/install.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Isolate git for the worktree fixture.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# Mini library fixture instead of the real claude/ tree: the suite tests the
# real install.sh (copied in), and a small tree keeps every case readable and
# fast. The template settings.json mirrors the real one's shape — hooks,
# statusLine, an allowlist, and the git -C deny the report must flag.
make_fixture() {
  local fix="$1"
  mkdir -p "$fix"/skills/foo "$fix"/agents "$fix"/rules "$fix"/references \
    "$fix"/scripts "$fix"/hooks
  echo "skill-body" > "$fix/skills/foo/SKILL.md"
  echo "agent-body" > "$fix/agents/a.md"
  echo "rule-body" > "$fix/rules/r.md"
  echo "ref-body" > "$fix/references/ref.md"
  printf '#!/bin/sh\necho s\n' > "$fix/scripts/s.sh" && chmod +x "$fix/scripts/s.sh"
  printf '#!/bin/sh\necho h\n' > "$fix/hooks/h.sh" && chmod +x "$fix/hooks/h.sh"
  echo "statusline-body" > "$fix/statusline-command.sh"
  cat > "$fix/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "command": "bash ~/.claude/hooks/h.sh", "type": "command" }
        ],
        "matcher": ""
      }
    ]
  },
  "permissions": {
    "allow": ["Bash(bd list *)", "Bash(bd show *)"],
    "deny": ["Bash(git -C *)"]
  },
  "statusLine": { "command": "bash ~/.claude/statusline-command.sh", "type": "command" }
}
EOF
  cp "$INSTALL_SRC" "$fix/install.sh"
  chmod +x "$fix/install.sh"
}

FIX="$TMP/fixture"
make_fixture "$FIX"

# Each case gets its own fake HOME; run_install captures output + status.
run_install() {
  # $1 = HOME to use; remaining args pass through to install.sh
  local home="$1"; shift
  OUT="$(cd "$TMP" && HOME="$home" bash "$FIX/install.sh" "$@" 2>&1)"
  STATUS=$?
}

section 'fresh install'

H1="$TMP/h1"; mkdir -p "$H1"
run_install "$H1"
all_there=1
for p in skills/foo/SKILL.md agents/a.md rules/r.md references/ref.md \
  scripts/s.sh hooks/h.sh statusline-command.sh; do
  [ -f "$H1/.claude/$p" ] || all_there=0
done
if [ "$STATUS" = 0 ] && [ "$all_there" = 1 ]; then
  ok 'fresh home: installs six content dirs + statusline-command.sh'
else
  not_ok "fresh home: installs six content dirs + statusline-command.sh (status=$STATUS)"
fi

# GUARD (mutation-tested): the copy set excludes the settings files. The
# plausible wrong fix is adding settings.json to the installer's file list
# ("why isn't it installed?") — do that and this goes red.
if [ ! -e "$H1/.claude/settings.json" ] && [ ! -e "$H1/.claude/settings.local.json" ]; then
  ok 'fresh home: does not create settings files'
else
  not_ok 'fresh home: does not create settings files'
fi

if printf '%s' "$OUT" | grep -q 'skills/foo/SKILL.md'; then
  ok 'fresh install reports what it created'
else
  not_ok 'fresh install reports what it created'
fi

section 'existing global state is preserved'

H2="$TMP/h2"; mkdir -p "$H2/.claude/skills/local-only" "$H2/.claude/scripts"
echo '{"my":"settings"}' > "$H2/.claude/settings.json"
echo '{"my":"local"}'    > "$H2/.claude/settings.local.json"
echo "precious-local-skill" > "$H2/.claude/skills/local-only/SKILL.md"
echo "precious-loose-script" > "$H2/.claude/scripts/wt-status.sh"
run_install "$H2"

# GUARD (mutation-tested): settings byte-identical after a run over an
# existing home. Red if the installer ever opens these for write.
if [ "$(cat "$H2/.claude/settings.json")" = '{"my":"settings"}' ] &&
  [ "$(cat "$H2/.claude/settings.local.json")" = '{"my":"local"}' ]; then
  ok 'existing settings files: byte-identical after run'
else
  not_ok 'existing settings files: byte-identical after run'
fi

# GUARD (mutation-tested): additive copy. Replace the per-file copy with any
# mirror semantics (rm -rf before copy, rsync --delete) and this goes red.
# These fixtures are real casualties: the maintainer's global has skills and
# loose scripts that exist nowhere in the repo.
if [ -f "$H2/.claude/skills/local-only/SKILL.md" ] &&
  [ "$(cat "$H2/.claude/scripts/wt-status.sh")" = "precious-loose-script" ]; then
  ok 'pre-existing global-only skill and loose script survive a run'
else
  not_ok 'pre-existing global-only skill and loose script survive a run'
fi

if printf '%s' "$OUT" | grep -q 'skills/local-only' &&
  printf '%s' "$OUT" | grep -q 'scripts/wt-status.sh'; then
  ok 'merge report lists global-only paths (files and dirs)'
else
  not_ok 'merge report lists global-only paths (files and dirs)'
fi

section 'update semantics'

echo "skill-body-v2" > "$FIX/skills/foo/SKILL.md"
run_install "$H1"
if [ "$(cat "$H1/.claude/skills/foo/SKILL.md")" = "skill-body-v2" ]; then
  ok 're-run after source edit updates the changed file'
else
  not_ok 're-run after source edit updates the changed file'
fi

run_install "$H1"
if printf '%s' "$OUT" | grep -qi 'no changes'; then
  ok 'idempotent re-run reports no changes'
else
  not_ok "idempotent re-run reports no changes (out='$OUT')"
fi

section 'merge report'

# H1 has no global settings at all — every template entry is missing.
run_install "$H1"
if printf '%s' "$OUT" | grep -q 'hooks/h.sh' && printf '%s' "$OUT" | grep -qi 'missing'; then
  ok 'merge report lists template-only hook entry when global lacks it'
else
  not_ok 'merge report lists template-only hook entry when global lacks it'
fi
if printf '%s' "$OUT" | grep -q 'Bash(bd list \*)'; then
  ok 'merge report lists missing permission entries verbatim'
else
  not_ok 'merge report lists missing permission entries verbatim'
fi

# Hook entry present only in settings.local.json, in ~ form → not reported.
H3="$TMP/h3"; mkdir -p "$H3/.claude"
cat > "$H3/.claude/settings.local.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "command": "bash ~/.claude/hooks/h.sh", "type": "command" } ], "matcher": "" }
    ]
  },
  "permissions": { "allow": ["Bash(bd list *)", "Bash(bd show *)"] }
}
EOF
run_install "$H3"
if printf '%s' "$OUT" | grep -qi 'missing hook'; then
  not_ok 'merge report checks settings.local.json too (entry there = not reported)'
else
  ok 'merge report checks settings.local.json too (entry there = not reported)'
fi

# Same hook registered with an ABSOLUTE path in the main global file → the
# ~/ template form must compare equal (path normalization), not re-report.
H4="$TMP/h4"; mkdir -p "$H4/.claude"
cat > "$H4/.claude/settings.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "command": "bash $H4/.claude/hooks/h.sh", "type": "command" } ], "matcher": "" }
    ]
  },
  "statusLine": { "command": "bash $H4/.claude/statusline-command.sh", "type": "command" }
}
EOF
run_install "$H4"
if printf '%s' "$OUT" | grep -qi 'missing hook'; then
  not_ok 'merge report treats ~ and absolute hook-command forms as equal'
else
  ok 'merge report treats ~ and absolute hook-command forms as equal'
fi
if printf '%s' "$OUT" | grep -qi 'missing statusline'; then
  not_ok 'merge report treats ~ and absolute statusline forms as equal'
else
  ok 'merge report treats ~ and absolute statusline forms as equal'
fi

# The git -C deny is never suggested for migration — global deny is absolute
# and the maintainer keeps a deliberate scoped git -C allow globally.
run_install "$H1"
if printf '%s' "$OUT" | grep -q 'git -C' && printf '%s' "$OUT" | grep -qi 'do not migrate'; then
  ok 'merge report flags the git -C deny as do-not-migrate'
else
  not_ok 'merge report flags the git -C deny as do-not-migrate'
fi

section 'dry run'

H5="$TMP/h5"; mkdir -p "$H5/.claude/skills/foo"
echo "old-divergent-content" > "$H5/.claude/skills/foo/SKILL.md"
run_install "$H5" --dry-run
if printf '%s' "$OUT" | grep -q 'would overwrite: skills/foo/SKILL.md'; then
  ok 'dry-run lists would-be-overwritten differing files'
else
  not_ok "dry-run lists would-be-overwritten differing files (out='$OUT')"
fi
if [ "$(cat "$H5/.claude/skills/foo/SKILL.md")" = "old-divergent-content" ] &&
  [ ! -e "$H5/.claude/rules/r.md" ]; then
  ok 'dry-run writes nothing'
else
  not_ok 'dry-run writes nothing'
fi

section 'degradation and guards'

# jq-less PATH still carrying every tool the installer legitimately needs —
# dropping the whole system PATH would break it for the wrong reason.
NOJQ_BIN="$TMP/nojq-bin"
mkdir -p "$NOJQ_BIN"
for tool in bash sh cp mkdir find cmp dirname sed grep sort cat uname; do
  src="$(command -v "$tool")" && ln -s "$src" "$NOJQ_BIN/$tool" 2>/dev/null
done
H6="$TMP/h6"; mkdir -p "$H6"
OUT="$(cd "$TMP" && HOME="$H6" PATH="$NOJQ_BIN" bash "$FIX/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" = 0 ] && [ -f "$H6/.claude/rules/r.md" ] &&
  printf '%s' "$OUT" | grep -qi 'requires jq'; then
  ok 'jq absent: copy succeeds, merge report skipped with notice'
else
  not_ok "jq absent: copy succeeds, merge report skipped with notice (status=$STATUS)"
fi

# Guard: refuses to run from inside the target. Recoverable (a no-op refusal),
# so asserted plainly rather than mutation-tested.
H7="$TMP/h7"; mkdir -p "$H7/.claude"
OUT="$(cd "$H7/.claude" && HOME="$H7" bash "$FIX/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" != 0 ] && printf '%s' "$OUT" | grep -qi 'refus'; then
  ok 'refuses to run from inside ~/.claude'
else
  not_ok "refuses to run from inside ~/.claude (status=$STATUS)"
fi

section 'source resolution'

# The installer resolves its source tree from its own script path, not cwd —
# the maintainer's default workflow runs it from a git worktree checkout.
WTREPO="$TMP/wtrepo"
mkdir -p "$WTREPO"
cp -R "$FIX/." "$WTREPO/"
( cd "$WTREPO" && git init -q . && git add -A && git commit -qm init &&
  git worktree add -q "$TMP/wt" -b wt-branch ) || true
H8="$TMP/h8"; mkdir -p "$H8"
OUT="$(cd "$TMP" && HOME="$H8" bash "$TMP/wt/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" = 0 ] && [ -f "$H8/.claude/skills/foo/SKILL.md" ]; then
  ok 'runs correctly from a git worktree checkout'
else
  not_ok "runs correctly from a git worktree checkout (status=$STATUS)"
fi

# Same rule as clwt: the tooling stays pure bash.
if grep -q 'python' "$INSTALL_SRC"; then
  not_ok 'no python dependency'
else
  ok 'no python dependency'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
