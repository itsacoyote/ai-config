#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
RUNNER="$ROOT/.agents/scripts/run-pi-role.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/run-pi-role-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
run_test() {
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

cat >"$TMP/pi" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
cat >"${PI_ROLE_STDIN_CAPTURE:-/dev/null}"
if [[ -n "${PI_ROLE_FAKE_PID_FILE:-}" ]]; then printf '%s\n' "$$" >"$PI_ROLE_FAKE_PID_FILE"; fi
trap 'exit 143' TERM
python3 - "$PI_ROLE_CAPTURE" "$@" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]))
PY
if [[ -n "${PI_ROLE_FAKE_SLEEP:-}" ]]; then sleep "$PI_ROLE_FAKE_SLEEP"; fi
printf '%s\n' "${PI_ROLE_FAKE_OUTPUT:-fake-pi-output}"
FAKE
chmod +x "$TMP/pi"

export PATH="$TMP:$PATH"
export PI_ROLE_LOCK_ROOT="$TMP/locks"

capture_run() {
  local capture=$1
  shift
  rm -f "$capture"
  PI_ROLE_CAPTURE="$capture" "$RUNNER" "$@" >/dev/null
}

json_assert() {
  local capture=$1
  local expression=$2
  python3 - "$capture" "$expression" <<'PY'
import json, sys
args = json.loads(open(sys.argv[1]).read())
if not eval(sys.argv[2], {"args": args}):
    raise SystemExit(f"assertion failed: {sys.argv[2]}\nargv={args!r}")
PY
}

test_unknown_role() {
  local capture="$TMP/unknown.json"
  rm -f "$capture"
  if PI_ROLE_CAPTURE="$capture" "$RUNNER" no-such-role -- "task" >"$TMP/out" 2>"$TMP/err"; then return 1; fi
  [[ ! -e "$capture" ]] && grep -q 'unknown role' "$TMP/err"
}

test_ephemeral_default() {
  local capture="$TMP/ephemeral.json"
  capture_run "$capture" senior-review -- "review only"
  json_assert "$capture" "'--no-session' in args and '--print' in args"
}

test_task_is_one_safe_argument() {
  local capture="$TMP/task.json"
  local marker="$TMP/must-not-exist"
  local task="literal ; touch $marker \$(touch $marker)\nsecond line"
  capture_run "$capture" senior-review -- "$task"
  [[ ! -e "$marker" ]] && TASK="$task" python3 - "$capture" <<'PY'
import json, os, sys
args = json.loads(open(sys.argv[1]).read())
assert args[-1].startswith("Parent task follows.")
assert args[-1].endswith(os.environ["TASK"])
assert args[-1].count(os.environ["TASK"]) == 1
PY
}

test_ambient_resources_excluded() {
  local capture="$TMP/ambient.json"
  local stdin_capture="$TMP/stdin.txt"
  rm -f "$capture" "$stdin_capture"
  printf 'ambient piped prompt injection' | PI_ROLE_CAPTURE="$capture" PI_ROLE_STDIN_CAPTURE="$stdin_capture" "$RUNNER" senior-review -- "review" >/dev/null
  json_assert "$capture" "all(flag in args for flag in ['--no-approve','--no-skills','--no-extensions','--no-context-files','--no-prompt-templates','--no-themes']) and '--skill' not in args"
  [[ ! -s "$stdin_capture" ]]
}

test_cli_like_tasks_are_data() {
  local capture="$TMP/cli-like.json"
  local task
  for task in '--approve' '--continue' '--no-tools' '@/etc/passwd'; do
    capture_run "$capture" senior-review -- "$task"
    TASK="$task" python3 - "$capture" <<'PY'
import json, os, sys
args = json.loads(open(sys.argv[1]).read())
assert args[-1].startswith("Parent task follows.")
assert args[-1].endswith(os.environ["TASK"])
PY
  done
}

test_system_prompts_overridden() {
  local capture="$TMP/system.json"
  capture_run "$capture" senior-review -- "review"
  json_assert "$capture" "args.count('--system-prompt') == 1 and args.count('--append-system-prompt') >= 3 and 'isolated Pi worker' in args[args.index('--system-prompt') + 1]"
}

test_declared_resources_only() {
  local capture="$TMP/resources.json"
  capture_run "$capture" senior-review -- "review"
  ROOT="$ROOT" python3 - "$capture" <<'PY'
import json, os, sys
from pathlib import Path
args = json.loads(open(sys.argv[1]).read())
root = Path(os.environ["ROOT"])
appended = [args[i + 1] for i, value in enumerate(args[:-1]) if value == "--append-system-prompt"]
expected = {
    str((root / "AGENTS.md").resolve()),
    str((root / ".agents/agents/senior-review.md").resolve()),
    str((root / ".agents/skills/senior-review/SKILL.md").resolve()),
}
assert set(appended) == expected, (appended, expected)
PY
}

test_extension_opt_in() {
  local capture="$TMP/extension.json"
  local extension="$TMP/reviewed-extension.ts"
  printf 'export default function () {}\n' >"$extension"
  capture_run "$capture" --extension "$extension" senior-review -- "review"
  EXTENSION="$extension" python3 - "$capture" <<'PY'
import json, os, sys
args = json.loads(open(sys.argv[1]).read())
assert "--no-extensions" in args
index = args.index("--extension")
assert args[index + 1] == os.environ["EXTENSION"]
PY
}

test_direct_implementation_requires_sandbox_launcher() {
  local capture="$TMP/direct-implementation.json"
  rm -f "$capture"
  if PI_ROLE_SANDBOXED_IMPLEMENTATION=1 PI_ROLE_CAPTURE="$capture" "$RUNNER" implementer -- "edit" >"$TMP/out" 2>"$TMP/err"; then return 1; fi
  [[ ! -e "$capture" ]] && grep -q 'disabled in the generic runner' "$TMP/err"
}

test_parallel_implementation_rejected() {
  local capture="$TMP/parallel.json"
  rm -f "$capture"
  if PI_ROLE_CAPTURE="$capture" "$RUNNER" --parallel implementer -- "edit" >"$TMP/out" 2>"$TMP/err"; then return 1; fi
  [[ ! -e "$capture" ]] && grep -q 'cannot run in parallel' "$TMP/err"
  if PI_ROLE_CAPTURE="$capture" "$RUNNER" --parallel qa-review -- "verify" >"$TMP/out" 2>"$TMP/err"; then return 1; fi
  [[ ! -e "$capture" ]] && grep -q 'cannot run in parallel' "$TMP/err"
}

test_full_absolute_methodology_paths() {
  local capture="$TMP/methodology.json"
  capture_run "$capture" qa-review -- "bounded verification"
  ROOT="$ROOT" python3 - "$capture" <<'PY'
import json, os, sys
from pathlib import Path
args = json.loads(open(sys.argv[1]).read())
root = Path(os.environ["ROOT"])
appended = [args[i + 1] for i, value in enumerate(args[:-1]) if value == "--append-system-prompt"]
expected = [
    root / "AGENTS.md",
    root / ".agents/agents/qa-review.md",
    root / ".agents/skills/qa-review/SKILL.md",
    root / ".agents/skills/writing-tests/SKILL.md",
]
for path in expected:
    resolved = str(path.resolve())
    assert resolved in appended, resolved
    assert path.read_text(), path
PY
}

test_out_of_tree_skill_symlink_fails_closed() {
  local fixture="$TMP/symlink-fixture"
  local capture="$TMP/symlink.json"
  mkdir -p "$fixture"
  cp -R "$ROOT/.agents" "$fixture/.agents"
  cp "$ROOT/AGENTS.md" "$fixture/AGENTS.md"
  printf '%s\n' '# outside methodology' >"$TMP/outside-skill.md"
  rm "$fixture/.agents/skills/senior-review/SKILL.md"
  ln -s "$TMP/outside-skill.md" "$fixture/.agents/skills/senior-review/SKILL.md"
  rm -f "$capture"
  if PI_ROLE_CAPTURE="$capture" "$fixture/.agents/scripts/run-pi-role.sh" senior-review -- "review" >"$TMP/out" 2>"$TMP/err"; then
    return 1
  fi
  [[ ! -e "$capture" ]] && grep -q 'containment failed' "$TMP/err"
}

test_verification_lock() {
  local first="$TMP/lock-first.json"
  local second="$TMP/lock-second.json"
  PI_ROLE_CAPTURE="$first" PI_ROLE_FAKE_SLEEP=2 "$RUNNER" qa-review -- "first" >"$TMP/first-out" 2>"$TMP/first-err" &
  local pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -e "$first" ]] && break
    sleep 0.1
  done
  if PI_ROLE_CAPTURE="$second" "$RUNNER" qa-review -- "second" >"$TMP/second-out" 2>"$TMP/second-err"; then
    wait "$pid"
    return 1
  fi
  wait "$pid"
  [[ ! -e "$second" ]] && grep -q 'already active' "$TMP/second-err"
}

test_signal_forwarding_and_cleanup() {
  local capture="$TMP/signal.json"
  local child_pid_file="$TMP/child.pid"
  PI_ROLE_CAPTURE="$capture" PI_ROLE_FAKE_PID_FILE="$child_pid_file" PI_ROLE_FAKE_SLEEP=30 \
    "$RUNNER" qa-review -- "cancel me" >"$TMP/signal-out" 2>"$TMP/signal-err" &
  local runner_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ -s "$child_pid_file" ]] && break
    sleep 0.1
  done
  [[ -s "$child_pid_file" ]] || { kill "$runner_pid" 2>/dev/null || true; wait "$runner_pid" 2>/dev/null || true; return 1; }
  local child_pid
  IFS= read -r child_pid <"$child_pid_file"
  kill -TERM "$runner_pid"
  set +e
  wait "$runner_pid"
  local status=$?
  set -e
  [[ $status -eq 143 ]] || return 1
  ! kill -0 "$child_pid" 2>/dev/null
}

test_saved_session_opt_in() {
  local capture="$TMP/session.json"
  local resume="$TMP/resume.json"
  capture_run "$capture" --save-session "role smoke" senior-review -- "review"
  json_assert "$capture" "'--no-session' not in args and '--name' in args and args[args.index('--name') + 1] == 'role smoke'"
  capture_run "$resume" --session "session-id" senior-review -- "continue review"
  json_assert "$resume" "'--no-session' not in args and '--session' in args and args[args.index('--session') + 1] == 'session-id'"
}

test_tools_derive_from_role() {
  local review="$TMP/review-tools.json"
  local verification="$TMP/verification-tools.json"
  capture_run "$review" senior-review -- "review"
  capture_run "$verification" qa-review -- "verify"
  json_assert "$review" "args[args.index('--tools') + 1] == 'read,grep,find,ls,bash'"
  json_assert "$verification" "args[args.index('--tools') + 1] == 'read,grep,find,ls,bash,browser,write'"
}

run_test 'rejects unknown roles before spawning pi' test_unknown_role
run_test 'defaults to an ephemeral child session' test_ephemeral_default
run_test 'preserves task text as one argument without evaluation' test_task_is_one_safe_argument
run_test 'excludes ambient project approval skills extensions context and stdin by default' test_ambient_resources_excluded
run_test 'keeps CLI-like task prefixes inside task data' test_cli_like_tasks_are_data
run_test 'overrides ambient global SYSTEM and APPEND_SYSTEM prompts' test_system_prompts_overridden
run_test 're-adds only declared role resources and trusted root guidance explicitly' test_declared_resources_only
run_test 'requires an explicit opt-in to load extensions' test_extension_opt_in
run_test 'rejects direct implementation without the sandbox launcher' test_direct_implementation_requires_sandbox_launcher
run_test 'rejects parallel execution for a source-editing role' test_parallel_implementation_rejected
run_test 'preloads full declared skill files and role prompt by absolute path' test_full_absolute_methodology_paths
run_test 'fails closed when a declared skill resolves outside the library' test_out_of_tree_skill_symlink_fails_closed
run_test 'serializes verification workers with an atomic lock' test_verification_lock
run_test 'forwards cancellation to Pi and cleans up the lock' test_signal_forwarding_and_cleanup
run_test 'allows saved sessions only by explicit opt-in' test_saved_session_opt_in
run_test 'derives built-in tools from the neutral role capabilities' test_tools_derive_from_role

if [[ "${RUN_REAL_PI_TESTS:-0}" == 1 ]]; then
  unset PI_ROLE_CAPTURE PI_ROLE_FAKE_SLEEP
  before=$(git -C "$ROOT" status --porcelain)
  output=$(
    "$RUNNER" efficiency-review -- \
      "Review only the unstaged diff for .agents/agents/roles.json. It is expected to be empty. Follow your exact role return contract and do not write files."
  )
  after=$(git -C "$ROOT" status --porcelain)
  normalized_output=$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')
  if [[ "$before" == "$after" && "$normalized_output" == *'nothing to review'* && "$output" == *'STATUS: DONE'* ]]; then
    pass 'role output follows a methodology-specific return contract in a real Pi smoke run'
  else
    printf 'real Pi output: %s\n' "$output" >&2
    fail 'role output follows a methodology-specific return contract in a real Pi smoke run'
  fi

  qa_output=$(
    "$RUNNER" qa-review -- \
      "Verify only that README.md exists and is readable. Do not run project checks or write files. Return a schema-version-1 APPROVED QA JSON envelope with concise evidence."
  )
  printf '%s\n' "$qa_output" >"$TMP/qa-result.json"
  after_qa=$(git -C "$ROOT" status --porcelain)
  if [[ "$before" == "$after_qa" ]] && python3 "$ROOT/.agents/scripts/validate-qa-result.py" "$TMP/qa-result.json" >/dev/null; then
    pass 'qa returns a schema-valid versioned result envelope and never edits source'
  else
    fail 'qa returns a schema-valid versioned result envelope and never edits source'
  fi
else
  printf 'ok - role output follows a methodology-specific return contract in a real Pi smoke run # SKIP set RUN_REAL_PI_TESTS=1\n'
  printf 'ok - qa returns a schema-valid versioned result envelope and never edits source # SKIP set RUN_REAL_PI_TESTS=1\n'
fi

printf '%s passed; %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
