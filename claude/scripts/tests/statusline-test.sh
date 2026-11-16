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

# Primary checkout with a clean https origin.
PRIMARY="$TMP/primary-proj"; mkdir -p "$PRIMARY"
( cd "$PRIMARY" && git init -q . && echo a > a.txt && git add a.txt && git commit -qm init &&
  git remote add origin 'https://example.invalid/owner/project.git' ) || { echo "fixture setup failed" >&2; exit 1; }

# Linked worktrees: folder equals branch / branch with / -> - / differs.
( cd "$PRIMARY" &&
  git worktree add -q "$TMP/feature-a" -b feature-a &&
  git worktree add -q "$TMP/feat-login" -b feat/login &&
  git worktree add -q "$TMP/scratch" -b feat/other &&
  git worktree add -q "$TMP/login-wt" -b feat/login-page ) || { echo "worktree fixture setup failed" >&2; exit 1; }

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

check_line2 'worktree name is shown when it differs from a branch containing a slash' \
  "$TMP/login-wt" '📁 primary-proj | 🌿 feat/login-page | login-wt'

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

run_statusline "$(jq -n --arg d "$NONGIT" '{workspace:{current_dir:$d,repo:{host:"user:repotok@example.invalid",owner:"acme",name:"widgets"}}}')"
if printf '%s' "$OUT" | grep -qF 'https://example.invalid/acme/widgets/pulls' &&
   ! printf '%s' "$OUT" | grep -qF 'repotok'; then
  ok 'credentials in workspace.repo.host are not printed'
else
  not_ok "credentials in workspace.repo.host are not printed: $(printf '%s' "$OUT" | od -c | head -8)"
fi

QRY="$TMP/query-proj"; mkdir -p "$QRY"
( cd "$QRY" && git init -q . && git remote add origin 'https://example.invalid/owner/project.git?token=qtok123#frag456' ) ||
  { echo "query fixture setup failed" >&2; exit 1; }
run_statusline "$(json_dir "$QRY")"
if printf '%s' "$OUT" | grep -qF 'https://example.invalid/owner/project/pulls' &&
   ! printf '%s' "$OUT" | grep -qF 'qtok123' && ! printf '%s' "$OUT" | grep -qF 'frag456'; then
  ok 'a query-string token and fragment in the origin remote are not printed'
else
  not_ok "a query-string token and fragment in the origin remote are not printed: $(printf '%s' "$OUT" | od -c | head -8)"
fi

SLASH="$TMP/slash-proj"; mkdir -p "$SLASH"
( cd "$SLASH" && git init -q . && git remote add origin 'https://someuser:1/slashsecret@example.invalid/owner/project.git' ) ||
  { echo "slash fixture setup failed" >&2; exit 1; }
run_statusline "$(json_dir "$SLASH")"
if ! printf '%s' "$OUT" | grep -qF 'slashsecret'; then
  ok 'a password containing a slash in the origin remote is not printed'
else
  not_ok "a password containing a slash in the origin remote is not printed: $(printf '%s' "$OUT" | od -c | head -8)"
fi

NOLINK="$TMP/nolink-proj"; mkdir -p "$NOLINK"
( cd "$NOLINK" && git init -q . && git remote add origin 'https://bad_host.invalid:x/owner/project.git' ) ||
  { echo "nolink fixture setup failed" >&2; exit 1; }
run_statusline "$(json_dir "$NOLINK")"
if ! printf '%s' "$OUT" | grep -qF "${ESC}]8;;"; then
  ok 'no link is emitted when the remote authority is not a plain host'
else
  not_ok 'no link is emitted when the remote authority is not a plain host'
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

BADU="$TMP/c1-$(printf '\xc2\x9b')dir"; mkdir -p "$BADU"
run_statusline "$(json_dir "$BADU")"
if [ "$(line2)" = '📁 c1-dir' ]; then
  ok 'UTF-8 C1 controls in the folder name are stripped'
else
  not_ok "UTF-8 C1 controls in the folder name are stripped: $(line2 | od -c | head -3)"
fi

# U+202E and U+2067, plus U+00E9 and U+2014 to show ordinary non-ASCII survives.
BIDI="$TMP/bidi-$(printf '\xe2\x80\xae')x$(printf '\xe2\x81\xa7')-$(printf '\xc3\xa9\xe2\x80\x94')"; mkdir -p "$BIDI"
run_statusline "$(json_dir "$BIDI")"
if [ "$(line2)" = "📁 bidi-x-$(printf '\xc3\xa9\xe2\x80\x94')" ]; then
  ok 'bidi override characters in the folder name are stripped'
else
  not_ok "bidi override characters in the folder name are stripped: $(line2 | od -c | head -3)"
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

err=$(printf '%s' '{"context_window":{"used_percentage":"abc"},"rate_limits":{"five_hour":{"used_percentage":"1e"}}}' | bash "$SCRIPT" 2>&1 >/dev/null)
run_statusline '{"context_window":{"used_percentage":"abc"},"rate_limits":{"five_hour":{"used_percentage":"1e"}}}'
if [ -z "$err" ] && [ "$(printf '%s\n' "$OUT" | sed -n 1p | plain)" = 'Unknown Model | --% ctx' ]; then
  ok 'a non-numeric percentage renders --% ctx with empty stderr'
else
  not_ok "a non-numeric percentage renders --% ctx with empty stderr: [$err] $OUT"
fi

section 'git config hardening'

# Behavioral trap for a future git call that bypasses git_safe and refreshes
# the index. Today's calls never read fsmonitor, so this passes even with the
# flag removed; the source pin below is what guards the flags.
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

# Source-level pin: the flags are the guard; the marker test cannot detect their removal.
if grep -q 'GIT_CONFIG_NOSYSTEM=1' "$SCRIPT" &&
   grep -q 'core.fsmonitor=false' "$SCRIPT" &&
   grep -q 'core.hooksPath=/dev/null' "$SCRIPT" &&
   grep -q -- '--no-optional-locks' "$SCRIPT"; then
  ok 'git runs with system config, fsmonitor, hooks and optional locks disabled'
else
  not_ok 'git runs with system config, fsmonitor, hooks and optional locks disabled'
fi

section 'refresh: cache the branch pull request'

TAB=$'\t'
CACHE_DIR="$HOME/.cache/claude-statusline"
BIN="$TMP/bin"; mkdir -p "$BIN"
GHFIX="$TMP/gh-fixtures"; mkdir -p "$GHFIX"
export STATUSLINE_GH_FIXTURES="$GHFIX"
PR_FIELDS='number,url,state,author,reviewDecision,reviews'
export PR_FIELDS

# Hosts the refresher may send to gh. The nested attacker.invalid key must not
# count: only top-level keys are hosts.
export GH_CONFIG_DIR="$TMP/gh-config"; mkdir -p "$GH_CONFIG_DIR"
cat >"$GH_CONFIG_DIR/hosts.yml" <<'YML'
example.invalid:
    user: me
    nested:
    attacker.invalid:
YML

# Stub gh: canned answers from fixture files, one log line per call. A missing
# fixture file exits 1, the same signal real gh gives for "no such PR" and for
# "gh is broken", so the refresher cannot rely on telling them apart. Failures
# write to stderr, as real gh does, so a refresher that stops discarding it fails.
cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
dir="${STATUSLINE_GH_FIXTURES:?}"
printf '%s\tenv:%s,%s,%s,%s,%s=%s,%s=%s,GIT_CONFIG_COUNT=%s\tent:[%s%s]\tlc:%s\tpwd:%s\n' "$*" \
  "${GH_PROMPT_DISABLED-}" "${GH_NO_UPDATE_NOTIFIER-}" "${GH_PAGER-}" "${NO_COLOR-}" \
  "${GIT_CONFIG_KEY_0-}" "${GIT_CONFIG_VALUE_0-}" "${GIT_CONFIG_KEY_1-}" "${GIT_CONFIG_VALUE_1-}" \
  "${GIT_CONFIG_COUNT-}" "${GH_ENTERPRISE_TOKEN-}" "${GITHUB_ENTERPRISE_TOKEN-}" "${LC_ALL-}" "$PWD" >>"$dir/log"
fail() { echo "gh: simulated failure" >&2; exit 1; }
[ -e "$dir/fail" ] && fail
if [ "$1" = api ] && [ "$2" = --hostname ] && [ "$4" = user ] && [ "$5" = --jq ] && [ "$6" = .login ] && [ $# -eq 6 ]; then
  [ -e "$dir/viewer-fail" ] && fail
  cat "$dir/viewer" 2>/dev/null || fail
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = view ] && [ "$4" = --json ] && [ "$5" = "$PR_FIELDS" ] && [ $# -eq 5 ]; then
  cat "$dir/view.json" 2>/dev/null || fail
  exit 0
fi
if [ "$1" = pr ] && [ "$2" = list ] && [ "$3" = --head ] && [ "$5" = --state ] && [ "$6" = all ] &&
   [ "$7" = --json ] && [ "$8" = "$PR_FIELDS" ] && [ "$9" = --limit ] && [ "${10}" = 10 ] && [ $# -eq 10 ]; then
  cat "$dir/list.json" 2>/dev/null || fail
  exit 0
fi
printf 'gh stub: unhandled: %s\n' "$*" >&2
printf 'UNHANDLED %s\n' "$*" >>"$dir/unhandled"
exit 99
STUB
chmod +x "$BIN/gh"

# A PATH with the tools the refresher runs but no gh.
NOGH="$TMP/nogh-bin"; mkdir -p "$NOGH"
for tool in git jq date mktemp mv rm mkdir chmod; do
  tool_path=$(command -v "$tool") && ln -sf "$tool_path" "$NOGH/$tool"
done

RF="$TMP/refresh-repo"; mkdir -p "$RF"
( cd "$RF" && git init -q . && echo a > a.txt && git add a.txt && git commit -qm init &&
  git remote add origin 'https://example.invalid/owner/project.git' &&
  git update-ref refs/remotes/origin/main HEAD &&
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main ) || { echo "refresh fixture setup failed" >&2; exit 1; }

# No origin/HEAD: the default branch falls back to main/master.
RFNOHEAD="$TMP/refresh-nohead"; mkdir -p "$RFNOHEAD"
( cd "$RFNOHEAD" && git init -q . && echo a > a.txt && git add a.txt && git commit -qm init ) ||
  { echo "refresh nohead fixture setup failed" >&2; exit 1; }

PRBASE='https://example.invalid/owner/project'
PRURL="$PRBASE/pull"

reset_gh() {
  rm -rf "$GHFIX" "$CACHE_DIR"; mkdir -p "$GHFIX"
  printf 'me\n' >"$GHFIX/viewer"
}

# reviews <login> <STATE> [<login> <STATE>]... — a reviews array, oldest first.
reviews() {
  jq -n -c '[$ARGS.positional as $p | range(0; $p | length; 2) | {author: {login: $p[.]}, state: $p[. + 1]}]' --args "$@"
}

# pr_obj <number> <STATE> <author> <reviewDecision> <reviews-json> [<url base>]
pr_obj() {
  jq -n -c --arg n "$1" --arg s "$2" --arg a "$3" --arg d "$4" --argjson r "$5" --arg b "${6:-$PRBASE}" \
    '{number: ($n | tonumber), url: "\($b)/pull/\($n)", state: $s, author: {login: $a}, reviewDecision: $d, reviews: $r}'
}

set_list() { printf '%s\n' "$1" >"$GHFIX/list.json"; }
set_view() { printf '%s\n' "$1" >"$GHFIX/view.json"; }
gh_calls() { [ -f "$GHFIX/log" ] && grep -c . "$GHFIX/log" || printf '0'; }
api_calls() { [ -f "$GHFIX/log" ] || { printf '0'; return; }; grep -c '^api ' "$GHFIX/log" || true; }

CF="$CACHE_DIR/k-1234567"
GOOD="7${TAB}OPEN${TAB}approved${TAB}$PRURL/7"
seed_cache() { mkdir -p "$CACHE_DIR" && printf '%s\n' "$1" >"$CF"; }
seed_good() { seed_cache "1000${TAB}$GOOD"; }

RSTATUS=0
# The tokens are fake; they exist so a leak into gh's environment is visible.
refresh() { # <top> <branch> <cache file> [PATH]
  GH_ENTERPRISE_TOKEN=fake-enterprise GITHUB_ENTERPRISE_TOKEN=fake-github-enterprise LC_ALL=en_US.UTF-8 \
    PATH="${4:-$BIN:$PATH}" "$BASH" "$SCRIPT" --refresh "$1" "$2" "$3" >"$TMP/refresh.out" 2>&1
  RSTATUS=$?
}

# refresh_bounded — as refresh, but kills the run after about 5 seconds so a
# refresher that blocks on a FIFO fails the test instead of hanging the suite.
refresh_bounded() {
  local pid i=0
  PATH="$BIN:$PATH" "$BASH" "$SCRIPT" --refresh "$1" "$2" "$3" >"$TMP/refresh.out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RSTATUS=timeout
  else
    wait "$pid"; RSTATUS=$?
  fi
}

cache_tail() { cut -f2- "$CF" 2>/dev/null; }
cache_epoch() { cut -f1 "$CF" 2>/dev/null; }
epoch_is_current() {
  local e now; e=$(cache_epoch); now=$(date +%s)
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  [ "$e" -le "$now" ] && [ "$e" -ge $((now - 30)) ]
}

# expect_cache <name> <expected line without epoch> — also pins a clean exit,
# a current epoch, empty output (gh's stderr must not leak) and no gh call the
# stub did not understand.
expect_cache() {
  local name="$1" want="$2" got
  got=$(cache_tail)
  if [ "$RSTATUS" = 0 ] && [ "$got" = "$want" ] && epoch_is_current &&
     [ ! -s "$TMP/refresh.out" ] && [ ! -e "$GHFIX/unhandled" ]; then
    ok "$name"
  else
    not_ok "$name (status=$RSTATUS): expected [$want] got [$got] out=[$(cat "$TMP/refresh.out" 2>/dev/null)]"
  fi
}

reset_gh
refresh "$RF" feat/x "$CF"
if [ "$(ls -ld "$CACHE_DIR" | cut -c1-10)" = 'drwx------' ]; then
  ok 'the cache directory is created owner-only'
else
  not_ok "the cache directory is created owner-only: $(ls -ld "$CACHE_DIR")"
fi

reset_gh
seed_good
set_list '[]'
refresh "$RF" feat/x "$CF"
expect_cache 'refresh caches NONE when the branch has no pr' 'NONE'

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh caches an open pr with no reviews as none' "7${TAB}OPEN${TAB}none${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews me APPROVED me COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh caches approved when the viewer's last opinionated review is an approval followed by a comment" \
  "7${TAB}OPEN${TAB}approved${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews me APPROVED me CHANGES_REQUESTED me COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh caches changes when the viewer's last opinionated review requests changes" \
  "7${TAB}OPEN${TAB}changes${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews bob APPROVED me COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh caches commented when the viewer only left comment reviews" \
  "7${TAB}OPEN${TAB}commented${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews me APPROVED me DISMISSED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh caches none when the viewer's approval was dismissed and they left no comment" \
  "7${TAB}OPEN${TAB}none${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews me APPROVED me DISMISSED me COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh caches commented when the viewer's approval was dismissed and they also commented" \
  "7${TAB}OPEN${TAB}commented${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN me APPROVED "$(reviews bob COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh on the viewer's own pr uses reviewDecision" \
  "7${TAB}OPEN${TAB}approved${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN me CHANGES_REQUESTED "$(reviews bob APPROVED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh on the viewer's own pr uses reviewDecision for changes" \
  "7${TAB}OPEN${TAB}changes${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN me '' "$(reviews bob COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh on the viewer's own pr caches commented when only others commented" \
  "7${TAB}OPEN${TAB}commented${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 7 OPEN me '' "$(reviews me COMMENTED)")]"
refresh "$RF" feat/x "$CF"
expect_cache "refresh on the viewer's own pr ignores the viewer's own comment reviews" \
  "7${TAB}OPEN${TAB}none${TAB}$PRURL/7"

reset_gh
set_list "[$(pr_obj 4 MERGED alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh caches merged' "4${TAB}MERGED${TAB}merged${TAB}$PRURL/4"
if [ "$(gh_calls)" = 1 ]; then ok 'a merged pr needs no viewer lookup'; else not_ok "a merged pr needs no viewer lookup: $(cat "$GHFIX/log")"; fi

# The open PR is the lower number and listed first, so only an explicit
# OPEN preference, not "highest number" or "last listed", picks it.
reset_gh
set_list "[$(pr_obj 3 OPEN alice '' "$(reviews)"),$(pr_obj 9 MERGED alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh prefers an open pr over a merged one' "3${TAB}OPEN${TAB}none${TAB}$PRURL/3"

reset_gh
set_list "[$(pr_obj 3 MERGED alice '' "$(reviews)"),$(pr_obj 9 MERGED alice '' "$(reviews)"),$(pr_obj 5 MERGED alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh picks the highest-numbered merged pr' "9${TAB}MERGED${TAB}merged${TAB}$PRURL/9"

reset_gh
seed_good
set_list "[$(pr_obj 8 CLOSED alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh ignores a closed unmerged pr' 'NONE'

reset_gh
set_list "[$(pr_obj 8 CLOSED alice '' "$(reviews)"),$(pr_obj 2 MERGED alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
expect_cache 'a closed pr does not hide an older merged one' "2${TAB}MERGED${TAB}merged${TAB}$PRURL/2"

section 'refresh: lookup order'

reset_gh
git -C "$RF" config branch.feat/m.worktree-pr-url "$PRURL/21"
set_view "$(pr_obj 21 OPEN alice '' "$(reviews me APPROVED)")"
refresh "$RF" feat/m "$CF"
expect_cache 'refresh uses the clwt pr url marker before searching by branch' \
  "21${TAB}OPEN${TAB}approved${TAB}$PRURL/21"
if grep -q "^pr view $PRURL/21 --json" "$GHFIX/log" && ! grep -q '^pr list' "$GHFIX/log"; then
  ok 'the marker path calls gh pr view with the url and never pr list'
else
  not_ok "the marker path calls gh pr view with the url and never pr list: $(cat "$GHFIX/log")"
fi
git -C "$RF" config --unset branch.feat/m.worktree-pr-url

reset_gh
git -C "$RF" config branch.feat/n.merge refs/pull/33/head
set_view "$(pr_obj 33 OPEN alice '' "$(reviews me CHANGES_REQUESTED)")"
refresh "$RF" feat/n "$CF"
expect_cache 'refresh uses refs/pull/<n>/head from branch merge config' \
  "33${TAB}OPEN${TAB}changes${TAB}$PRURL/33"
if grep -q '^pr view 33 --json' "$GHFIX/log" && ! grep -q '^pr list' "$GHFIX/log"; then
  ok 'the merge-ref path calls gh pr view with the number and never pr list'
else
  not_ok "the merge-ref path calls gh pr view with the number and never pr list: $(cat "$GHFIX/log")"
fi
git -C "$RF" config --unset branch.feat/n.merge

reset_gh
git -C "$RF" config branch.feat/bad.worktree-pr-url 'https://example.invalid/owner/project/issues/5'
set_list '[]'
refresh "$RF" feat/bad "$CF"
expect_cache 'a marker that is not a pr url falls back to the branch search' 'NONE'
if grep -q '^pr list' "$GHFIX/log" && ! grep -q '^pr view' "$GHFIX/log"; then
  ok 'an invalid marker runs pr list and never pr view'
else
  not_ok "an invalid marker runs pr list and never pr view: $(cat "$GHFIX/log")"
fi
git -C "$RF" config --unset branch.feat/bad.worktree-pr-url

reset_gh
git -C "$RF" config branch.feat/c.worktree-pr-url "$PRURL/40"
set_view "$(pr_obj 40 CLOSED alice '' "$(reviews)")"
refresh "$RF" feat/c "$CF"
expect_cache 'a closed unmerged pr found through the marker caches NONE' 'NONE'
git -C "$RF" config --unset branch.feat/c.worktree-pr-url

reset_gh
git -C "$RF" config branch.feat/d.merge refs/pull/41/head
set_view "$(pr_obj 41 CLOSED alice '' "$(reviews)")"
refresh "$RF" feat/d "$CF"
expect_cache 'a closed unmerged pr found through refs/pull/<n>/head caches NONE' 'NONE'
git -C "$RF" config --unset branch.feat/d.merge

reset_gh
refresh "$RF" main "$CF"
expect_cache 'refresh on the default branch caches NONE without calling gh' 'NONE'
if [ "$(gh_calls)" = 0 ]; then ok 'the default branch makes no gh call'; else not_ok "the default branch makes no gh call: $(cat "$GHFIX/log")"; fi

reset_gh
refresh "$RFNOHEAD" master "$CF"
expect_cache 'without origin/HEAD, master is treated as the default branch' 'NONE'
if [ "$(gh_calls)" = 0 ]; then ok 'master without origin/HEAD makes no gh call'; else not_ok "master without origin/HEAD makes no gh call: $(cat "$GHFIX/log")"; fi

reset_gh
set_list '[]'
refresh "$RF" develop "$CF"
if [ "$(gh_calls)" = 1 ]; then ok 'a non-default branch name is looked up even when origin/HEAD names another branch'; else not_ok "a non-default branch name is looked up: $(gh_calls) calls"; fi

section 'refresh: trusted hosts'

reset_gh
seed_good
git -C "$RF" config branch.feat/h.worktree-pr-url 'https://attacker.invalid/owner/project/pull/50'
set_list '[]'
refresh "$RF" feat/h "$CF"
expect_cache 'a marker on a host that is not in hosts.yml is ignored' 'NONE'
if ! grep -q 'attacker.invalid' "$GHFIX/log" && grep -q '^pr list' "$GHFIX/log"; then
  ok 'a marker on a non-allowlisted host never reaches gh'
else
  not_ok "a marker on a non-allowlisted host never reaches gh: $(cat "$GHFIX/log")"
fi
git -C "$RF" config --unset branch.feat/h.worktree-pr-url

reset_gh
git -C "$RF" config branch.feat/g.worktree-pr-url 'https://github.com/owner/project/pull/60'
set_view "$(pr_obj 60 OPEN alice '' "$(reviews me APPROVED)" 'https://github.com/owner/project')"
refresh "$RF" feat/g "$CF"
expect_cache 'a marker on github.com is trusted without a hosts.yml entry' \
  "60${TAB}OPEN${TAB}approved${TAB}https://github.com/owner/project/pull/60"
if grep -q '^api --hostname github.com user' "$GHFIX/log"; then ok 'the viewer login is requested from the marker host'; else not_ok "the viewer login is requested from the marker host: $(cat "$GHFIX/log")"; fi
git -C "$RF" config --unset branch.feat/g.worktree-pr-url

reset_gh
seed_good
git -C "$RF" config branch.feat/r.worktree-pr-url 'https://github.com/owner/project/pull/61'
set_view "$(pr_obj 61 OPEN alice '' "$(reviews me APPROVED)")"
refresh "$RF" feat/r "$CF"
expect_cache 'a response url on a different host than the marker is rejected' 'NONE'
if [ "$(api_calls)" = 0 ]; then ok 'a rejected response makes no viewer lookup'; else not_ok "a rejected response makes no viewer lookup: $(cat "$GHFIX/log")"; fi
git -C "$RF" config --unset branch.feat/r.worktree-pr-url

reset_gh
seed_good
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)" 'https://attacker.invalid/owner/project')]"
refresh "$RF" feat/x "$CF"
expect_cache 'a pr list answer on a host that is not in hosts.yml is rejected' 'NONE'
if ! grep -q 'attacker.invalid' "$GHFIX/log"; then ok 'no gh call names a host that is not in hosts.yml (pr list)'; else not_ok "a gh call named the untrusted host: $(cat "$GHFIX/log")"; fi

reset_gh
seed_good
git -C "$RF" config branch.feat/q.merge refs/pull/62/head
set_view "$(pr_obj 62 OPEN alice '' "$(reviews)" 'https://attacker.invalid/owner/project')"
refresh "$RF" feat/q "$CF"
expect_cache 'a refs/pull answer on a host that is not in hosts.yml is rejected' 'NONE'
if ! grep -q 'attacker.invalid' "$GHFIX/log"; then ok 'no gh call names a host that is not in hosts.yml (refs/pull)'; else not_ok "a gh call named the untrusted host: $(cat "$GHFIX/log")"; fi
git -C "$RF" config --unset branch.feat/q.merge

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews me APPROVED)")]"
refresh "$RF" feat/x "$CF"
if [ "$(gh_calls)" = 2 ] && [ "$(grep -c 'ent:\[\]' "$GHFIX/log")" = 2 ]; then
  ok 'gh runs without the enterprise token variables'
else
  not_ok "gh runs without the enterprise token variables: $(cat "$GHFIX/log")"
fi

section 'refresh: viewer login'

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
refresh "$RF" feat/x "$CF"
if [ "$(api_calls)" = 1 ] && grep -q '^api --hostname example.invalid user --jq .login' "$GHFIX/log"; then
  ok 'the viewer login is fetched for the pr host once and cached'
else
  not_ok "the viewer login is fetched for the pr host once and cached: $(cat "$GHFIX/log")"
fi

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
printf '%s\tme\n' "$(( $(date +%s) - 90000 ))" >"$CACHE_DIR/viewer.example.invalid"
refresh "$RF" feat/x "$CF"
if [ "$(api_calls)" = 2 ]; then
  ok 'a viewer login older than 24 hours is fetched again'
else
  not_ok "a viewer login older than 24 hours is fetched again: $(cat "$GHFIX/log")"
fi

# A leading zero is octal in shell arithmetic; 08... would abort the refresh.
reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews me APPROVED)")]"
mkdir -p "$CACHE_DIR"
printf '0800000000\tme\n' >"$CACHE_DIR/viewer.example.invalid"
refresh "$RF" feat/x "$CF"
expect_cache 'a viewer file epoch with a leading zero is ignored and refetched' "7${TAB}OPEN${TAB}approved${TAB}$PRURL/7"
if [ "$(api_calls)" = 1 ]; then ok 'the leading-zero viewer file triggers a fresh lookup'; else not_ok "the leading-zero viewer file triggers a fresh lookup: $(cat "$GHFIX/log")"; fi

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
mkdir -p "$CACHE_DIR"
printf '%s\tevil\n' "$(date +%s)" >"$TMP/viewer-target"
ln -s "$TMP/viewer-target" "$CACHE_DIR/viewer.example.invalid"
seed_good
refresh "$RF" feat/x "$CF"
if [ "$(api_calls)" = 1 ] && [ "$(cat "$TMP/viewer-target")" != "$(printf '%s\tme' "$(date +%s)")" ] && grep -q evil "$TMP/viewer-target"; then
  ok 'a viewer file that is a symlink is not read and not written through'
else
  not_ok "a viewer file that is a symlink is not read and not written through: $(cat "$GHFIX/log" 2>/dev/null)"
fi
expect_cache 'a viewer file that cannot be replaced is a refresh failure that keeps the previous fields' "$GOOD"

reset_gh
seed_good
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
touch "$GHFIX/viewer-fail"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh treats a viewer login failure as a refresh failure' "$GOOD"

section 'refresh: failures and validation'

reset_gh
seed_good
touch "$GHFIX/fail"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh keeps the previous fields and bumps the epoch when gh fails' "$GOOD"

reset_gh
touch "$GHFIX/fail"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh writes NONE when gh fails and there is no previous file' 'NONE'

reset_gh
seed_cache "1000${TAB}7${TAB}OPEN${TAB}approved${TAB}https://evil.invalid/x"
touch "$GHFIX/fail"
refresh "$RF" feat/x "$CF"
expect_cache 'a previous line that fails validation is not carried forward' 'NONE'

reset_gh
seed_good
set_list 'not json'
refresh "$RF" feat/x "$CF"
expect_cache 'a gh answer that is not json keeps the previous fields' "$GOOD"

reset_gh
seed_good
set_list "$(jq -n -c --arg u "$PRURL/7" '[{number: "12x", url: $u, state: "OPEN", author: {login: "alice"}, reviewDecision: "", reviews: []}]')"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh rejects a non-numeric pr number' 'NONE'

reset_gh
seed_good
set_list "$(jq -n -c --arg u "$PRURL/7"$'\033[31m' '[{number: 7, url: $u, state: "OPEN", author: {login: "alice"}, reviewDecision: "", reviews: []}]')"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh rejects a url with control characters' 'NONE'

reset_gh
seed_good
set_list "$(jq -n -c '[{number: 7, url: "http://example.invalid/owner/project/pull/7", state: "OPEN", author: {login: "alice"}, reviewDecision: "", reviews: []}]')"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh rejects a pr url that is not https' 'NONE'

reset_gh
seed_good
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)" | jq -c --arg u "$PRURL/8" '.url = $u')]"
refresh "$RF" feat/x "$CF"
expect_cache 'refresh rejects a pr whose url number differs from its number' 'NONE'

reset_gh
seed_good
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF" "$NOGH"
expect_cache 'refresh with gh absent from PATH writes NONE' 'NONE'

reset_gh
set_list "[$(pr_obj 7 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
if grep -q 'env:1,1,cat,1,core.fsmonitor=false,core.hooksPath=/dev/null,GIT_CONFIG_COUNT=2' "$GHFIX/log" &&
   grep -q "pwd:$RF\$" "$GHFIX/log"; then
  ok 'gh runs from the repo toplevel with prompts, pager, colour and git hooks disabled'
else
  not_ok "gh runs from the repo toplevel with prompts, pager, colour and git hooks disabled: $(head -3 "$GHFIX/log")"
fi
if [ "$(grep -c 'lc:C' "$GHFIX/log")" = "$(gh_calls)" ]; then ok 'gh runs with LC_ALL=C'; else not_ok "gh runs with LC_ALL=C: $(cat "$GHFIX/log")"; fi

section 'refresh: cache paths and files'

reset_gh
set_list "[$(pr_obj 5 OPEN alice '' "$(reviews)")]"
mkdir -p "$TMP/elsewhere"
# Each path breaks one guard: the first four sit in the wrong directory with a
# valid name, the rest sit in the cache directory with an invalid name.
for bad in "$TMP/k-5" "$CACHE_DIR/../k-5" "$CACHE_DIR/sub/k-5" "relative-k-5" \
           "$CACHE_DIR/viewer.example.invalid" "$CACHE_DIR/.hidden" "$CACHE_DIR/branch-key" "$CACHE_DIR/k-5x" "$CACHE_DIR/k-"; do
  rm -f "$TMP/k-5" "$HOME/.cache/k-5"
  refresh "$RF" feat/x "$bad"
  if [ "$RSTATUS" != 0 ] && [ ! -e "$TMP/k-5" ] && [ ! -e "$HOME/.cache/k-5" ] && [ ! -e "$CACHE_DIR/sub" ] &&
     [ ! -e "$CACHE_DIR/viewer.example.invalid" ] && [ ! -e "$CACHE_DIR/.hidden" ] && [ ! -e "$CACHE_DIR/branch-key" ] &&
     [ ! -e "$CACHE_DIR/k-5x" ] && [ "$(gh_calls)" = 0 ]; then
    ok "refresh refuses the cache file path: $bad"
  else
    not_ok "refresh refuses the cache file path: $bad (status=$RSTATUS)"
  fi
done

reset_gh
refresh "$RF" "" "$CF"; empty_status=$RSTATUS
refresh "$RF" "--help" "$CF"; dash_status=$RSTATUS
if [ "$empty_status" != 0 ] && [ "$dash_status" != 0 ] && [ "$(gh_calls)" = 0 ]; then
  ok 'refresh refuses an empty branch and one starting with a dash'
else
  not_ok "refresh refuses an empty branch and one starting with a dash ($empty_status, $dash_status)"
fi

reset_gh
# From a directory that really holds refresh-repo, so only the absolute-path check can refuse it.
cd "$TMP" || exit 1
refresh 'refresh-repo' feat/x "$CF"; rel_status=$RSTATUS
cd "$REPO_ROOT" || exit 1
refresh "$TMP/no-such-toplevel" feat/x "$CF"; missing_status=$RSTATUS
if [ "$rel_status" != 0 ] && [ "$missing_status" != 0 ] && [ "$(gh_calls)" = 0 ] && [ ! -e "$CF" ]; then
  ok 'refresh refuses a relative or missing toplevel'
else
  not_ok "refresh refuses a relative or missing toplevel ($rel_status, $missing_status)"
fi

reset_gh
mkdir -p "$TMP/real-cache"
mkdir -p "$HOME/.cache"
ln -s "$TMP/real-cache" "$CACHE_DIR"
set_list "[$(pr_obj 5 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
if [ "$RSTATUS" != 0 ] && [ -z "$(ls -A "$TMP/real-cache")" ] && [ "$(gh_calls)" = 0 ]; then
  ok 'refresh refuses a cache directory that is a symlink'
else
  not_ok "refresh refuses a cache directory that is a symlink (status=$RSTATUS): $(ls -A "$TMP/real-cache")"
fi

# A failed write must also remove its temp file, so this asserts both.
reset_gh
mkdir -p "$CACHE_DIR"
mkdir "$CF"
set_list "[$(pr_obj 5 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
if [ "$RSTATUS" != 0 ] && [ -z "$(ls -A "$CF")" ] && ! ls "$CACHE_DIR"/.tmp.* >/dev/null 2>&1; then
  ok 'a cache file that is a directory is refused and leaves no temp file'
else
  not_ok "a cache file that is a directory is refused and leaves no temp file (status=$RSTATUS): $(ls -A "$CF" "$CACHE_DIR")"
fi

reset_gh
mkdir -p "$CACHE_DIR" "$TMP/link-target"
ln -s "$TMP/link-target" "$CF"
set_list "[$(pr_obj 5 OPEN alice '' "$(reviews)")]"
refresh "$RF" feat/x "$CF"
if [ "$RSTATUS" != 0 ] && [ -z "$(ls -A "$TMP/link-target")" ] && [ -L "$CF" ]; then
  ok 'a cache file that is a symlink to a directory is refused'
else
  not_ok "a cache file that is a symlink to a directory is refused (status=$RSTATUS): $(ls -A "$TMP/link-target")"
fi
rm -rf "$TMP/link-target"

reset_gh
mkdir -p "$CACHE_DIR"
mkfifo "$CF"
touch "$GHFIX/fail"
refresh_bounded "$RF" feat/x "$CF"
if [ "$RSTATUS" != timeout ] && [ "$RSTATUS" != 0 ] && [ -p "$CF" ]; then
  ok 'a cache file that is a FIFO is refused without blocking'
else
  not_ok "a cache file that is a FIFO is refused without blocking (status=$RSTATUS)"
fi
rm -f "$CF"

section 'portability'

if sed 's/#.*//' "$SCRIPT" | grep -Eq '(^|[[:space:]])(mapfile|readarray|(declare|local)[[:space:]]+-A)([[:space:]]|$)'; then
  not_ok 'uses no bash 4 builtins'
else
  ok 'uses no bash 4 builtins'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
