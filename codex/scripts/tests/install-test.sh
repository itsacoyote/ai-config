#!/usr/bin/env bash
# Self-contained safety suite for codex/install.sh.
set -u
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok() { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }
REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/../../.." && pwd -P)"
INSTALL_SRC="${INSTALL_UNDER_TEST:-$REPO_ROOT/codex/install.sh}"
[ -f "$INSTALL_SRC" ] || { printf 'installer not found: %s\n' "$INSTALL_SRC" >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-install-test.XXXXXX")" || exit 1
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FIX="$TMP/fixture"
mkdir -p "$FIX/rules"
cp "$INSTALL_SRC" "$FIX/install.sh"
cp "$REPO_ROOT/codex/rules/ai-config.rules" "$FIX/rules/ai-config.rules"
chmod +x "$FIX/install.sh"
section 'fresh install and dry run'
HOME1="$TMP/home1"
mkdir -p "$HOME1"
BEFORE="$(find "$HOME1" -print | sort)"
OUT="$(HOME="$HOME1" bash "$FIX/install.sh" --dry-run 2>&1)"; STATUS=$?
AFTER="$(find "$HOME1" -print | sort)"
if [ "$STATUS" -eq 0 ] && [ "$BEFORE" = "$AFTER" ] && printf '%s' "$OUT" | grep -q 'would create'; then ok 'dry-run writes nothing'; else not_ok 'dry-run writes nothing'; fi
OUT="$(HOME="$HOME1" bash "$FIX/install.sh" 2>&1)"; STATUS=$?
if [ "$STATUS" -eq 0 ] && [ -f "$HOME1/.codex/rules/ai-config.rules" ]; then ok 'fresh install creates the rules file'; else not_ok 'fresh install creates the rules file'; fi
if [ ! -e "$HOME1/.codex/AGENTS.md" ] && [ ! -e "$HOME1/.codex/config.toml" ]; then ok 'fresh install leaves unrelated Codex files absent'; else not_ok 'fresh install leaves unrelated Codex files absent'; fi
if cmp -s "$FIX/rules/ai-config.rules" "$HOME1/.codex/rules/ai-config.rules"; then ok 'installed rules match source'; else not_ok 'installed rules match source'; fi
section 'existing user state and guards'
printf '%s\n' personal >"$HOME1/.codex/config.toml"
printf '%s\n' instructions >"$HOME1/.codex/AGENTS.md"
printf '%s\n' personal >"$HOME1/.codex/rules/default.rules"
cp "$HOME1/.codex/config.toml" "$TMP/config-before"
cp "$HOME1/.codex/AGENTS.md" "$TMP/agents-before"
HOME="$HOME1" bash "$FIX/install.sh" >/dev/null 2>&1
if cmp -s "$HOME1/.codex/config.toml" "$TMP/config-before" && cmp -s "$HOME1/.codex/AGENTS.md" "$TMP/agents-before" && [ -f "$HOME1/.codex/rules/default.rules" ]; then ok 'existing personal files survive'; else not_ok 'existing personal files survive'; fi
HOME2="$TMP/home2"
mkdir -p "$HOME2/.codex/rules"
ln -s "$TMP/outside" "$HOME2/.codex/rules/ai-config.rules"
OUT="$(HOME="$HOME2" bash "$FIX/install.sh" 2>&1)"; STATUS=$?
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi symlink; then ok 'destination symlink is rejected'; else not_ok 'destination symlink is rejected'; fi
section 'syntax and source contract'
if bash -n "$FIX/install.sh" && bash -n "$REPO_ROOT/codex/scripts/tests/install-test.sh"; then ok 'installer and test parse as Bash'; else not_ok 'installer and test parse as Bash'; fi
if grep -q 'prefix_rule' "$FIX/rules/ai-config.rules" && ! grep -qiE 'claude|anthropic' "$FIX/rules/ai-config.rules"; then ok 'rules use Codex syntax without Claude references'; else not_ok 'rules use Codex syntax without Claude references'; fi
printf '\nresults: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
