#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
PWT="$ROOT/.agents/scripts/pwt"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME/remotes/owner" "$HOME/github/owner" "$HOME/fake-bin"
REMOTE="$HOME/remotes/owner/project.git"
PRIMARY="$HOME/github/owner/project"
MANAGED="$HOME/github/.worktrees/owner/project"
mkdir -p "$MANAGED"
MANAGED=$(cd "$MANAGED" && pwd -P)
LOG="$TMP/pi.log"
export PWT_TEST_LOG="$LOG"

pass=0
fail=0
ok() { printf 'ok - %s\n' "$1"; pass=$((pass + 1)); }
not_ok() { printf 'not ok - %s\n' "$1"; fail=$((fail + 1)); }
check() {
  local label=$1
  shift
  if "$@"; then ok "$label"; else not_ok "$label"; fi
}

cat >"$HOME/fake-bin/pi" <<'EOF'
#!/usr/bin/env bash
printf '%s|' "$PWD" >>"$PWT_TEST_LOG"
printf '%q ' "$@" >>"$PWT_TEST_LOG"
printf '\n' >>"$PWT_TEST_LOG"
EOF
chmod 700 "$HOME/fake-bin" "$HOME/fake-bin/pi"
ln -s "$PWT" "$HOME/fake-bin/pwt"
export PATH="$HOME/fake-bin:$PATH"

if pwt --help | grep -q 'pwt new <branch>'; then
  ok 'global help works outside a repository'
else
  not_ok 'global help works outside a repository'
fi
if env -C "$TMP" "$PWT" branch --help | grep -q 'existing local or origin branch'; then
  ok 'command help is available'
else
  not_ok 'command help is available'
fi

git init --bare --quiet "$REMOTE"
git init --quiet -b main "$TMP/seed"
git -C "$TMP/seed" config user.name Test
git -C "$TMP/seed" config user.email test@example.com
printf 'base\n' >"$TMP/seed/README.md"
git -C "$TMP/seed" add README.md
git -C "$TMP/seed" commit --quiet -m base
git -C "$TMP/seed" remote add origin "$REMOTE"
git -C "$TMP/seed" push --quiet -u origin main
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main
git clone --quiet "$REMOTE" "$PRIMARY"
git -C "$PRIMARY" config user.name Test
git -C "$PRIMARY" config user.email test@example.com

# Change the remote default after clone so origin/HEAD in the clone is stale.
git -C "$TMP/seed" switch --quiet -c stable
printf 'stable\n' >"$TMP/seed/stable.txt"
git -C "$TMP/seed" add stable.txt
git -C "$TMP/seed" commit --quiet -m stable
git -C "$TMP/seed" push --quiet -u origin stable
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/stable

if env -C "$PRIMARY" "$PWT" branch main >/dev/null 2>&1; then
  not_ok 'branch refuses a checkout outside the managed root'
else
  ok 'branch refuses a checkout outside the managed root'
fi

if env -C "$PRIMARY" "$PWT" new alpha >/dev/null 2>&1; then
  not_ok 'new requires an explicit typed branch name'
else
  ok 'new requires an explicit typed branch name'
fi

if env -C "$PRIMARY" "$PWT" new fix/alpha -- --name 'alpha session'; then
  check 'new preserves the explicit branch type' git -C "$PRIMARY" show-ref --verify --quiet refs/heads/fix/alpha
  check 'new creates central worktree' test -d "$MANAGED/fix-alpha"
  check 'new resolves the current remote default branch' test -f "$MANAGED/fix-alpha/stable.txt"
  if grep -Fq "$MANAGED/fix-alpha|--name alpha\\ session " "$LOG"; then
    ok 'new launches Pi inside worktree and preserves arguments'
  else
    not_ok 'new launches Pi inside worktree and preserves arguments'
  fi
else
  not_ok 'new command completes'
fi

if env -C "$PRIMARY" "$PWT" list | grep -q 'fix/alpha'; then
  ok 'list shows managed worktrees'
else
  not_ok 'list shows managed worktrees'
fi

: >"$LOG"
if env -C "$PRIMARY" "$PWT" open fix/alpha -- --thinking high && grep -Fq "$MANAGED/fix-alpha|--thinking high " "$LOG"; then
  ok 'open reuses managed worktree and launches Pi there'
else
  not_ok 'open reuses managed worktree and launches Pi there'
fi

mv "$MANAGED/fix-alpha" "$TMP/moved-alpha"
ln -s "$TMP/moved-alpha" "$MANAGED/fix-alpha"
if env -C "$PRIMARY" "$PWT" open fix/alpha >/dev/null 2>&1; then
  not_ok 'open rejects a replaced worktree symlink'
else
  ok 'open rejects a replaced worktree symlink'
fi
rm "$MANAGED/fix-alpha"
mv "$TMP/moved-alpha" "$MANAGED/fix-alpha"

mkdir -p "$PRIMARY/tools"
cat >"$PRIMARY/re.py" <<'EOF'
from pathlib import Path
import os
Path(os.environ["PWT_TEST_LOG"]).write_text("UNTRUSTED MODULE\n")
raise RuntimeError("repository module executed")
EOF
for command in pi git python3 bash; do
  cat >"$PRIMARY/tools/$command" <<'EOF'
#!/bin/bash
printf 'UNTRUSTED\n' >>"$PWT_TEST_LOG"
exit 99
EOF
  chmod 700 "$PRIMARY/tools/$command"
done
: >"$LOG"
if env -C "$PRIMARY" PATH="$PRIMARY/tools:$PATH" "$PWT" open fix/alpha && ! grep -q UNTRUSTED "$LOG"; then
  ok 'launcher rejects repository-provided bootstrap and Pi executables'
else
  not_ok 'launcher rejects repository-provided bootstrap and Pi executables'
fi
rm -rf "$PRIMARY/tools" "$PRIMARY/re.py"

# Create a remote-only branch.
git -C "$PRIMARY" switch --quiet -c fix/existing
printf 'fix\n' >"$PRIMARY/fix.txt"
git -C "$PRIMARY" add fix.txt
git -C "$PRIMARY" commit --quiet -m fix
git -C "$PRIMARY" push --quiet -u origin fix/existing
git -C "$PRIMARY" switch --quiet main
git -C "$PRIMARY" branch -D fix/existing >/dev/null

: >"$LOG"
if env -C "$PRIMARY" "$PWT" branch fix/existing && grep -Fq "$MANAGED/fix-existing|" "$LOG"; then
  check 'branch creates tracking branch' git -C "$PRIMARY" show-ref --verify --quiet refs/heads/fix/existing
  ok 'branch launches Pi in central worktree'
else
  not_ok 'branch launches Pi in central worktree'
fi

: >"$LOG"
if env -C "$PRIMARY" "$PWT" branch fix/existing && grep -Fq "$MANAGED/fix-existing|" "$LOG"; then
  ok 'branch reuses an existing checkout'
else
  not_ok 'branch reuses an existing checkout'
fi

printf 'dirty\n' >"$MANAGED/fix-alpha/dirty.txt"
if env -C "$PRIMARY" "$PWT" remove fix/alpha >/dev/null 2>&1; then
  not_ok 'remove refuses dirty worktree'
else
  ok 'remove refuses dirty worktree'
fi
rm "$MANAGED/fix-alpha/dirty.txt"
printf 'ignored.txt\n' >"$TMP/global-ignore"
git -C "$MANAGED/fix-alpha" config core.excludesFile "$TMP/global-ignore"
printf 'local data\n' >"$MANAGED/fix-alpha/ignored.txt"
if env -C "$PRIMARY" "$PWT" remove fix/alpha >/dev/null 2>&1; then
  not_ok 'remove refuses ignored local data'
else
  ok 'remove refuses ignored local data'
fi
rm "$MANAGED/fix-alpha/ignored.txt"
if env -C "$PRIMARY" "$PWT" remove fix/alpha --delete-branch >/dev/null; then
  check 'remove deletes clean worktree' test ! -e "$MANAGED/fix-alpha"
  if git -C "$PRIMARY" show-ref --verify --quiet refs/heads/fix/alpha; then
    not_ok 'remove safely deletes requested merged branch'
  else
    ok 'remove safely deletes requested merged branch'
  fi
else
  not_ok 'remove deletes clean worktree and branch'
fi

if env -C "$PRIMARY" "$PWT" remove fix/existing >/dev/null; then
  check 'remove keeps branch by default' git -C "$PRIMARY" show-ref --verify --quiet refs/heads/fix/existing
else
  not_ok 'remove keeps branch by default'
fi

if env -C "$PRIMARY" "$PWT" open fix/missing >/dev/null 2>&1; then
  not_ok 'open rejects unknown worktree'
else
  ok 'open rejects unknown worktree'
fi
if env -C "$PRIMARY" "$PWT" pr 123 >/dev/null 2>&1; then
  not_ok 'PR mode remains blocked pending sandboxing'
else
  ok 'PR mode remains blocked pending sandboxing'
fi

printf '%s passed; %s failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
