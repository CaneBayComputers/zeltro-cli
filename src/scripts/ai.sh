#!/bin/bash

set -e

CALLER_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

DEV_DIR=$(pwd)

# Run standard pre-checks (loads /etc/zeltro-cli/.env, validates projects dir, etc.)
source scripts/pre_check.sh

SCRIPT_DIR="$DEV_DIR/scripts"

# Run the AI agent from the original directory (project root), not the CLI repo
cd "$CALLER_DIR"

usage() {
    echo-white "Usage: zeltro ai [--interactive] \"<prompt>\""
    echo-white ""
    echo-white "Send a one-off prompt to your configured AI agent and exit."
    echo-white "Durable project context lives in the project's AGENTS.md, so each"
    echo-white "prompt can stand alone — the agent reads that file to pick the"
    echo-white "project up cold."
    echo-white ""
    echo-white "Options:"
    echo-white "  --interactive, -i  Open a persistent interactive session instead"
    echo-white "  --one-off          Accepted for compatibility (now the default)"
    echo-white ""
    echo-white "Must be run from a Zeltro project directory."
}

# One-off is the DEFAULT. --interactive opts back into a persistent session;
# --one-off is still accepted so existing scripts and callers keep working.
ONE_OFF=1
PROMPT_ARGS=()
# `--` ends Zeltro's option parsing. Note it does not make a dash-leading
# prompt work end to end: the prompt is passed to the agent CLI as an
# argument, and that CLI parses the leading dash as its own flag. The latch
# is here so Zeltro does not reject such a prompt itself.
END_OF_OPTS=0
for arg in "$@"; do
    if [[ "$END_OF_OPTS" == "0" ]]; then
        case "$arg" in
            --)
                END_OF_OPTS=1
                continue
                ;;
            --one-off)
                ONE_OFF=1
                continue
                ;;
            --interactive|-i)
                ONE_OFF=0
                continue
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                # Unknown flags used to be appended to the prompt, so a typo
                # silently changed what the agent was asked, and a newer flag on
                # an older CLI became part of the request instead of an error.
                echo-red "Unknown option: $arg"
                echo-white "Use '$ZELTRO_CMD --help' for the option list."
                exit 1
                ;;
        esac
    fi
    PROMPT_ARGS+=("$arg")
done

INIT_PROMPT="${PROMPT_ARGS[*]}"

# An initial prompt is required — no interactive prompt.
if [[ -z "$INIT_PROMPT" ]]; then
    echo-red "No initial prompt provided."
    echo-white "Usage: zeltro ai [--interactive] \"<prompt>\""
    cd "$CALLER_DIR"
    exit 1
fi

AI_AGENT_CLI_NAME="$AI_AGENT"

if ! _ai_problem=$(zeltro_ai_agent_problem); then
    echo-red "$_ai_problem" >&2
    cd "$CALLER_DIR"
    exit 1
fi

# Zeltro no longer forces each agent's approval prompts off. Disabling another
# tool's safety mechanism on someone's machine is a decision for the user, not
# for us, so it is asked once at install time and recorded in the agent's own
# config file (see zeltro_offer_agent_autonomy). The user can inspect and revoke
# it there using the agent's own documentation.
#
# ZELTRO_AI_AUTO_APPROVE=1 re-adds the flags per invocation. It exists for
# throwaway containers and CI, where writing to a home-directory config is
# pointless, and so anyone depending on the old behaviour has a way back.
AUTO_APPROVE="${ZELTRO_AI_AUTO_APPROVE:-0}"

# ZELTRO_AI_LANGUAGE: a system-level instruction where the agent has one (see
# zeltro_ai_language_args). Gemini has none, so it rides on the prompt.
zeltro_ai_language_args "$AI_AGENT_CLI_NAME"
if [[ "$AI_AGENT_CLI_NAME" == "gemini" && -n "${AI_LANGUAGE:-}" ]]; then
    INIT_PROMPT="$(zeltro_ai_language_instruction)

$INIT_PROMPT"
fi

case "$AI_AGENT_CLI_NAME" in
    codex)
        codex_args=()
        if [[ -n "$AI_MODEL" ]]; then
            codex_args+=("--model" "$AI_MODEL")
        fi
        _export_agent_key OPENAI_API_KEY "sk-"
        _export_agent_base OPENAI_BASE_URL
        [[ "$AUTO_APPROVE" == "1" ]] && codex_args+=(--dangerously-bypass-approvals-and-sandbox)
        codex_args+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        if [[ "$ONE_OFF" == "1" ]]; then
            codex exec "${codex_args[@]}" "$INIT_PROMPT"
        else
            codex "${codex_args[@]}" "$INIT_PROMPT"
        fi
        ;;
    claude)
        claude_args=()
        [[ "$AUTO_APPROVE" == "1" ]] && claude_args+=(--dangerously-skip-permissions)
        if [[ "$ONE_OFF" == "1" ]]; then
            claude_args+=(-p)
        fi
        if [[ -n "$AI_MODEL" ]]; then
            claude_args+=("--model" "$AI_MODEL")
        fi
        _export_agent_key ANTHROPIC_API_KEY "sk-ant-"
        _export_agent_base ANTHROPIC_BASE_URL
        claude_args+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        claude_args+=("$INIT_PROMPT")
        claude "${claude_args[@]}"
        ;;
    qwen)
        # Qwen Code is a fork of Gemini CLI, so the invocation mirrors it. It is
        # OpenAI-compatible by design and reads OPENAI_API_KEY / OPENAI_BASE_URL,
        # which is why it pairs well with `--api-base` pointed at OpenRouter,
        # DeepInfra or a local Ollama.
        _export_agent_key OPENAI_API_KEY ""
        _export_agent_base OPENAI_BASE_URL
        # --auth-type is required: without it qwen refuses non-interactive runs
        # with "No auth type is selected", even when the key and endpoint are set.
        # The yolo warning is printed on every headless run and would land in the
        # middle of `zeltro create`'s JSON reply, so it is suppressed rather than
        # left to corrupt the classifier.
        export QWEN_CODE_SUPPRESS_YOLO_WARNING=1
        # --auth-type is required for headless runs and is not a safety setting,
        # so it stays unconditional; --yolo is the approval bypass and is gated.
        qwen_args=(--auth-type openai)
        [[ "$AUTO_APPROVE" == "1" ]] && qwen_args+=(--yolo)
        qwen_args+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        if [[ -n "$AI_MODEL" ]]; then
            qwen_args+=("--model" "$AI_MODEL")
        fi
        if [[ "$ONE_OFF" == "1" ]]; then
            qwen_args+=(--prompt "$INIT_PROMPT")
        else
            qwen_args+=("-i" "$INIT_PROMPT")
        fi
        qwen "${qwen_args[@]}"
        ;;
    gemini)
        # Both --yolo (action approval) and --skip-trust (directory trust) are
        # safety prompts, so both are gated rather than only the obvious one.
        gemini_args=()
        [[ "$AUTO_APPROVE" == "1" ]] && gemini_args+=(--yolo --skip-trust)
        if [[ -n "$AI_MODEL" ]]; then
            gemini_args+=("--model" "$AI_MODEL")
        fi
        # Add projects directory to workspace so gemini's file tools can reach it
        if [[ -n "$PROJECTS_DIR_PATH" ]]; then
            gemini_args+=(--include-directories "$PROJECTS_DIR_PATH")
        fi
        if [[ "$ONE_OFF" == "1" ]]; then
            # --output-format text suppresses the xterm.js TUI dump in headless mode
            gemini_args+=(--output-format text --prompt "$INIT_PROMPT")
        else
            gemini_args+=("-i" "$INIT_PROMPT")
        fi
        gemini "${gemini_args[@]}"
        ;;
    aider)
        build_aider_args
        AIDER_ARGS+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        if [[ "$ONE_OFF" == "1" ]]; then
            aider "${AIDER_ARGS[@]}" --message "$INIT_PROMPT"
        else
            write_aider_seed_file "$INIT_PROMPT"
            aider "${AIDER_ARGS[@]}" --load "$AIDER_SEED_FILE"
            rm -f "$AIDER_SEED_FILE"
        fi
        ;;
    *)
        echo-red "Unsupported AI agent: '$AI_AGENT_CLI_NAME'."
        echo-white "Supported agents: codex, claude, gemini, aider"
        echo-white "Run 'zeltro ai-set' to choose a supported agent."
        exit 1
        ;;
esac

cd "$CALLER_DIR"
