#!/bin/bash
# Unit test for the OpenCode, Hermes and Cline argument builders in functions.sh:
# zeltro_opencode_prepare, zeltro_hermes_prepare and zeltro_cline_prepare turn
# Zeltro's AI_MODEL, AI_API_KEY and AI_API_BASE into each CLI's flags, environment
# and (Cline) provider settings. Runs no agent and makes no network calls.
#
#   bash tests/agent-args.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { # <description> <actual> <expected>
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi
}

# Runs <function> with the given AI_* values in a clean subshell (set -e on, like
# the launchers) and prints: the args joined by |, then the named env variables.
run() { # <function> <model> <key> <base> <array> [env var ...]
    local fn="$1" model="$2" key="$3" base="$4" arr="$5"; shift 5
    ( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1
      unset OPENAI_API_KEY OPENAI_BASE_URL ANTHROPIC_API_KEY OPENROUTER_API_KEY GEMINI_API_KEY \
            GOOGLE_GENERATIVE_AI_API_KEY OPENCODE_CONFIG_CONTENT ZELTRO_AI_API_KEY
      set -e
      AI_MODEL="$model" AI_API_KEY="$key" AI_API_BASE="$base"
      "$fn"
      eval "for a in \${${arr}[@]+\"\${${arr}[@]}\"}; do printf '%s|' \"\$a\"; done"; echo
      for v in "$@"; do printf '%s=%s\n' "$v" "${!v:-}"; done )
}

echo "OpenCode"
out="$(run zeltro_opencode_prepare openai/gpt-5.4-mini sk-test "" ZELTRO_OPENCODE_ARGS OPENAI_API_KEY OPENCODE_DISABLE_AUTOUPDATE)"
check "openai model passed as -m" "$(echo "$out" | sed -n 1p)" "-m|openai/gpt-5.4-mini|"
check "key goes to OPENAI_API_KEY" "$(echo "$out" | grep '^OPENAI_API_KEY=')" "OPENAI_API_KEY=sk-test"
check "auto-update off" "$(echo "$out" | grep '^OPENCODE_DISABLE_AUTOUPDATE=')" "OPENCODE_DISABLE_AUTOUPDATE=1"
out="$(run zeltro_opencode_prepare anthropic/claude-sonnet-5-5 sk-ant-x "" ZELTRO_OPENCODE_ARGS ANTHROPIC_API_KEY OPENAI_API_KEY)"
check "anthropic key goes to ANTHROPIC_API_KEY" "$(echo "$out" | grep '^ANTHROPIC_API_KEY=')" "ANTHROPIC_API_KEY=sk-ant-x"
check "and not to OPENAI_API_KEY" "$(echo "$out" | grep '^OPENAI_API_KEY=')" "OPENAI_API_KEY="
out="$(run zeltro_opencode_prepare openrouter/qwen/qwen3-coder sk-or-x "" ZELTRO_OPENCODE_ARGS OPENROUTER_API_KEY)"
check "openrouter key goes to OPENROUTER_API_KEY" "$(echo "$out" | grep '^OPENROUTER_API_KEY=')" "OPENROUTER_API_KEY=sk-or-x"
out="$(run zeltro_opencode_prepare "" "" "" ZELTRO_OPENCODE_ARGS)"
check "no model: no flags (OpenCode's own default)" "$(echo "$out" | sed -n 1p)" ""
out="$(run zeltro_opencode_prepare qwen3-coder:30b ollama http://localhost:11434/v1 ZELTRO_OPENCODE_ARGS OPENCODE_CONFIG_CONTENT ZELTRO_AI_API_KEY)"
check "endpoint: model is zeltro/<model>" "$(echo "$out" | sed -n 1p)" "-m|zeltro/qwen3-coder:30b|"
check "endpoint: key in ZELTRO_AI_API_KEY" "$(echo "$out" | grep '^ZELTRO_AI_API_KEY=')" "ZELTRO_AI_API_KEY=ollama"
cfg="$(echo "$out" | grep '^OPENCODE_CONFIG_CONTENT=' | cut -d= -f2-)"
check "endpoint: inline provider config" "$(python3 -c 'import json,sys; p=json.loads(sys.argv[1])["provider"]["zeltro"]; print(p["npm"], p["options"]["baseURL"], p["options"]["apiKey"], list(p["models"]))' "$cfg")" \
    "@ai-sdk/openai-compatible http://localhost:11434/v1 {env:ZELTRO_AI_API_KEY} ['qwen3-coder:30b']"
out="$(run zeltro_opencode_prepare qwen3-coder:30b "" http://localhost:11434/v1 ZELTRO_OPENCODE_ARGS ZELTRO_AI_API_KEY)"
check "endpoint without a key: placeholder key" "$(echo "$out" | grep '^ZELTRO_AI_API_KEY=')" "ZELTRO_AI_API_KEY=zeltro-no-key"

echo "Hermes"
out="$(run zeltro_hermes_prepare openai/gpt-5.4-mini sk-test "" ZELTRO_HERMES_ARGS OPENAI_API_KEY OPENAI_BASE_URL)"
check "openai/ prefix becomes --provider openai" "$(echo "$out" | sed -n 1p)" "--provider|openai|-m|gpt-5.4-mini|"
check "key goes to OPENAI_API_KEY" "$(echo "$out" | grep '^OPENAI_API_KEY=')" "OPENAI_API_KEY=sk-test"
check "no endpoint set" "$(echo "$out" | grep '^OPENAI_BASE_URL=')" "OPENAI_BASE_URL="
out="$(run zeltro_hermes_prepare openrouter/qwen/qwen3-coder sk-or-x "" ZELTRO_HERMES_ARGS OPENROUTER_API_KEY)"
check "openrouter/ prefix keeps the rest as the model" "$(echo "$out" | sed -n 1p)" "--provider|openrouter|-m|qwen/qwen3-coder|"
check "openrouter key goes to OPENROUTER_API_KEY" "$(echo "$out" | grep '^OPENROUTER_API_KEY=')" "OPENROUTER_API_KEY=sk-or-x"
out="$(run zeltro_hermes_prepare anthropic/claude-sonnet-5-5 sk-ant-x "" ZELTRO_HERMES_ARGS ANTHROPIC_API_KEY)"
check "anthropic/ prefix" "$(echo "$out" | sed -n 1p)" "--provider|anthropic|-m|claude-sonnet-5-5|"
check "anthropic key" "$(echo "$out" | grep '^ANTHROPIC_API_KEY=')" "ANTHROPIC_API_KEY=sk-ant-x"
out="$(run zeltro_hermes_prepare qwen/qwen3-coder "" "" ZELTRO_HERMES_ARGS)"
check "unknown prefix: model as-is, Hermes's own provider" "$(echo "$out" | sed -n 1p)" "-m|qwen/qwen3-coder|"
out="$(run zeltro_hermes_prepare qwen3-coder:30b "" http://localhost:11434/v1 ZELTRO_HERMES_ARGS OPENAI_BASE_URL OPENAI_API_KEY)"
check "endpoint: --provider openai and the model" "$(echo "$out" | sed -n 1p)" "--provider|openai|-m|qwen3-coder:30b|"
check "endpoint: OPENAI_BASE_URL" "$(echo "$out" | grep '^OPENAI_BASE_URL=')" "OPENAI_BASE_URL=http://localhost:11434/v1"
check "endpoint without a key: placeholder key" "$(echo "$out" | grep '^OPENAI_API_KEY=')" "OPENAI_API_KEY=zeltro-no-key"

echo "Cline"
CT="$(mktemp -d)"; trap 'rm -rf "$CT"' EXIT
export CLINE_PROVIDER_SETTINGS_PATH="$CT/providers.json"
# <description> <jq-ish python expr over the saved file> <expected>
saved() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$CLINE_PROVIDER_SETTINGS_PATH" "$1" 2>/dev/null; }
out="$(run zeltro_cline_prepare "" "" "" ZELTRO_CLINE_ARGS)"
check "no key, no endpoint: Cline's own sign-in, no flags" "$(echo "$out" | sed -n 1p)" ""
check "  ...and nothing saved" "$([ -e "$CLINE_PROVIDER_SETTINGS_PATH" ] && echo saved || echo none)" "none"
out="$(run zeltro_cline_prepare some-model "" "" ZELTRO_CLINE_ARGS)"
check "no key: the model goes to Cline as-is" "$(echo "$out" | sed -n 1p)" "-m|some-model|"
out="$(run zeltro_cline_prepare anthropic/claude-sonnet-5-5 sk-ant-x "" ZELTRO_CLINE_ARGS)"
check "key: anthropic/ prefix picks Anthropic" "$(echo "$out" | sed -n 1p)" "-P|anthropic|-m|claude-sonnet-5-5|"
check "  ...key saved for that provider" "$(saved 'd["providers"]["anthropic"]["settings"]["apiKey"]')" "sk-ant-x"
check "  ...file is mode 600" "$(stat -c %a "$CLINE_PROVIDER_SETTINGS_PATH")" "600"
out="$(run zeltro_cline_prepare openrouter/qwen/qwen3-coder sk-or-x "" ZELTRO_CLINE_ARGS)"
check "key: openrouter/ prefix picks OpenRouter" "$(echo "$out" | sed -n 1p)" "-P|openrouter|-m|qwen/qwen3-coder|"
check "  ...the Anthropic entry is kept" "$(saved 'd["providers"]["anthropic"]["settings"]["apiKey"]')" "sk-ant-x"
check "  ...lastUsedProvider follows" "$(saved 'd["lastUsedProvider"]')" "openrouter"
out="$(run zeltro_cline_prepare gpt-5.4-mini sk-x "" ZELTRO_CLINE_ARGS)"
check "key, no prefix: OpenAI" "$(echo "$out" | sed -n 1p)" "-P|openai-native|-m|gpt-5.4-mini|"
out="$(run zeltro_cline_prepare openai/gpt-5.4-mini sk-x "" ZELTRO_CLINE_ARGS)"
check "key: openai/ prefix is stripped" "$(echo "$out" | sed -n 1p)" "-P|openai-native|-m|gpt-5.4-mini|"
out="$(run zeltro_cline_prepare qwen3-coder:30b "" http://localhost:11434/v1 ZELTRO_CLINE_ARGS)"
check "endpoint: OpenAI-compatible" "$(echo "$out" | sed -n 1p)" "-P|openai-compatible|-m|qwen3-coder:30b|"
check "  ...base URL saved" "$(saved 'd["providers"]["openai-compatible"]["settings"]["baseUrl"]')" "http://localhost:11434/v1"
check "  ...placeholder key without one" "$(saved 'd["providers"]["openai-compatible"]["settings"]["apiKey"]')" "zeltro-no-key"
out="$(run zeltro_cline_prepare deepseek/deepseek-v4.1-flash sk-or-y https://openrouter.ai/api/v1 ZELTRO_CLINE_ARGS)"
check "endpoint openrouter.ai: Cline's OpenRouter provider" "$(echo "$out" | sed -n 1p)" "-P|openrouter|-m|deepseek/deepseek-v4.1-flash|"
check "  ...no base URL stored for it" "$(saved 'd["providers"]["openrouter"]["settings"].get("baseUrl","")')" ""
out="$(run zeltro_cline_prepare claude-haiku-5-5 zk-1 https://example.test/api/v1/starter/anthropic ZELTRO_CLINE_ARGS)"
check "endpoint ending /anthropic: Anthropic provider" "$(echo "$out" | sed -n 1p)" "-P|anthropic|-m|claude-haiku-5-5|"
check "  ...with /v1 added" "$(saved 'd["providers"]["anthropic"]["settings"]["baseUrl"]')" "https://example.test/api/v1/starter/anthropic/v1"
out="$(run zeltro_cline_prepare anthropic/claude-sonnet-5-5 sk-ant-x "" ZELTRO_CLINE_ARGS)"
check "  ...a later plain-key Anthropic run drops that base URL" "$(saved 'd["providers"]["anthropic"]["settings"].get("baseUrl","")')" ""
echo 'not json {' > "$CLINE_PROVIDER_SETTINGS_PATH"
run zeltro_cline_prepare anthropic/x sk-1 "" ZELTRO_CLINE_ARGS >/dev/null 2>&1
check "an unparseable providers.json is left alone" "$(cat "$CLINE_PROVIDER_SETTINGS_PATH")" "not json {"
unset CLINE_PROVIDER_SETTINGS_PATH

echo "Language"
out="$( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1; set -e
        AI_LANGUAGE=Spanish; zeltro_ai_system_args hermes; printf '%s' "${HERMES_EPHEMERAL_SYSTEM_PROMPT:-}" )"
echo "$out" | grep -q "Spanish" && ok "hermes: language in HERMES_EPHEMERAL_SYSTEM_PROMPT" || bad "hermes: no language instruction"
out="$( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1
        zeltro_ai_system_in_prompt opencode && echo yes || echo no )"
check "opencode: language rides on the prompt" "$out" "yes"
out="$( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1
        zeltro_ai_system_in_prompt cline && echo yes || echo no )"
check "cline: language rides on the prompt (--system would replace Cline's own)" "$out" "yes"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
