#!/bin/bash
# Agent sign-in and profile translation: `zeltro ai-status`, `zeltro ai-login`,
# the capabilities in `ai-set --json-output`, and how a profile's key, endpoint
# and model reach each agent (zeltro_agent_env, aider's arguments).
#
# 2026-10-23: the app moved to profiles (subscription, API key, or custom
# endpoint) and signs agents in itself on local, WSL and SSH hosts. A Windows
# user's Create with AI failed with Codex's raw "401 Missing bearer" because
# Codex was never signed in on their WSL.
#
# Uses fake claude/codex binaries in a throwaway HOME; no real sign-in, network
# or config is touched. Needs /etc/zeltro-cli/.env (functions.sh loads it).
#
#   bash tests/ai-auth.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }

B="$T/bin"; mkdir -p "$B" "$T/home"
# Fake Claude Code: `auth status --json` reads $T/claude-in; `auth login` prints
# the paste link (and hands $BROWSER a localhost link), accepts GOOD-CODE.
cat > "$B/claude" << EOF
#!/bin/bash
S="$T/claude-in"
case "\$1 \$2" in
  "--version ") echo "9.9.9 (Claude Code)" ;;
  "auth status")
    if [ -f "\$S" ]; then echo '{"loggedIn": true, "authMethod": "claude.ai", "email": "u@example.com", "subscriptionType": "pro"}'; exit 0; fi
    echo '{"loggedIn": false, "authMethod": "none"}'; exit 1 ;;
  "auth login")
    [ -n "\$BROWSER" ] && "\$BROWSER" "https://claude.com/cai/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A5555%2Fcallback"
    if [ -n "\${FAKE_CALLBACK:-}" ]; then sleep 1; touch "\$S"; echo "Login successful."; exit 0; fi
    echo "If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&state=x"
    printf 'Paste code here if prompted > '
    while IFS= read -r code; do
      if [ "\$code" = "GOOD-CODE" ]; then touch "\$S"; echo "Login successful."; exit 0; fi
      if [ "\$code" = "WRONG-400" ]; then echo "Login failed: Request failed with status code 400"; exit 1; fi
      echo " Invalid code. Please make sure the full code was copied."
    done
    exit 1 ;;
esac
EOF
# Fake Codex: `login status` reads $T/codex-in; `login --device-auth` prints a
# device code and signs in a moment later.
cat > "$B/codex" << EOF
#!/bin/bash
S="$T/codex-in"
case "\$1 \$2" in
  "--version ") echo "codex-cli 0.999.0" ;;
  "login status") if [ -f "\$S" ]; then cat "\$S"; exit 0; fi; echo "Not logged in"; exit 1 ;;
  "login --device-auth")
    printf '1. Open this link in your browser and sign in to your account\n   \033[94mhttps://auth.openai.com/codex/device\033[0m\n\n2. Enter this one-time code (expires in 15 minutes)\n   \033[94mABCD-12345\033[0m\n'
    sleep "\${FAKE_WAIT:-1}"; echo "Logged in using ChatGPT" > "\$S"; echo "Successfully logged in" ;;
esac
EOF
printf '#!/bin/sh\necho "gemini 0.1.0"\n' > "$B/gemini"
chmod +x "$B"/*

# zeltro with the fakes first on PATH and the throwaway HOME. zp keeps the
# ZELTRO_AI_* profile overrides the caller set; z clears them.
zp() { ( export HOME="$T/home" PATH="$B:/usr/bin:/bin"; unset CODEX_HOME; "$REPO/src/zeltro" "$@" 2>/dev/null ) }
z() { ( unset ZELTRO_AI_AGENT ZELTRO_AI_API_KEY ZELTRO_AI_API_BASE ZELTRO_AI_MODEL ZELTRO_AI_API_KEY_FILE; zp "$@" ) }

echo "capabilities"
caps="$(python3 "$REPO/src/scripts/ai_auth.py" capabilities)"
check "claude: subscription, key, anthropic endpoint" "$(python3 -c 'import json,sys; c=json.loads(sys.argv[1])["agents"]["claude"]; print(c["subscription"], c["api_key"], c["endpoint"])' "$caps")" "True True anthropic"
check "codex endpoint must speak Responses" "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["agents"]["codex"]["endpoint"])' "$caps")" "openai-responses"
check "gemini, qwen, aider: no subscription" "$(python3 -c 'import json,sys; a=json.loads(sys.argv[1])["agents"]; print([a[x]["subscription"] for x in ("gemini","qwen","aider")])' "$caps")" "[False, False, False]"
check "login supported for claude and codex" "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["login_supported"])' "$caps")" "['claude', 'codex']"
check "ai-set --json-output carries them" "$(z ai-set --json-output | python3 -c 'import json,sys; print(json.load(sys.stdin)["agent_auth"]["agents"]["hermes"]["endpoint"])')" "openai"

echo "ai-status"
s="$(z ai-status --agent claude --json-output)"
check "claude installed, version" "$(field "$s" installed) $(field "$s" version)" "True 9.9.9"
check "claude not signed in" "$(field "$s" auth) $(field "$s" signed_in)" "none False"
touch "$T/claude-in"; s="$(z ai-status --agent claude --json)"
check "claude signed in with a subscription" "$(field "$s" auth) $(field "$s" signed_in) $(field "$s" account)" "subscription True u@example.com (pro)"
rm -f "$T/claude-in"
echo "Logged in using an API key - sk-***" > "$T/codex-in"; s="$(z ai-status --agent codex --json-output)"
check "codex with a stored API key" "$(field "$s" auth) $(field "$s" signed_in)" "api_key True"
rm -f "$T/codex-in"
s="$(z ai-status --agent gemini --json-output)"
check "key-only agent, no key: unknown" "$(field "$s" auth) $(field "$s" signed_in)" "unknown False"
s="$(z ai-status --agent aider --json-output)"
check "not installed" "$(field "$s" installed) $(field "$s" auth)" "False none"
s="$( ( export ZELTRO_AI_AGENT=gemini ZELTRO_AI_API_KEY=k; zp ai-status --agent gemini --json-output ) )"
check "profile key counts as signed in" "$(field "$s" auth) $(field "$s" signed_in)" "api_key True"
s="$( ( export ZELTRO_AI_AGENT=claude ZELTRO_AI_API_BASE=http://gw:4000 ZELTRO_AI_API_KEY=; zp ai-status --agent claude --json-output ) )"
check "profile endpoint counts as ready" "$(field "$s" auth) $(field "$s" signed_in)" "endpoint True"
s="$( ( export ZELTRO_AI_AGENT=codex ZELTRO_AI_API_KEY=k; zp ai-status --agent claude --json-output ) )"
check "another agent's profile key doesn't count" "$(field "$s" auth)" "none"
check "unknown agent is an error" "$(z ai-status --agent bogus --json-output | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')" "error"

echo "ai-login: claude, pasted code"
F="$T/in"; mkfifo "$F"
( z ai-login --agent claude --json-output --timeout 20 < "$F" > "$T/out" ; echo "rc=$?" >> "$T/out" ) &
exec 3> "$F"
for _ in $(seq 1 100); do grep -q need_code "$T/out" 2>/dev/null && break; sleep 0.1; done
check "open event with the paste link" "$(sed -n 1p "$T/out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["event"], d["url"])')" "open https://claude.com/cai/oauth/authorize?code=true&state=x"
check "then need_code" "$(sed -n 2p "$T/out")" '{"event": "need_code"}'
echo "WRONG" >&3
for _ in $(seq 1 100); do [ "$(grep -c need_code "$T/out")" -ge 2 ] && break; sleep 0.1; done
check "a wrong code asks again" "$(sed -n 3p "$T/out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["event"], d.get("retry"))')" "need_code True"
echo "GOOD-CODE" >&3
for _ in $(seq 1 100); do grep -q "^rc=" "$T/out" && break; sleep 0.1; done
exec 3>&-
check "done, signed in" "$(sed -n 4p "$T/out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["event"], d["signed_in"], d["account"])')" "done True u@example.com (pro)"
check "exit 0" "$(grep '^rc=' "$T/out")" "rc=0"
check "already signed in: done at once" "$(z ai-login --agent claude --json-output < /dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["event"], d.get("already"))')" "done True"
rm -f "$T/claude-in"

echo "ai-login: claude, local browser"
out="$( ( export FAKE_CALLBACK=1; z ai-login --agent claude --json-output --local-browser --timeout 20 < /dev/null ) )"
check "open event with the localhost-callback link, no need_code" "$(echo "$out" | python3 -c 'import json,sys; e=[json.loads(l) for l in sys.stdin]; print([x["event"] for x in e], "localhost%3A5555" in e[0]["url"])')" "['open', 'done'] True"
rm -f "$T/claude-in"

echo "ai-login: codex device code"
out="$(z ai-login --agent codex --json-output --timeout 20 < /dev/null)"
check "open with URL and code" "$(echo "$out" | sed -n 1p)" '{"event": "open", "url": "https://auth.openai.com/codex/device", "code": "ABCD-12345"}'
check "then done" "$(echo "$out" | sed -n 2p | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["event"], d["auth"])')" "done subscription"
rm -f "$T/codex-in"
check "unsupported agent says so" "$(z ai-login --agent gemini --json-output < /dev/null)" '{"event": "error", "message": "not supported yet"}'
check "missing agent says how to install" "$(z ai-login --agent aider --json-output < /dev/null | python3 -c 'import json,sys; print("ai-install --agent aider" in json.load(sys.stdin)["message"])')" "True"

echo "cancelling a login"
mkfifo "$T/in2"; exec 4<> "$T/in2"
( export HOME="$T/home" PATH="$B:/usr/bin:/bin"; exec python3 "$REPO/src/scripts/ai_auth.py" login --agent claude --json-output --timeout 20 ) < "$T/in2" > "$T/out2" 2>&1 &
P=$!
for _ in $(seq 1 100); do grep -q need_code "$T/out2" 2>/dev/null && break; sleep 0.1; done
kill -TERM "$P"; wait "$P" 2>/dev/null; rc=$?
exec 4>&-
check "exits 130" "$rc" "130"
sleep 0.5
check "its sign-in process is gone" "$(pgrep -f "$B/claude auth login" | wc -l | tr -d ' ')" "0"

# Through `zeltro`, the way the app calls it: the signal goes to the zeltro PID.
( export FAKE_WAIT=30; z ai-login --agent codex --json-output --timeout 60 < /dev/null > "$T/out3" ) &
for _ in $(seq 1 100); do grep -q '"open"' "$T/out3" 2>/dev/null && break; sleep 0.1; done
P="$(pgrep -f "ai_auth.py login --agent codex" | head -1)"
check "zeltro ai-login's PID is the login process" "$(ps -o args= -p "$P" 2>/dev/null | grep -c ai_auth.py)" "1"
kill -TERM "$P"
for _ in $(seq 1 50); do [ "$(pgrep -f "$B/codex login" | wc -l)" -eq 0 ] && break; sleep 0.1; done
check "SIGTERM to it ends codex's sign-in too" "$(pgrep -f "$B/codex login" | wc -l | tr -d ' ')" "0"
wait 2>/dev/null; rm -f "$T/codex-in"

echo "ai-login: claude, a wrong code that Claude rejects"
mkfifo "$T/in4"; exec 5<> "$T/in4"
( export HOME="$T/home" PATH="$B:/usr/bin:/bin"; exec python3 "$REPO/src/scripts/ai_auth.py" login --agent claude --json-output --timeout 20 ) < "$T/in4" > "$T/out4" 2>&1 &
P=$!
for _ in $(seq 1 100); do grep -q need_code "$T/out4" 2>/dev/null && break; sleep 0.1; done
echo "WRONG-400" >&5; wait "$P" 2>/dev/null; exec 5>&-
check "a readable error, no prompt text" "$(tail -1 "$T/out4")" '{"event": "error", "message": "That code wasn'"'"'t accepted. Start the sign-in again and copy the whole code from the sign-in page."}'

echo "profile translation (zeltro_agent_env, aider)"
envrun() { # <agent> <model> <key> <base> <vars...>
    local a="$1" m="$2" k="$3" b="$4"; shift 4
    ( export HOME="$T/home" PATH="$B:$PATH"; cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1
      unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL GEMINI_API_KEY GOOGLE_GEMINI_BASE_URL OPENAI_API_KEY OPENAI_BASE_URL CODEX_HOME
      AI_AGENT="$a" AI_MODEL="$m" AI_API_KEY="$k" AI_API_BASE="$b"
      zeltro_agent_env "$a" > /dev/null 2>&1
      for v in "$@"; do printf '%s=%s ' "$v" "${!v:-}"; done )
}
check "claude endpoint: Anthropic vars, key as bearer token, model everywhere" \
    "$(envrun claude deepseek-v4 dk-123 https://api.deepseek.com/anthropic ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL)" \
    "ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic ANTHROPIC_AUTH_TOKEN=dk-123 ANTHROPIC_API_KEY= ANTHROPIC_MODEL=deepseek-v4 ANTHROPIC_SMALL_FAST_MODEL=deepseek-v4 "
check "claude key, no endpoint: ANTHROPIC_API_KEY" "$(envrun claude "" sk-ant-1 "" ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN)" "ANTHROPIC_API_KEY=sk-ant-1 ANTHROPIC_AUTH_TOKEN= "
check "gemini: key and Gemini-format endpoint" "$(envrun gemini "" g-1 https://gw/gemini GEMINI_API_KEY GOOGLE_GEMINI_BASE_URL)" "GEMINI_API_KEY=g-1 GOOGLE_GEMINI_BASE_URL=https://gw/gemini "
check "qwen: OpenAI vars" "$(envrun qwen "" q-1 https://openrouter.ai/api/v1 OPENAI_API_KEY OPENAI_BASE_URL)" "OPENAI_API_KEY=q-1 OPENAI_BASE_URL=https://openrouter.ai/api/v1 "
cx="$( ( export HOME="$T/home" PATH="$B:$PATH"; cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1; unset CODEX_HOME
        AI_MODEL=m AI_API_KEY=or-1 AI_API_BASE=https://openrouter.ai/api/v1; zeltro_agent_env codex > /dev/null 2>&1
        printf '%s\n' "${ZELTRO_CODEX_BASE_ARGS[@]}"; echo "KEY=$ZELTRO_CODEX_ENDPOINT_KEY HOME=${CODEX_HOME:-unset}" ) )"
check "codex endpoint: its own Responses provider" "$(echo "$cx" | grep -v '^-c$' | tr '\n' ' ')" \
    'model_provider=zeltro model_providers.zeltro.name="Zeltro endpoint" model_providers.zeltro.base_url="https://openrouter.ai/api/v1" model_providers.zeltro.env_key="ZELTRO_CODEX_ENDPOINT_KEY" model_providers.zeltro.wire_api="responses" KEY=or-1 HOME=unset '
aid() { ( cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1; cd "$T"
          AI_MODEL="$1" AI_API_KEY="$2" AI_API_BASE="$3"; build_aider_args
          for i in "${!AIDER_ARGS[@]}"; do case "${AIDER_ARGS[$i]}" in --model|--api-key|--openai-api-base) printf '%s %s ' "${AIDER_ARGS[$i]}" "${AIDER_ARGS[$((i+1))]}" ;; esac; done ) }
check "aider endpoint: openai/<model>, openai= key" "$(aid deepseek/deepseek-v4.1-flash or-1 https://openrouter.ai/api/v1)" "--model openai/deepseek/deepseek-v4.1-flash --api-key openai=or-1 --openai-api-base https://openrouter.ai/api/v1 "
check "aider endpoint, Ollama route kept" "$(aid ollama_chat/qwen3 "" http://localhost:11434)" "--model ollama_chat/qwen3 --api-key openai=zeltro-no-key --openai-api-base http://localhost:11434 "
check "aider without endpoint unchanged" "$(aid anthropic/claude-x sk-ant-1 "")" "--model anthropic/claude-x --api-key anthropic=sk-ant-1 "

echo "not signed in"
sp() { ( export HOME="$T/home" PATH="$B:/usr/bin:/bin"; cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1
         unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN CODEX_HOME
         AI_AGENT="$1" AI_API_KEY="$2" AI_API_BASE=""; zeltro_ai_signin_problem && echo OK ) }
check "codex not signed in: plain message" "$(sp codex "" | sed 's/ on [^.]*\./ on HOST./')" "Codex isn't signed in on HOST. Sign in from the Zeltro app, or run: zeltro ai-login --agent codex"
check "codex with a profile key: fine" "$(sp codex sk-1)" "OK"
check "claude not signed in" "$(sp claude "" | grep -c "Claude Code isn't signed in")" "1"
touch "$T/claude-in"; check "claude signed in: fine" "$(sp claude "")" "OK"; rm -f "$T/claude-in"
check "other agents aren't checked" "$(sp gemini "")" "OK"

echo "npm global install without a password"
NB="$T/npmbin"; mkdir -p "$NB" "$T/sysprefix"; chmod 555 "$T/sysprefix"
printf '#!/bin/sh\n[ "$1 $2" = "prefix -g" ] && { echo "%s"; exit 0; }\necho "npm $*" >> "%s"\n' "$T/sysprefix" "$T/npm.log" > "$NB/npm"
printf '#!/bin/sh\nexit 1\n' > "$NB/sudo"; chmod +x "$NB"/*
( export HOME="$T/home" PATH="$NB:/usr/bin:/bin"; cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1; _npm_install_global @openai/codex > /dev/null 2>&1 )
check "unwritable prefix, no sudo: per-user prefix" "$(cat "$T/npm.log")" "npm install -g --prefix $T/home/.npm-global @openai/codex"
chmod 755 "$T/sysprefix"; rm -f "$T/npm.log"
( export HOME="$T/home" PATH="$NB:/usr/bin:/bin"; cd "$REPO/src" && set +u && source scripts/functions.sh > /dev/null 2>&1; _npm_install_global @openai/codex > /dev/null 2>&1 )
check "writable prefix: plain -g" "$(cat "$T/npm.log")" "npm install -g @openai/codex"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
