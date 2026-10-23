#!/bin/bash
# Codex with an API key: the key is handed over through `codex login
# --with-api-key` in a Zeltro-managed CODEX_HOME (Codex ignores OPENAI_API_KEY),
# and the user's own ~/.codex is never touched. Also: create's classifier passes
# the agent's real error through (agent_failed vs no_stack) and stops a run as
# soon as it shows a 4xx. Uses a fake `codex` on PATH and a sandboxed HOME;
# no network, no keys.
#
#   bash tests/codex-key.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }

# A fake codex: `login --with-api-key` stores the key; `exec` answers per FAKE_CODEX.
mkdir -p "$T/bin" "$T/home/.codex"
cat > "$T/bin/codex" <<'FAKE'
#!/bin/bash
if [ "$1" = "login" ]; then
    mkdir -p "$CODEX_HOME"; cat > "$CODEX_HOME/auth.json"; exit 0
fi
if [ "$1" = "--version" ]; then echo "codex-cli 0.128.0"; exit 0; fi
echo "user" >&2; echo "prompt with a {\"template\": true} in it" >&2
case "${FAKE_CODEX:-ok}" in
    ok) echo '{"project_name":"todo","recommended":"framework","customization_requested":true,"framework":{"slug":"flask","reason":"small"},"apps":[],"folder":null,"database":{"slug":"sqlite","reason":"tiny"}}' ;;
    401) echo "ERROR: unexpected status 401 Unauthorized: Incorrect API key provided: sk-proj-****0000. You can find your API key at https://platform.openai.com/account/api-keys., url: https://api.openai.com/v1/responses, request id: req_1" >&2; sleep 60; exit 1 ;;
    garbage) echo "I am not sure what you mean." ;;
    markdown) echo '{"project_name":"pedal-lending","recommended":"app","customization_requested":false,"framework":{"slug":"flask","reason":"**Custom** tracker, see https://flask.palletsprojects.com."},"apps":[{"slug":"snipe-it","reason":"Tracks pedals [checked out to friends](https://snipe-it.readme.io/docs/overview) and checked back in upon return."}],"folder":null,"database":{"slug":"sqlite","reason":"`sqlite` is tiny"}}' ;;
esac
FAKE
chmod +x "$T/bin/codex"
echo 'approval_policy = "never"' > "$T/home/.codex/config.toml"
echo '{"chatgpt": "the user own login"}' > "$T/home/.codex/auth.json"
USER_AUTH_BEFORE="$(cat "$T/home/.codex/auth.json")"

# zeltro_codex_prepare in a clean subshell with the sandboxed HOME.
prep() { # <key> [base]
    ( export HOME="$T/home" PATH="$T/bin:$PATH"; unset CODEX_HOME
      cd "$REPO/src" && set +u && source scripts/functions.sh >/dev/null 2>&1
      AI_API_KEY="$1" AI_API_BASE="${2:-}"
      zeltro_codex_prepare && echo "${CODEX_HOME:-<unset>}" )
}

echo "managed CODEX_HOME"
h1="$(prep sk-proj-one)"
check "a key gets a Zeltro CODEX_HOME" "${h1%/*}" "$T/home/.zeltro/codex"
check "logged in with that key" "$(cat "$h1/auth.json")" "sk-proj-one"
check "auth.json is private" "$(stat -c %a "$h1" 2>/dev/null || stat -f %Lp "$h1")" "700"
check "user's config.toml linked in" "$(readlink "$h1/config.toml")" "$T/home/.codex/config.toml"
check "same key, same home (resume works)" "$(prep sk-proj-one)" "$h1"
h2="$(prep sk-proj-two)"
check "another key, another home" "$([ "$h2" != "$h1" ] && echo different)" "different"
check "no key: Codex's own sign-in" "$(prep '')" "<unset>"
check "not an OpenAI key, no endpoint: ignored" "$(prep 'abc123')" "<unset>"
check "custom endpoint: no sign-in, the key goes by env (zeltro_codex_base_args)" "$(prep 'or-key' https://openrouter.ai/api/v1)" "<unset>"
check "user's own auth.json untouched" "$(cat "$T/home/.codex/auth.json")" "$USER_AUTH_BEFORE"
check "the key is not in the folder name" "$(ls "$T/home/.zeltro/codex" | grep -c sk-proj)" "0"

echo "classifier errors"
mkdir -p "$T/projects"
run_classify() { # <FAKE_CODEX mode>
    ( export HOME="$T/home" PATH="$T/bin:$PATH" FAKE_CODEX="$1" ZELTRO_TEST_PROJECTS_DIR="$T/projects"
      unset CODEX_HOME
      cd "$T" && ZELTRO_AI_AGENT=codex ZELTRO_AI_MODEL=gpt-test ZELTRO_AI_API_BASE= ZELTRO_AI_API_KEY=sk-proj-one \
        "$REPO/src/zeltro" create --classify-only --json-output "A simple to-do list website" 2>/dev/null | tail -n 1 )
}
field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }

out="$(run_classify ok)"
check "a good answer classifies" "$(field "$out" status)" "success"
check "prompt echoed on stderr doesn't confuse the parser" "$(field "$out" recommended)" "framework"
start=$(date +%s)
out="$(run_classify 401)"
took=$(( $(date +%s) - start ))
check "a 401 is agent_failed" "$(field "$out" error)" "agent_failed"
check "with the agent's own words" "$(field "$out" message | grep -c 'Codex: unexpected status 401 Unauthorized: Incorrect API key provided')" "1"
check "url and request id trimmed" "$(field "$out" message | grep -c 'request id')" "0"
check "stopped early, not after the agent's retries ($took s)" "$([ "$took" -lt 30 ] && echo fast)" "fast"
out="$(run_classify markdown)"
reasons="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(" | ".join(c["reason"] for c in d["candidates"]) + " | " + d["database"]["reason"])' "$out" 2>/dev/null)"
check "markdown stripped from reasons" "$reasons" \
    "Tracks pedals checked out to friends and checked back in upon return. | Custom tracker, see. | sqlite is tiny"
out="$(run_classify garbage)"
check "an unusable answer is no_stack" "$(field "$out" error)" "no_stack"
out="$( ( export HOME="$T/home" PATH="$T/bin:$PATH" FAKE_CODEX=401 ZELTRO_TEST_PROJECTS_DIR="$T/projects"; cd "$T" && ZELTRO_AI_AGENT=codex ZELTRO_AI_MODEL=gpt-test ZELTRO_AI_API_BASE= ZELTRO_AI_API_KEY=sk-proj-one "$REPO/src/zeltro" create --one-off --json-output "A simple to-do list website" 2>/dev/null | tail -n 1 ) )"
check "create (not just classify) reports it too" "$(field "$out" error)" "agent_failed"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
