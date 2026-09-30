#!/bin/bash
# Unit test for the OpenCode and Hermes argument builders in functions.sh:
# zeltro_opencode_prepare and zeltro_hermes_prepare turn Zeltro's AI_MODEL,
# AI_API_KEY and AI_API_BASE into each CLI's flags and environment. Runs no agent
# and makes no network calls.
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

echo "Language"
out="$( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1; set -e
        AI_LANGUAGE=Spanish; zeltro_ai_language_args hermes; printf '%s' "${HERMES_EPHEMERAL_SYSTEM_PROMPT:-}" )"
echo "$out" | grep -q "Spanish" && ok "hermes: language in HERMES_EPHEMERAL_SYSTEM_PROMPT" || bad "hermes: no language instruction"
out="$( cd "$REPO/src" && set +u && NO_COLOR=1 source scripts/functions.sh >/dev/null 2>&1
        zeltro_ai_language_in_prompt opencode && echo yes || echo no )"
check "opencode: language rides on the prompt" "$out" "yes"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
