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

# Not pre_check.sh: that requires Docker to be up, and this only edits an
# agent's config file. The .env is read just for the default agent.
source scripts/functions.sh
[ -f /etc/zeltro-cli/.env ] && source /etc/zeltro-cli/.env
zeltro_apply_ai_overrides

AGENT=""
ACTION="set"
JSON_OUTPUT="${JSON_OUTPUT:-}"

usage() {
    echo-white "Usage: zeltro ai-unattended [--agent] AGENT [on|off|status] [--json-output]"
    echo-white ""
    echo-white "Control whether an AI agent runs without asking approval for each action."
    echo-white "Changes only that agent's own config file: never Zeltro's .env, the default"
    echo-white "agent, or anything installed."
    echo-white ""
    echo-white "Arguments:"
    echo-white "  AGENT            claude, codex, agy, qwen, aider, opencode, hermes or gemini."
    echo-white "                   Defaults to the currently configured agent."
    echo-white "  on | off         Turn unattended mode on (the default) or off."
    echo-white "  status           Report the current setting without changing it."
    echo-white ""
    echo-white "Options:"
    echo-white "  --revoke         Same as off."
    echo-white "  --status         Same as status."
    echo-white "  --json-output    Machine-readable output: {\"action\": \"ai_unattended\","
    echo-white "                   \"status\", \"agent\", \"unattended\": \"true|false|unknown\","
    echo-white "                   \"config_file\"}; on failure \"error\" is unknown_agent,"
    echo-white "                   no_agent, not_installed, write_failed or not_applied."
    echo-white "  --help           Show this message."
    echo-white ""
    echo-white "The setting is stored in the agent's OWN config file, not in Zeltro's, so"
    echo-white "it can be inspected and undone with that agent's documentation:"
    echo-white "  claude → ~/.claude/settings.json      codex → ~/.codex/config.toml"
    echo-white "  gemini → ~/.gemini/settings.json      qwen  → ~/.qwen/settings.json"
    echo-white "  aider  → ~/.aider.conf.yml             opencode → ~/.config/opencode/opencode.json"
    echo-white "  hermes → ~/.hermes/config.yaml (approvals.mode)"
    echo-white "  agy    → ~/.gemini/antigravity-cli/settings.json (toolPermission)"
}

# Error out with a code the app can branch on. $1 code, $2 message.
fail() {
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c 'import json,sys; print(json.dumps({"action": "ai_unattended", "status": "error", "agent": sys.argv[1], "error": sys.argv[2], "message": sys.argv[3]}))' "$AGENT" "$1" "$2"
    else
        echo-red "$2"
    fi
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)       [ $# -ge 2 ] || fail usage "--agent needs a value."; AGENT="$2"; shift 2 ;;
        on|--on)       ACTION="set"; shift ;;
        off|--off|--revoke) ACTION="revoke"; shift ;;
        status|--status) ACTION="status"; shift ;;
        --json-output) JSON_OUTPUT=1; export JSON_OUTPUT; shift ;;
        --no-colors)   NO_COLOR=1; export NO_COLOR; shift ;;
        --help|-h)     usage; exit 0 ;;
        -*)            fail usage "Unknown option: $1" ;;
        *)
            if [ -z "$AGENT" ]; then AGENT="$1"; else fail usage "Too many arguments: $1"; fi
            shift ;;
    esac
done

# Default to whatever agent Zeltro is configured to use.
if [ -z "$AGENT" ]; then
    AGENT="${AI_AGENT:-}"
fi
[ -n "$AGENT" ] || fail no_agent "No agent specified and none is configured. Pass --agent, or run 'zeltro ai-set' first."

case "$AGENT" in
    claude|codex|gemini|qwen|aider|opencode|hermes|agy) ;;
    *) fail unknown_agent "Unknown agent '$AGENT'. Expected claude, codex, agy, qwen, aider, opencode, hermes or gemini." ;;
esac

CFG="$(zeltro_agent_config_path "$AGENT")"

report() { # $1 state
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        echo "{\"action\": \"ai_unattended\", \"status\": \"success\", \"agent\": \"$AGENT\", \"unattended\": \"$1\", \"config_file\": \"$CFG\"}"
    fi
}

if [ "$ACTION" = "status" ]; then
    STATE=$(zeltro_read_agent_autonomy "$AGENT")
    report "$STATE"
    if [[ "$JSON_OUTPUT" != "1" ]]; then
        case "$STATE" in
            true)    echo-yellow "$AGENT runs unattended (no approval prompts)." ;;
            false)   echo-green  "$AGENT asks for approval before acting." ;;
            *)       echo-yellow "$AGENT: cannot tell — $CFG is missing or unreadable." ;;
        esac
        echo-white "  $CFG"
    fi
    cd "$ORIG_DIR"
    exit 0
fi

# Only for an installed agent: writing ~/.codex/config.toml for a Codex that
# isn't here would report "on" for an agent that can't run. Install first
# (zeltro ai-install --agent A), then turn it on.
zeltro_agent_installed "$AGENT" || fail not_installed "$AGENT is not installed. Install it with: zeltro ai-install --agent $AGENT"

# Deliberately no confirmation prompt here. Running this command IS the
# explicit request; the interactive consent flow lives in ai-set, where the
# user has not necessarily asked for it yet. The writers' messages are for
# humans, so in JSON mode they go to stderr.
if [ "$ACTION" = "set" ]; then want=true; writer=zeltro_allow_agent_autonomy; else want=false; writer=zeltro_revoke_agent_autonomy; fi
if [[ "$JSON_OUTPUT" == "1" ]]; then
    errf=$(mktemp)
    if ! JSON_OUTPUT= NO_COLOR=1 "$writer" "$AGENT" >"$errf" 2>&1; then
        msg=$(tr '\n' ' ' < "$errf" | sed 's/[[:space:]]*$//'); rm -f "$errf"
        fail write_failed "Couldn't change $AGENT's setting in $CFG. ${msg}"
    fi
    cat "$errf" >&2; rm -f "$errf"
else
    "$writer" "$AGENT" || fail write_failed "Couldn't change $AGENT's setting in $CFG."
fi

# Read it back: the writer returning 0 isn't proof the agent will see it.
STATE=$(zeltro_read_agent_autonomy "$AGENT")
if [ "$STATE" != "$want" ] && [ "$STATE" != "unknown" ]; then
    fail not_applied "$AGENT's setting still reads '$STATE' after the change. Check $CFG."
fi
report "$STATE"

cd "$ORIG_DIR"
