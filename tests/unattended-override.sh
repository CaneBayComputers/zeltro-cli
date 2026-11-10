#!/bin/bash
# ZELTRO_AI_UNATTENDED=1/0 picks each agent's per-run approval flags, and
# only Claude's one-time consent key is ever written. No agents are run.
#
#   bash tests/unattended-override.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# <env assignments> <agent> -> the args, then "|OPENCODE_PERMISSION"
args_for() {
    env -u ZELTRO_AI_UNATTENDED -u ZELTRO_AI_AUTO_APPROVE -u OPENCODE_PERMISSION \
        CLAUDE_CONFIG_DIR="${CDIR:-$T/claude}" $1 bash -c "
        cd '$REPO/src' && set +u && source scripts/functions.sh >/dev/null 2>&1
        zeltro_unattended_args $2
        echo \"\${ZELTRO_UNATTENDED_ARGS[*]}|\${OPENCODE_PERMISSION:-}\""
}

echo "unset: the agent's own config decides"
for a in claude codex qwen gemini agy opencode hermes aider; do
    check "$a" "$(args_for "" $a)" "|"
done

echo "ZELTRO_AI_UNATTENDED=1"
check claude   "$(args_for ZELTRO_AI_UNATTENDED=1 claude)"   "--dangerously-skip-permissions|"
check codex    "$(args_for ZELTRO_AI_UNATTENDED=1 codex)"    "--dangerously-bypass-approvals-and-sandbox|"
check qwen     "$(args_for ZELTRO_AI_UNATTENDED=1 qwen)"     "--yolo|"
check gemini   "$(args_for ZELTRO_AI_UNATTENDED=1 gemini)"   "--yolo --skip-trust|"
check agy      "$(args_for ZELTRO_AI_UNATTENDED=1 agy)"      "--dangerously-skip-permissions|"
check opencode "$(args_for ZELTRO_AI_UNATTENDED=1 opencode)" "--auto|"
check hermes   "$(args_for ZELTRO_AI_UNATTENDED=1 hermes)"   "--yolo|"
check aider    "$(args_for ZELTRO_AI_UNATTENDED=1 aider)"    "--yes-always|"
check "older ZELTRO_AI_AUTO_APPROVE=1 still means 1" "$(args_for ZELTRO_AI_AUTO_APPROVE=1 codex)" "--dangerously-bypass-approvals-and-sandbox|"
check "ZELTRO_AI_UNATTENDED=0 beats AUTO_APPROVE=1" "$(args_for "ZELTRO_AI_AUTO_APPROVE=1 ZELTRO_AI_UNATTENDED=0" qwen)" "--approval-mode default|"

echo "ZELTRO_AI_UNATTENDED=0"
check claude   "$(args_for ZELTRO_AI_UNATTENDED=0 claude)"   "--permission-mode manual|"
check codex    "$(args_for ZELTRO_AI_UNATTENDED=0 codex)"    "--ask-for-approval on-request --sandbox workspace-write|"
check qwen     "$(args_for ZELTRO_AI_UNATTENDED=0 qwen)"     "--approval-mode default|"
check gemini   "$(args_for ZELTRO_AI_UNATTENDED=0 gemini)"   "--approval-mode default|"
check "agy (no per-run ask switch)" "$(args_for ZELTRO_AI_UNATTENDED=0 agy)" "|"
check opencode "$(args_for ZELTRO_AI_UNATTENDED=0 opencode)" '|{"*":"ask"}'
check "hermes (no per-run ask switch)" "$(args_for ZELTRO_AI_UNATTENDED=0 hermes)" "|"
check aider    "$(args_for ZELTRO_AI_UNATTENDED=0 aider)"    "--no-yes-always|"

echo "Claude's consent key"
check "0 writes nothing" "$(CDIR="$T/claude0" args_for ZELTRO_AI_UNATTENDED=0 claude >/dev/null; ls "$T/claude0" 2>/dev/null | wc -l)" "0"
mkdir -p "$T/claude"; echo '{"model": "opus", "permissions": {"defaultMode": "default"}}' > "$T/claude/settings.json"
args_for ZELTRO_AI_UNATTENDED=1 claude >/dev/null
check "1 adds only skipDangerousModePermissionPrompt" \
    "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$T/claude/settings.json")" \
    '{"model": "opus", "permissions": {"defaultMode": "default"}, "skipDangerousModePermissionPrompt": true}'
echo 'not json {' > "$T/claude/settings.json"
args_for ZELTRO_AI_UNATTENDED=1 claude >/dev/null
check "an unparseable settings file is left alone" "$(cat "$T/claude/settings.json")" "not json {"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
