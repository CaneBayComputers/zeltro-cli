#!/bin/bash

# Toggle (or report) whether an AI agent may run without approval prompts.
#
# Exists alongside `ai-set --allow-unattended` for a reason the GUI raised:
# re-running `ai-set` can trigger a package install, and flipping a checkbox in a
# settings panel should never risk installing software as a side effect. This
# command touches nothing but the agent's own config file.

set -e

ORIG_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

DEV_DIR=$(pwd)

source scripts/pre_check.sh

AGENT=""
ACTION="set"
JSON_OUTPUT="${JSON_OUTPUT:-}"

usage() {
    echo-white "Usage: zeltro ai-unattended [AGENT] [--revoke] [--status] [--json-output]"
    echo-white ""
    echo-white "Control whether an AI agent runs without asking approval for each action."
    echo-white ""
    echo-white "Arguments:"
    echo-white "  AGENT            claude, codex, gemini, qwen, aider, opencode or hermes."
    echo-white "                   Defaults to the currently configured agent."
    echo-white ""
    echo-white "Options:"
    echo-white "  --revoke         Turn unattended mode off again."
    echo-white "  --status         Report the current setting without changing it."
    echo-white "  --json-output    Machine-readable output."
    echo-white "  --help           Show this message."
    echo-white ""
    echo-white "The setting is stored in the agent's OWN config file, not in Zeltro's, so"
    echo-white "it can be inspected and undone with that agent's documentation:"
    echo-white "  claude → ~/.claude/settings.json      codex → ~/.codex/config.toml"
    echo-white "  gemini → ~/.gemini/settings.json      qwen  → ~/.qwen/settings.json"
    echo-white "  aider  → ~/.aider.conf.yml             opencode → ~/.config/opencode/opencode.json"
    echo-white "  hermes → ~/.hermes/config.yaml (approvals.mode)"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --revoke)      ACTION="revoke"; shift ;;
        --status)      ACTION="status"; shift ;;
        --json-output) JSON_OUTPUT=1; export JSON_OUTPUT; shift ;;
        --no-colors)   NO_COLOR=1; export NO_COLOR; shift ;;
        --help|-h)     usage; exit 0 ;;
        -*)            error "Unknown option: $1" ;;
        *)
            if [ -z "$AGENT" ]; then AGENT="$1"; else error "Too many arguments"; fi
            shift ;;
    esac
done

# Default to whatever agent Zeltro is configured to use.
if [ -z "$AGENT" ]; then
    AGENT="${AI_AGENT:-}"
fi

if [ -z "$AGENT" ]; then
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        json_error "No agent specified and none configured. Run 'zeltro ai-set' first."
    fi
    error "No agent specified and none is configured. Run 'zeltro ai-set' first."
fi

case "$AGENT" in
    claude|codex|gemini|qwen|aider|opencode|hermes) ;;
    *)
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            json_error "Unknown agent '$AGENT'. Expected claude, codex, gemini, qwen, aider, opencode or hermes."
        fi
        error "Unknown agent '$AGENT'. Expected claude, codex, gemini, qwen, aider, opencode or hermes." ;;
esac

CFG="$(zeltro_agent_config_path "$AGENT")"

case "$ACTION" in
    status)
        STATE=$(zeltro_read_agent_autonomy "$AGENT")
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            echo "{\"action\": \"ai_unattended\", \"status\": \"success\", \"agent\": \"$AGENT\", \"unattended\": \"$STATE\", \"config_file\": \"$CFG\"}"
        else
            case "$STATE" in
                true)    echo-yellow "$AGENT runs unattended (no approval prompts)." ;;
                false)   echo-green  "$AGENT asks for approval before acting." ;;
                *)       echo-yellow "$AGENT: cannot tell — $CFG is missing or unreadable." ;;
            esac
            echo-white "  $CFG"
        fi
        ;;

    set)
        # Deliberately no confirmation prompt here. Running this command IS the
        # explicit request; the interactive consent flow lives in ai-set, where
        # the user has not necessarily asked for it yet.
        zeltro_allow_agent_autonomy "$AGENT"
        STATE=$(zeltro_read_agent_autonomy "$AGENT")
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            echo "{\"action\": \"ai_unattended\", \"status\": \"success\", \"agent\": \"$AGENT\", \"unattended\": \"$STATE\", \"config_file\": \"$CFG\"}"
        fi
        ;;

    revoke)
        zeltro_revoke_agent_autonomy "$AGENT"
        STATE=$(zeltro_read_agent_autonomy "$AGENT")
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            echo "{\"action\": \"ai_unattended\", \"status\": \"success\", \"agent\": \"$AGENT\", \"unattended\": \"$STATE\", \"config_file\": \"$CFG\"}"
        fi
        ;;
esac

cd "$ORIG_DIR"
