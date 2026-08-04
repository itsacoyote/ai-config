#!/bin/sh
# setup-beads.sh — deterministic local/isolated beads setup.
#
# Performs the mechanical, repeatable part of the `setup-beads` skill: it
# initializes beads in *stealth* (personal/local/isolated) mode and wires the
# project so the workflow skills can drive `bd`. It does NOT make judgment
# calls — installing software, choosing tracked vs. local mode, or setting up a
# remote stay in the skill (see SKILL.md).
#
# What it does (idempotent, safe to re-run):
#   1. Refuses to run in a git worktree (worktrees share the main repo's .beads/).
#   2. No-ops if beads is already initialized here (.beads/ exists).
#   3. Stops with install instructions if `bd` is not on PATH (never auto-installs).
#   4. Runs `bd init --stealth --non-interactive [-p <prefix>]`.
#   5. Reverts bd's edit to the tracked root .gitignore (stealth makes it redundant).
#   6. Ensures .beads/ and .claude/settings.local.json are in .git/info/exclude.
#   7. Adds `Bash(bd *)` to .claude/settings.local.json permissions (needs jq).
#   8. Verifies `bd version` / `bd ready` and prints a recap.
#
# Usage:  setup-beads.sh [-p <prefix>] [--prefix <prefix>]
# Exit:   0 success (incl. "already set up"); non-zero on a refusal or failure.

set -eu

PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--prefix)
      [ $# -ge 2 ] || { echo "error: $1 requires a value" >&2; exit 2; }
      PREFIX="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }
note() { echo "→ $*"; }
ok()   { echo "✓ $*"; }

# --- 1. Must be inside a git repo (stealth mode relies on .git/info/exclude) ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "not a git repository. Stealth/isolated mode needs .git/info/exclude.
   Initialize git first, or follow the non-git path in the setup-beads skill."
fi

# --- 2. Refuse worktrees: they share the main repo's single .beads/ ---
git_dir="$(git rev-parse --git-dir)"
common_dir="$(git rev-parse --git-common-dir)"
if [ "$git_dir" != "$common_dir" ]; then
  fail "this is a git worktree. Worktrees share the main repo's .beads/ via the
   git common dir — \`bd ready\` already works here. Never \`bd init\` in a worktree;
   it forks the database. Run setup from the main working tree only."
fi

# Operate from the repo root so all relative paths resolve correctly.
cd "$(git rev-parse --show-toplevel)"

# --- 3. Already initialized? Nothing to do. ---
if [ -d .beads ]; then
  ok "beads already initialized here (.beads/ exists) — nothing to set up."
  echo "  Re-run setup only to change git mode or the session hook (see SKILL.md)."
  exit 0
fi

# --- 4. bd must be installed. We never auto-install software. ---
if ! command -v bd >/dev/null 2>&1; then
  cat >&2 <<'EOF'
✗ `bd` is not installed. setup-beads.sh does not install software for you.
  Install beads (confirm with the user first), then re-run:

    Homebrew (macOS/Linux) : brew install beads
    npm                    : npm install -g @beads/bd
    curl (Linux/macOS/BSD) : curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash

  Verify with `bd version`, then run this script again.
EOF
  exit 1
fi

# --- Snapshot .gitignore so we can revert bd's appended block deterministically ---
GITIGNORE_BACKUP=""
HAD_GITIGNORE=0
if [ -f .gitignore ]; then
  HAD_GITIGNORE=1
  GITIGNORE_BACKUP="$(mktemp)"
  cat .gitignore > "$GITIGNORE_BACKUP"
fi

# --- 5. Initialize in stealth + non-interactive mode ---
set -- init --stealth --non-interactive
[ -n "$PREFIX" ] && set -- "$@" -p "$PREFIX"
note "running: bd $*"
bd "$@" || fail "bd init failed — see the error above; not proceeding."
ok "bd init --stealth --non-interactive complete"

# --- 6. Revert bd's edit to the tracked root .gitignore ---
# Stealth already excludes all of .beads/ via .git/info/exclude, so bd's
# appended "# Beads / Dolt files" block is redundant and would commit
# beads-related lines. Restoring the snapshot drops exactly that block.
if [ "$HAD_GITIGNORE" = 1 ]; then
  if ! cmp -s "$GITIGNORE_BACKUP" .gitignore; then
    cp "$GITIGNORE_BACKUP" .gitignore
    ok "reverted bd's .gitignore edit (restored pre-init content)"
  else
    ok ".gitignore unchanged by bd"
  fi
  rm -f "$GITIGNORE_BACKUP"
elif [ -f .gitignore ]; then
  # bd created .gitignore solely for its block; remove it.
  rm -f .gitignore
  ok "removed bd-created .gitignore (stealth makes it redundant)"
fi

# --- 7. Ensure the stealth excludes are present in .git/info/exclude ---
EXCLUDE_FILE="$common_dir/info/exclude"
mkdir -p "$(dirname "$EXCLUDE_FILE")"
[ -f "$EXCLUDE_FILE" ] || : > "$EXCLUDE_FILE"
ensure_exclude() {
  if ! grep -qxF "$1" "$EXCLUDE_FILE" 2>/dev/null; then
    printf '%s\n' "$1" >> "$EXCLUDE_FILE"
    note "added '$1' to .git/info/exclude"
  fi
}
ensure_exclude '.beads/'
ensure_exclude '.claude/settings.local.json'
ok ".beads/ and .claude/settings.local.json excluded locally (.git/info/exclude)"

# --- 8. Add Bash(bd *) permission to .claude/settings.local.json ---
SETTINGS=".claude/settings.local.json"
if command -v jq >/dev/null 2>&1; then
  mkdir -p .claude
  existing='{}'
  [ -f "$SETTINGS" ] && existing="$(cat "$SETTINGS")"
  updated="$(printf '%s' "$existing" | jq '
    .permissions = (.permissions // {})
    | .permissions.allow = (.permissions.allow // [])
    | if (.permissions.allow | index("Bash(bd *)"))
      then . else .permissions.allow += ["Bash(bd *)"] end
  ')" || fail "failed to update $SETTINGS — is it valid JSON?"
  printf '%s\n' "$updated" > "$SETTINGS"
  ok "Bash(bd *) present in $SETTINGS"
else
  note "jq not found — add \"Bash(bd *)\" to $SETTINGS by hand"
  note "  (use the update-config skill), then the workflow skills can run bd unprompted."
fi

# --- 9. Verify and recap ---
echo
echo "── Verify ──────────────────────────────────────────"
bd version || fail "bd version failed after init"
echo
echo "bd ready (empty list = success: initialized, no ready issues yet):"
bd ready || true

echo
echo "── Recap ───────────────────────────────────────────"
echo "  • mode        : local / isolated (stealth)"
echo "  • bd init     : --stealth --non-interactive${PREFIX:+ -p $PREFIX}"
echo "  • .gitignore  : bd's edit reverted; nothing beads-related tracked"
echo "  • exclude     : .beads/ + .claude/settings.local.json in .git/info/exclude"
echo "  • permission  : Bash(bd *) in $SETTINGS"
echo "  • hook        : .claude/hooks/beads-gate.sh ships committed & wired — no action"
echo
echo "git status should show nothing beads-related:"
git status --porcelain | grep -iE 'beads|\.gitignore' || echo "  (clean — no beads/gitignore changes)"
echo
ok "beads is set up. Next: run \`define\` to start a feature, or \`standup\` to read state."
