#!/usr/bin/env bash
# install-test.sh — self-contained safety suite for agents/install.sh
#
# Every case uses a fake HOME. The installer must manage only regular files below
# agents/skills and must validate the complete destination set before its first write.

set -u

pass=0
fail=0

ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REPO_ROOT="$(CDPATH= cd "$(dirname "$0")/../../.." && pwd -P)"
INSTALL_SRC="${INSTALL_UNDER_TEST:-$REPO_ROOT/agents/install.sh}"

if [ ! -f "$INSTALL_SRC" ]; then
  printf 'install-test.sh: installer not found: %s\n' "$INSTALL_SRC" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agents-install-test.XXXXXX")" || exit 1
[ -n "$TMP" ] && [ -d "$TMP" ] || exit 1
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false

make_fixture() {
  fix="$1"
  mkdir -p "$fix/skills/alpha/references" "$fix/skills/zulu/scripts"
  printf '%s\n' 'alpha-skill' >"$fix/skills/alpha/SKILL.md"
  printf '%s\n' 'alpha-reference' >"$fix/skills/alpha/references/guide.md"
  printf '%s\n' 'zulu-skill' >"$fix/skills/zulu/SKILL.md"
  printf '%s\n' '#!/bin/sh' 'echo zulu' >"$fix/skills/zulu/scripts/run.sh"
  chmod +x "$fix/skills/zulu/scripts/run.sh"

  # These files prove the install inventory does not expand beyond skills/.
  printf '%s\n' 'project instructions' >"$fix/AGENTS.md"
  mkdir -p "$fix/.codex" "$fix/pi"
  printf '%s\n' 'codex fixture' >"$fix/.codex/config.toml"
  printf '%s\n' 'pi fixture' >"$fix/pi/AGENTS.md"

  cp "$INSTALL_SRC" "$fix/install.sh"
  chmod +x "$fix/install.sh"
}

FIX="$TMP/fixture"
make_fixture "$FIX"

run_install() {
  home="$1"
  shift
  OUT="$(CDPATH= cd "$TMP" && HOME="$home" bash "$FIX/install.sh" "$@" 2>&1)"
  STATUS=$?
}

section 'arguments and fresh install'

H1="$TMP/h1"
mkdir -p "$H1"
OUT="$(HOME="$H1" bash "$FIX/install.sh" --help 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 0 ] && printf '%s' "$OUT" | grep -qi 'usage'; then
  ok 'help exits zero and prints usage'
else
  not_ok "help exits zero and prints usage (status=$STATUS)"
fi

OUT="$(HOME="$H1" bash "$FIX/install.sh" --unknown 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'unknown argument.*--help'; then
  ok 'unknown argument exits two with an actionable error'
else
  not_ok "unknown argument exits two with an actionable error (status=$STATUS out='$OUT')"
fi

run_install "$H1"
all_there=1
for rel in alpha/SKILL.md alpha/references/guide.md zulu/SKILL.md zulu/scripts/run.sh; do
  [ -f "$H1/.agents/skills/$rel" ] || all_there=0
done
if [ "$STATUS" -eq 0 ] && [ "$all_there" -eq 1 ]; then
  ok 'fresh home installs every regular file under skills'
else
  not_ok "fresh home installs every regular file under skills (status=$STATUS)"
fi

if [ ! -e "$H1/.agents/AGENTS.md" ] && [ ! -e "$H1/.codex" ] && [ ! -e "$H1/.pi" ]; then
  ok 'fresh home does not create AGENTS.md, .codex, or Pi content'
else
  not_ok 'fresh home does not create AGENTS.md, .codex, or Pi content'
fi

find "$FIX/skills" -type f -print | sed "s|^$FIX/skills/||" | sort >"$TMP/source-inventory"
find "$H1/.agents/skills" -type f -print | sed "s|^$H1/.agents/skills/||" | sort >"$TMP/installed-inventory"
if cmp -s "$TMP/source-inventory" "$TMP/installed-inventory"; then
  ok 'installed inventory contains only regular source skill files'
else
  not_ok 'installed inventory contains only regular source skill files'
fi

H1_DRY="$TMP/h1-dry"
mkdir -p "$H1_DRY"
find "$H1_DRY" -print | sort >"$TMP/dry-before"
run_install "$H1_DRY" --dry-run
find "$H1_DRY" -print | sort >"$TMP/dry-after"
if [ "$STATUS" -eq 0 ] && cmp -s "$TMP/dry-before" "$TMP/dry-after"; then
  ok 'fresh-home dry-run creates no files or directories'
else
  not_ok 'fresh-home dry-run creates no files or directories'
fi

section 'existing global state is preserved'

H2="$TMP/h2"
mkdir -p "$H2/.agents/skills/local-only" "$H2/.agents/skills/alpha" \
  "$H2/.codex/private" "$H2/.pi/agent"
printf '%s\n' 'personal instructions' >"$H2/.agents/AGENTS.md"
printf '%s\n' 'local-only skill' >"$H2/.agents/skills/local-only/SKILL.md"
printf '%s\n' 'local loose file' >"$H2/.agents/skills/local-note.md"
printf '%s\n' 'personal codex config' >"$H2/.codex/config.toml"
printf '%s\n' 'unreadable secret' >"$H2/.codex/private/secret"
printf '%s\n' 'personal pi config' >"$H2/.pi/agent/AGENTS.md"
cp "$H2/.agents/AGENTS.md" "$TMP/agents-before"
cp "$H2/.codex/config.toml" "$TMP/codex-before"
cp "$H2/.pi/agent/AGENTS.md" "$TMP/pi-before"
chmod 000 "$H2/.agents/AGENTS.md" "$H2/.codex/config.toml" \
  "$H2/.codex/private" "$H2/.pi/agent/AGENTS.md"

run_install "$H2"
chmod 600 "$H2/.agents/AGENTS.md" "$H2/.codex/config.toml" "$H2/.pi/agent/AGENTS.md"
chmod 700 "$H2/.codex/private"
if [ "$STATUS" -eq 0 ] && cmp -s "$H2/.agents/AGENTS.md" "$TMP/agents-before" && \
  cmp -s "$H2/.codex/config.toml" "$TMP/codex-before" && \
  cmp -s "$H2/.pi/agent/AGENTS.md" "$TMP/pi-before"; then
  ok 'existing agents, codex, and Pi sentinels remain byte-identical'
else
  not_ok "existing agents, codex, and Pi sentinels remain byte-identical (status=$STATUS)"
fi

if [ "$STATUS" -eq 0 ]; then
  ok 'unreadable unrelated configuration does not affect installation'
else
  not_ok 'unreadable unrelated configuration does not affect installation'
fi

if [ -f "$H2/.agents/skills/local-only/SKILL.md" ] && \
  [ "$(cat "$H2/.agents/skills/local-note.md")" = 'local loose file' ]; then
  ok 'global-only skill and loose file survive a rerun'
else
  not_ok 'global-only skill and loose file survive a rerun'
fi

if printf '%s' "$OUT" | grep -q 'local-only/SKILL.md' && \
  printf '%s' "$OUT" | grep -q 'local-note.md'; then
  ok 'global-only paths are reported'
else
  not_ok "global-only paths are reported (out='$OUT')"
fi

section 'updates and dry run'

printf '%s\n' 'alpha-skill-v2' >"$FIX/skills/alpha/SKILL.md"
run_install "$H1"
if [ "$STATUS" -eq 0 ] && [ "$(cat "$H1/.agents/skills/alpha/SKILL.md")" = 'alpha-skill-v2' ]; then
  ok 'changed source file is updated'
else
  not_ok 'changed source file is updated'
fi

run_install "$H1"
if [ "$STATUS" -eq 0 ] && printf '%s' "$OUT" | grep -qi 'no changes'; then
  ok 'unchanged rerun is idempotent'
else
  not_ok "unchanged rerun is idempotent (out='$OUT')"
fi

printf '%s\n' 'alpha-skill-v3' >"$FIX/skills/alpha/SKILL.md"
run_install "$H1" --dry-run
if [ "$STATUS" -eq 0 ] && printf '%s' "$OUT" | grep -q 'would overwrite: alpha/SKILL.md' && \
  [ "$(cat "$H1/.agents/skills/alpha/SKILL.md")" = 'alpha-skill-v2' ]; then
  ok 'dry-run reports changes and writes nothing'
else
  not_ok "dry-run reports changes and writes nothing (status=$STATUS out='$OUT')"
fi

section 'symlink and transaction guards'

ln -s "$FIX/skills/alpha/SKILL.md" "$FIX/skills/source-link.md"
H3="$TMP/h3"
mkdir -p "$H3/.agents/skills"
printf '%s\n' 'personal skipped-link path' >"$H3/.agents/skills/source-link.md"
run_install "$H3"
if [ "$STATUS" -eq 0 ] && \
  [ "$(cat "$H3/.agents/skills/source-link.md")" = 'personal skipped-link path' ] && \
  printf '%s' "$OUT" | grep -q 'source-link.md'; then
  ok 'source symlink is skipped and its matching target is reported global-only'
else
  not_ok 'source symlink is skipped and its matching target is reported global-only'
fi

H4="$TMP/h4"
mkdir -p "$H4/.agents/skills/alpha"
printf '%s\n' 'outside sentinel' >"$H4/outside"
ln -s "$H4/outside" "$H4/.agents/skills/alpha/SKILL.md"
run_install "$H4"
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'symlink' && \
  [ "$(cat "$H4/outside")" = 'outside sentinel' ]; then
  ok 'destination symlink cannot redirect a write outside the target'
else
  not_ok "destination symlink cannot redirect a write outside the target (status=$STATUS)"
fi

H5="$TMP/h5"
mkdir -p "$H5/.agents/skills" "$H5/outside-parent"
ln -s "$H5/outside-parent" "$H5/.agents/skills/alpha"
run_install "$H5"
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'symlink\|outside' && \
  [ ! -e "$H5/outside-parent/SKILL.md" ]; then
  ok 'symlinked parent cannot redirect a write outside the target'
else
  not_ok "symlinked parent cannot redirect a write outside the target (status=$STATUS)"
fi

# alpha sorts before zulu. The unsafe zulu destination must be detected before alpha is
# overwritten, proving validation covers the complete plan before the first write.
H6="$TMP/h6"
mkdir -p "$H6/.agents/skills/alpha" "$H6/.agents/skills/zulu"
printf '%s\n' 'old alpha' >"$H6/.agents/skills/alpha/SKILL.md"
printf '%s\n' 'outside zulu' >"$H6/outside-zulu"
ln -s "$H6/outside-zulu" "$H6/.agents/skills/zulu/SKILL.md"
run_install "$H6"
if [ "$STATUS" -ne 0 ] && [ "$(cat "$H6/.agents/skills/alpha/SKILL.md")" = 'old alpha' ] && \
  [ "$(cat "$H6/outside-zulu")" = 'outside zulu' ]; then
  ok 'late unsafe destination prevents every earlier planned overwrite'
else
  not_ok "late unsafe destination prevents every earlier planned overwrite (status=$STATUS)"
fi

H6B="$TMP/h6b"
mkdir -p "$H6B/.agents/skills/alpha" "$H6B/.agents/skills/zulu/SKILL.md"
printf '%s\n' 'old alpha' >"$H6B/.agents/skills/alpha/SKILL.md"
run_install "$H6B"
if [ "$STATUS" -ne 0 ] && [ "$(cat "$H6B/.agents/skills/alpha/SKILL.md")" = 'old alpha' ]; then
  ok 'late non-file destination prevents every earlier planned overwrite'
else
  not_ok "late non-file destination prevents every earlier planned overwrite (status=$STATUS)"
fi

H6C="$TMP/h6c"
mkdir -p "$H6C/.agents/skills/alpha"
printf '%s\n' 'outside hard-link sentinel' >"$H6C/outside-hard-link"
ln "$H6C/outside-hard-link" "$H6C/.agents/skills/alpha/SKILL.md"
run_install "$H6C"
if [ "$STATUS" -eq 0 ] && \
  [ "$(cat "$H6C/outside-hard-link")" = 'outside hard-link sentinel' ] && \
  [ "$(cat "$H6C/.agents/skills/alpha/SKILL.md")" = 'alpha-skill-v3' ]; then
  ok 'existing destination hard link cannot redirect an overwrite outside the target'
else
  not_ok "existing destination hard link cannot redirect an overwrite outside the target (status=$STATUS)"
fi

H6D="$TMP/h6d"
mkdir -p "$H6D/.agents/skills/alpha" "$H6D/.agents/skills/zulu/scripts"
printf '%s\n' 'old alpha' >"$H6D/.agents/skills/alpha/SKILL.md"
chmod 500 "$H6D/.agents/skills/zulu/scripts"
run_install "$H6D"
chmod 700 "$H6D/.agents/skills/zulu/scripts"
if [ "$STATUS" -ne 0 ] && [ "$(cat "$H6D/.agents/skills/alpha/SKILL.md")" = 'old alpha' ]; then
  ok 'late unwritable destination prevents every earlier planned overwrite'
else
  not_ok "late unwritable destination prevents every earlier planned overwrite (status=$STATUS)"
fi

section 'location guards'

H7="$TMP/h7"
mkdir -p "$H7/.agents"
OUT="$(CDPATH= cd "$H7/.agents" && HOME="$H7" bash "$FIX/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'refus'; then
  ok 'target cwd is refused'
else
  not_ok "target cwd is refused (status=$STATUS)"
fi

mkdir -p "$H7/.agents/library"
cp -R "$FIX/." "$H7/.agents/library/"
OUT="$(CDPATH= cd "$TMP" && HOME="$H7" bash "$H7/.agents/library/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'refus'; then
  ok 'installed copy is refused'
else
  not_ok "installed copy is refused (status=$STATUS)"
fi

BARE="$TMP/bare"
mkdir -p "$BARE"
cp "$INSTALL_SRC" "$BARE/install.sh"
H8="$TMP/h8"
mkdir -p "$H8"
OUT="$(HOME="$H8" bash "$BARE/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'no skills content'; then
  ok 'stray installer without agents/skills content fails loudly'
else
  not_ok "stray installer without agents/skills content fails loudly (status=$STATUS out='$OUT')"
fi

section 'source resolution and portability'

WTREPO="$TMP/wtrepo"
mkdir -p "$WTREPO/agents"
cp -R "$FIX/." "$WTREPO/agents/"
(
  CDPATH= cd "$WTREPO" || exit 1
  git init -q .
  git add -A
  git commit -qm init
  git worktree add -q "$TMP/wt" -b wt-branch
)
H9="$TMP/h9"
mkdir -p "$H9"
OUT="$(CDPATH= cd "$TMP" && HOME="$H9" bash "$TMP/wt/agents/install.sh" 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 0 ] && [ -f "$H9/.agents/skills/alpha/SKILL.md" ]; then
  ok 'installer resolves its source from a git worktree checkout'
else
  not_ok "installer resolves its source from a git worktree checkout (status=$STATUS out='$OUT')"
fi

if grep -qi 'python' "$INSTALL_SRC"; then
  not_ok 'installer has no Python dependency'
else
  ok 'installer has no Python dependency'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
