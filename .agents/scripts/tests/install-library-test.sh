#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
INSTALLER="$ROOT/.agents/scripts/install-library.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/install-library-test.XXXXXX")
TMP=$(CDPATH= cd -- "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
passed=0
failed=0

ok() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1"; failed=$((failed + 1)); }
run_test() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
new_source() { local name=$1; cp -R "$ROOT/.agents" "$TMP/$name"; printf '%s\n' "$TMP/$name"; }
checksum() { python3 - "$1" <<'PY'
import hashlib,sys
print('sha256:' + hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest())
PY
}
manifest_add() {
  local source=$1 relative=$2
  python3 - "$source" "$relative" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); rel=sys.argv[2]; path=root/rel.removeprefix('.agents/')
m=json.loads((root/'manifest.json').read_text()); m['ownership']['files'].append(rel); m['ownership']['files'].sort()
m['ownership']['checksums'][rel]='sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()
(root/'manifest.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
PY
}
manifest_update() { manifest_add "$@"; python3 - "$1/manifest.json" "$2" <<'PY'
import json,sys
p=sys.argv[1]; rel=sys.argv[2]; m=json.load(open(p)); m['ownership']['files']=sorted(set(m['ownership']['files'])); open(p,'w').write(json.dumps(m,indent=2,sort_keys=True)+'\n')
PY
}
trust_prior() {
  python3 - "$1" "$2" <<'PY'
import hashlib,json,pathlib,sys
new=pathlib.Path(sys.argv[1])/'manifest.json'; prior=pathlib.Path(sys.argv[2])/'manifest.json'; m=json.loads(new.read_text())
value='sha256:'+hashlib.sha256(prior.read_bytes()).hexdigest(); m['installation']['upgrade_from_manifest_sha256']=sorted(set(m['installation']['upgrade_from_manifest_sha256']+[value]))
new.write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
PY
}
manifest_remove() {
  python3 - "$1" "$2" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); rel=sys.argv[2]; m=json.loads((root/'manifest.json').read_text())
m['ownership']['files'].remove(rel); m['ownership']['checksums'].pop(rel,None)
(root/'manifest.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
PY
}

installs_complete_tree() {
  local source target="$TMP/install-target"; source=$(new_source source-install)
  "$INSTALLER" --source "$source" --target "$target" >/dev/null
  test -f "$target/skills/typescript-tips/SKILL.md" && test -f "$target/references/beads.md" &&
    test -f "$target/agents/roles.json" && test -x "$target/scripts/run-pi-role.sh" && test -f "$target/catalog.md"
}
preserves_unrelated() {
  local source target="$TMP/unrelated-target"; source=$(new_source source-unrelated)
  mkdir -p "$target/skills/custom"; printf 'mine\n' > "$target/skills/custom/SKILL.md"; printf 'keep\n' > "$target/notes.txt"
  "$INSTALLER" --source "$source" --target "$target" >/dev/null
  grep -q mine "$target/skills/custom/SKILL.md" && grep -q keep "$target/notes.txt"
}
refuses_conflict() {
  local source target="$TMP/conflict-target"; source=$(new_source source-conflict)
  mkdir -p "$target/skills/typescript-tips"; printf 'local\n' > "$target/skills/typescript-tips/SKILL.md"
  ! "$INSTALLER" --source "$source" --target "$target" >/dev/null 2>"$TMP/conflict.err" && grep -qi conflict "$TMP/conflict.err" && grep -q local "$target/skills/typescript-tips/SKILL.md"
}
dry_run_only_reports() {
  local source target="$TMP/dry-target"; source=$(new_source source-dry)
  "$INSTALLER" --source "$source" --target "$target" --dry-run >"$TMP/dry.out"
  grep -q 'INSTALL' "$TMP/dry.out" && test ! -e "$target/manifest.json"
}
replace_conflict() {
  local source target="$TMP/replace-target"; source=$(new_source source-replace)
  mkdir -p "$target/skills/typescript-tips"; printf 'local\n' > "$target/skills/typescript-tips/SKILL.md"; printf 'keep\n' > "$target/unrelated"
  "$INSTALLER" --source "$source" --target "$target" --replace >/dev/null
  grep -q '^name: typescript-tips' "$target/skills/typescript-tips/SKILL.md" && grep -q keep "$target/unrelated"
}
upgrade_removes_unmodified() {
  local v1 v2 target="$TMP/remove-target"; v1=$(new_source source-remove-v1); v2="$TMP/source-remove-v2"
  printf 'legacy\n' > "$v1/legacy.txt"; manifest_add "$v1" '.agents/legacy.txt'; "$INSTALLER" --source "$v1" --target "$target" >/dev/null
  cp -R "$v1" "$v2"; rm "$v2/legacy.txt"; manifest_remove "$v2" '.agents/legacy.txt'; trust_prior "$v2" "$v1"
  "$INSTALLER" --source "$v2" --target "$target" >/dev/null; test ! -e "$target/legacy.txt"
}
upgrade_refuses_modified_update() {
  local v1 v2 target="$TMP/modified-update-target"; v1=$(new_source source-update-v1); "$INSTALLER" --source "$v1" --target "$target" >/dev/null
  cp -R "$v1" "$TMP/source-update-v2"; v2="$TMP/source-update-v2"
  printf '\nnew source\n' >> "$v2/catalog.md"; manifest_update "$v2" '.agents/catalog.md'; trust_prior "$v2" "$v1"; printf '\nlocal\n' >> "$target/catalog.md"
  ! "$INSTALLER" --source "$v2" --target "$target" >/dev/null 2>"$TMP/update.err" && grep -qi 'locally modified' "$TMP/update.err" && grep -q local "$target/catalog.md"
}
upgrade_refuses_modified_remove() {
  local v1 v2 target="$TMP/modified-remove-target"; v1=$(new_source source-modremove-v1)
  printf 'legacy\n' > "$v1/legacy.txt"; manifest_add "$v1" '.agents/legacy.txt'; "$INSTALLER" --source "$v1" --target "$target" >/dev/null
  printf 'local\n' >> "$target/legacy.txt"; cp -R "$v1" "$TMP/source-modremove-v2"; v2="$TMP/source-modremove-v2"; rm "$v2/legacy.txt"; manifest_remove "$v2" '.agents/legacy.txt'; trust_prior "$v2" "$v1"
  ! "$INSTALLER" --source "$v2" --target "$target" >/dev/null 2>"$TMP/remove.err" && grep -qi 'locally modified' "$TMP/remove.err" && test -f "$target/legacy.txt"
}
override_modified_owned() {
  local v1 v2 target="$TMP/override-target"; v1=$(new_source source-override-v1)
  printf 'legacy\n' > "$v1/legacy.txt"; manifest_add "$v1" '.agents/legacy.txt'; "$INSTALLER" --source "$v1" --target "$target" >/dev/null
  printf 'local\n' >> "$target/legacy.txt"; printf '\nlocal\n' >> "$target/catalog.md"; cp -R "$v1" "$TMP/source-override-v2"; v2="$TMP/source-override-v2"
  rm "$v2/legacy.txt"; manifest_remove "$v2" '.agents/legacy.txt'; printf '\nnew source\n' >> "$v2/catalog.md"; manifest_update "$v2" '.agents/catalog.md'; trust_prior "$v2" "$v1"
  printf 'keep\n' > "$target/unrelated"; "$INSTALLER" --source "$v2" --target "$target" --replace >/dev/null
  test ! -e "$target/legacy.txt" && grep -q 'new source' "$target/catalog.md" && grep -q keep "$target/unrelated"
}
preserves_renamed_unowned() {
  local source target="$TMP/rename-target"; source=$(new_source source-rename); "$INSTALLER" --source "$source" --target "$target" >/dev/null
  mv "$target/catalog.md" "$target/catalog-local.md"; "$INSTALLER" --source "$source" --target "$target" >/dev/null
  test -f "$target/catalog-local.md" && test -f "$target/catalog.md"
}
checksum_mismatch_no_partial() {
  local source target="$TMP/checksum-target"; source=$(new_source source-checksum); printf '\ntampered\n' >> "$source/catalog.md"
  ! "$INSTALLER" --source "$source" --target "$target" >/dev/null 2>"$TMP/checksum.err" && grep -qi checksum "$TMP/checksum.err" && test ! -e "$target/skills"
}
rejects_source_and_target_symlinks() {
  local source target="$TMP/symlink-target" external="$TMP/external"; source=$(new_source source-symlink)
  cp "$source/catalog.md" "$external"; rm "$source/catalog.md"; ln -s "$external" "$source/catalog.md"
  ! "$INSTALLER" --source "$source" --target "$target" --replace >/dev/null 2>"$TMP/source-symlink.err" && grep -Eqi '(symlink|symbolic|unsafe|safely open)' "$TMP/source-symlink.err" || return 1
  source=$(new_source source-target-symlink); mkdir -p "$target"; printf 'outside\n' > "$external"; ln -s "$external" "$target/catalog.md"
  ! "$INSTALLER" --source "$source" --target "$target" --replace >/dev/null 2>"$TMP/target-symlink.err" && grep -Eqi '(symlink|symbolic|unsafe|safely open)' "$TMP/target-symlink.err" && grep -q '^outside$' "$external"
}
rejects_symlinked_ancestors_and_file_target() {
  local real="$TMP/real-parent" link="$TMP/link-parent" source target_file="$TMP/target-file"
  mkdir -p "$real"; cp -R "$ROOT/.agents" "$real/source"; ln -s "$real" "$link"
  ! "$INSTALLER" --source "$link/source" --target "$TMP/unused" >/dev/null 2>"$TMP/source-parent.err" && grep -Eqi '(symlink|symbolic|unsafe)' "$TMP/source-parent.err" || return 1
  source=$(new_source source-parent-target); rm "$link"; ln -s "$real" "$link"
  ! "$INSTALLER" --source "$source" --target "$link/target" >/dev/null 2>"$TMP/target-parent.err" && grep -Eqi '(symlink|symbolic|unsafe)' "$TMP/target-parent.err" || return 1
  printf 'file\n' > "$target_file"
  ! "$INSTALLER" --source "$source" --target "$target_file" --dry-run >/dev/null 2>"$TMP/target-file.err" && grep -qi 'not a directory' "$TMP/target-file.err"
}
handles_malformed_manifests_without_tracebacks() {
  local source target="$TMP/malformed-target"; source=$(new_source source-malformed); printf '[]\n' > "$source/manifest.json"
  ! "$INSTALLER" --source "$source" --target "$target" >/dev/null 2>"$TMP/source-malformed.err" && ! grep -q Traceback "$TMP/source-malformed.err" || return 1
  source=$(new_source source-mixed-trust)
  python3 - "$source/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p)); m['installation']['upgrade_from_manifest_sha256']=[1,'sha256:'+'0'*64]; open(p,'w').write(json.dumps(m))
PY
  ! "$INSTALLER" --source "$source" --target "$target" >/dev/null 2>"$TMP/mixed-trust.err" && ! grep -q Traceback "$TMP/mixed-trust.err" || return 1
  source=$(new_source source-valid-malformed); mkdir -p "$target"; printf '[]\n' > "$target/manifest.json"
  ! "$INSTALLER" --source "$source" --target "$target" >/dev/null 2>"$TMP/prior-malformed.err" && ! grep -q Traceback "$TMP/prior-malformed.err" || return 1
  "$INSTALLER" --source "$source" --target "$target" --replace >/dev/null && test -f "$target/catalog.md"
}
untrusted_prior_cannot_claim_unrelated_files() {
  local source target="$TMP/untrusted-prior-target"; source=$(new_source source-untrusted); "$INSTALLER" --source "$source" --target "$target" >/dev/null
  printf 'keep\n' > "$target/unrelated.txt"
  python3 - "$target" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); p=root/'manifest.json'; m=json.loads(p.read_text()); rel='.agents/unrelated.txt'
m['ownership']['files'].append(rel); m['ownership']['files'].sort(); m['ownership']['checksums'][rel]='sha256:'+hashlib.sha256((root/'unrelated.txt').read_bytes()).hexdigest(); p.write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
PY
  ! "$INSTALLER" --source "$source" --target "$target" >/dev/null 2>"$TMP/untrusted.err" && grep -qi authenticated "$TMP/untrusted.err" || return 1
  "$INSTALLER" --source "$source" --target "$target" --replace >/dev/null && grep -q keep "$target/unrelated.txt"
}
repairs_owned_mode_drift() {
  local source target="$TMP/mode-target"; source=$(new_source source-mode); "$INSTALLER" --source "$source" --target "$target" >/dev/null
  chmod 0644 "$target/scripts/run-pi-role.sh"; "$INSTALLER" --source "$source" --target "$target" >/dev/null
  test -x "$target/scripts/run-pi-role.sh"
}
idempotent_install() {
  local source target="$TMP/idempotent-target" before after; source=$(new_source source-idempotent); "$INSTALLER" --source "$source" --target "$target" >/dev/null
  before=$(checksum "$target/manifest.json"); "$INSTALLER" --source "$source" --target "$target" >"$TMP/idempotent.out"; after=$(checksum "$target/manifest.json")
  test "$before" = "$after" && grep -q 'no changes' "$TMP/idempotent.out"
}
installed_project_validates() {
  local project="$TMP/validated-project"
  mkdir -p "$project/archive"; cp -R "$ROOT/.claude" "$project/.claude"; cp -R "$ROOT/.codex" "$project/.codex"; cp -R "$ROOT/docs" "$project/docs"
  cp "$ROOT/AGENTS.md" "$ROOT/README.md" "$ROOT/CLAUDE.md" "$project/"
  "$INSTALLER" --source "$ROOT/.agents" --target "$project/.agents" >/dev/null
  python3 "$ROOT/.agents/scripts/validate-library.py" --root "$project" >/dev/null && cmp "$ROOT/.agents/manifest.json" "$project/.agents/manifest.json"
}
manifest_covers_installer() {
  python3 - "$ROOT" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); m=json.loads((root/'.agents/manifest.json').read_text()); owned=set(m['ownership']['files']); sums=set(m['ownership']['checksums'])
need={'.agents/scripts/install-library.sh','.agents/scripts/tests/install-library-test.sh'}
raise SystemExit(0 if need <= owned and need <= sums else 1)
PY
}

run_test 'installs skills references agents scripts and catalog together' installs_complete_tree
run_test 'preserves unrelated target skills and files' preserves_unrelated
run_test 'refuses a conflicting existing file by default' refuses_conflict
run_test 'dry run reports changes without writing' dry_run_only_reports
run_test 'explicit replace updates only manifest-owned paths' replace_conflict
run_test 'upgrade removes unmodified files owned only by prior manifest' upgrade_removes_unmodified
run_test 'upgrade refuses locally modified prior-owned update' upgrade_refuses_modified_update
run_test 'upgrade refuses locally modified prior-owned removal' upgrade_refuses_modified_remove
run_test 'explicit override updates or removes only modified owned files' override_modified_owned
run_test 'upgrade preserves renamed paths not owned by either manifest' preserves_renamed_unowned
run_test 'checksum mismatch prevents partial installation' checksum_mismatch_no_partial
run_test 'source and target symlinks are rejected without following' rejects_source_and_target_symlinks
run_test 'symlinked ancestors and file targets are rejected' rejects_symlinked_ancestors_and_file_target
run_test 'malformed manifests fail cleanly and replace can recover' handles_malformed_manifests_without_tracebacks
run_test 'untrusted prior manifest cannot claim unrelated files' untrusted_prior_cannot_claim_unrelated_files
run_test 'owned executable mode drift is repaired' repairs_owned_mode_drift
run_test 'repeated identical installation is idempotent' idempotent_install
run_test 'installed project validates with source inventory' installed_project_validates
run_test 'final manifest covers installer files' manifest_covers_installer

printf '%s passed; %s failed\n' "$passed" "$failed"
test "$failed" -eq 0
