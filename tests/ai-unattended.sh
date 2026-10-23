#!/bin/bash
# zeltro ai-unattended: turns an agent's own approval setting on or off and
# nothing else (no .env change, no install), reads it back, and gives the app
# an error code it can branch on. ai-status reports the same setting. Fake
# agents on PATH and a sandboxed HOME; no network.
#
#   bash tests/ai-unattended.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
unset NVM_DIR
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

mkdir -p "$T/bin" "$T/home"
for a in claude codex; do
    cat > "$T/bin/$a" <<'FAKE'
#!/bin/sh
case "$*" in
    --version) echo "9.9.9" ;;
    "auth status --json") echo '{"loggedIn": false, "authMethod": "none"}'; exit 1 ;;
    "login status") echo "Not logged in"; exit 1 ;;
esac
FAKE
    chmod +x "$T/bin/$a"
done
mkdir -p "$T/home/.codex"
echo 'model = "gpt-test"' > "$T/home/.codex/config.toml"

z() { ( export HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" NO_COLOR=1; "$REPO/src/zeltro" "$@" 2>/dev/null </dev/null ) }
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1].strip().splitlines()[-1]); print(d.get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
envsum() { cksum < /etc/zeltro-cli/.env 2>/dev/null; }

before="$(envsum)"

echo "on / off"
out="$(z ai-unattended --agent claude on --json-output)"
check "claude on: success" "$(field "$out" status)" "success"
check "claude on: unattended true (read back)" "$(field "$out" unattended)" "true"
check "written to the agent's own settings" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["defaultMode"])' "$T/home/.claude/settings.json")" "bypassPermissions"
check "stdout is one JSON line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"
check "ai-status agrees" "$(field "$(z ai-status --agent claude --json-output)" unattended)" "true"
out="$(z ai-unattended --agent claude off --json-output)"
check "claude off: unattended false" "$(field "$out" unattended)" "false"
check "ai-status agrees" "$(field "$(z ai-status --agent claude --json-output)" unattended)" "false"

out="$(z ai-unattended --agent codex on --json-output)"
check "codex on" "$(field "$out" unattended)" "true"
check "codex: the user's own keys kept" "$(grep -c '^model = "gpt-test"' "$T/home/.codex/config.toml")" "1"
check "ai-status for codex" "$(field "$(z ai-status --agent codex --json-output)" unattended)" "true"
check "ai-status for another agent doesn't borrow it" "$(field "$(z ai-status --agent claude --json-output)" unattended)" "false"

echo "older forms still work"
check "positional agent + --status" "$(field "$(z ai-unattended codex --status --json-output)" unattended)" "true"
check "positional agent + --revoke" "$(field "$(z ai-unattended codex --revoke --json-output)" unattended)" "false"
check "no on/off means on" "$(field "$(z ai-unattended --agent codex --json-output)" unattended)" "true"

echo "errors"
out="$(z ai-unattended --agent gemini on --json-output)"; rc=$?
check "not installed: error code" "$(field "$out" error)" "not_installed"
check "not installed: exit 1" "$rc" "1"
check "not installed: nothing written" "$([ -e "$T/home/.gemini/settings.json" ] && echo written || echo none)" "none"
check "unknown agent" "$(field "$(z ai-unattended --agent cursor on --json-output)" error)" "unknown_agent"
check "status works for an agent that isn't installed" "$(field "$(z ai-unattended --agent gemini status --json-output)" unattended)" "false"
rm -f "$T/home/.claude/settings.json"; mkdir -p "$T/home/.claude/settings.json"
out="$(z ai-unattended --agent claude on --json-output)"; rc=$?
check "unwritable config: write_failed" "$(field "$out" error)" "write_failed"
check "unwritable config: exit 1" "$rc" "1"
rmdir "$T/home/.claude/settings.json"

echo "scope"
check "/etc/zeltro-cli/.env untouched" "$(envsum)" "$before"
check "human output" "$(z ai-unattended --agent claude on | grep -c 'unattended')" "1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
