#!/bin/bash

set -e

CALLER_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

DEV_DIR=$(pwd)

source scripts/pre_check.sh

SCRIPT_DIR="$DEV_DIR/scripts"

usage() {
    echo-white "Usage: ${ZELTRO_CMD:-$0} <project>"
    echo-white ""
    echo-white "Reopen the AI session for a project, in that project's directory."
    echo-white "Resumes the previous conversation where the agent supports it,"
    echo-white "otherwise starts a fresh one."
    echo-white ""
    echo-white "Options:"
    echo-white "  --help, -h   Show this help message"
}

case "$1" in
    --help|-h)
        usage
        exit 0
        ;;
esac

# A project name is required — no interactive picker.
if [[ -z "$1" ]]; then
    echo-red "No project specified."
    echo-white "Usage: zeltro resume <project>"
    exit 1
fi
PROJECT_NAME="$1"

PROJECT_DIR="$PROJECTS_DIR_PATH/$PROJECT_NAME"

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo-red "Project directory not found: $PROJECT_DIR"
    exit 1
fi

# Start the project — but only if it is not already up.
#
# resume is "continue my AI conversation", not "restart my project". Calling
# startup here unconditionally cost seconds, could prompt for sudo to change
# nothing, and ran the connectivity checks TWICE, because startup.sh ends with
# its own status.sh call and resume runs one immediately below. On a running
# project that is all waste.
if docker container inspect -f '{{.State.Running}}' "$PROJECT_NAME" 2>/dev/null | grep -q true; then
    echo-cyan "$PROJECT_NAME is already running — continuing the session."
else
    echo-cyan "Starting $PROJECT_NAME..."
    (cd "$PROJECTS_DIR_PATH" && "$SCRIPT_DIR/startup.sh" "$PROJECT_NAME")
fi

echo-return

# Show status
(cd "$PROJECTS_DIR_PATH" && "$SCRIPT_DIR/status.sh" "$PROJECT_NAME")

echo-return
echo-cyan "============================================"
echo-cyan "  Project : $PROJECT_NAME"
echo-cyan "  URL     : $(zeltro_project_url "$PROJECT_NAME" || true)/"
echo-cyan "============================================"
echo-return
echo-white "Ctrl+click (or right-click) the URL above to open it in your browser."
echo-white "The AI will resume the last session for this project."
echo-return

# Resume the AI session from the project directory
cd "$PROJECT_DIR"

# No AI chosen yet: run on the free starter credit (see zeltro sandbox).
zeltro_sandbox_autoclaim
AI_AGENT_CLI_NAME="$AI_AGENT"

if ! _ai_problem=$(zeltro_ai_agent_problem); then
    echo-red "$_ai_problem" >&2
    exit 1
fi

notify_resume_fallback() {
    echo-return
    echo-yellow "Could not resume previous session. Starting a new session..."
    echo-return
}

# ZELTRO_AI_LANGUAGE rides on each agent's system-level flag, which applies to
# the resumed session too. Gemini and OpenCode have none and a resume has no
# prompt to carry it, so a resumed session of theirs gets no language instruction.
zeltro_ai_language_args "$AI_AGENT_CLI_NAME"
# In a session the Zeltro app started, report turn ends to it (no-op otherwise).
zeltro_gui_hook_args "$AI_AGENT_CLI_NAME"

# Approval bypass follows the same rule as `zeltro ai`: whether an agent may act
# without asking is the user's choice, recorded in the agent's own config
# (`zeltro ai-unattended`). ZELTRO_AI_AUTO_APPROVE=1 adds the bypass flags for one
# run. Resume used to force them on every time, so a resumed session could skip
# approvals the user never agreed to skip.
AUTO_APPROVE="${ZELTRO_AI_AUTO_APPROVE:-0}"

case "$AI_AGENT_CLI_NAME" in
    codex)
        common_args=()
        if [[ -n "$AI_MODEL" ]]; then
            common_args+=("--model" "$AI_MODEL")
        fi
        _export_agent_key OPENAI_API_KEY "sk-"
        _export_agent_base OPENAI_BASE_URL
        zeltro_codex_base_args
        common_args+=(${ZELTRO_CODEX_BASE_ARGS[@]+"${ZELTRO_CODEX_BASE_ARGS[@]}"})
        [[ "$AUTO_APPROVE" == "1" ]] && common_args+=(--dangerously-bypass-approvals-and-sandbox)
        common_args+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        common_args+=(${ZELTRO_GUI_HOOK_ARGS[@]+"${ZELTRO_GUI_HOOK_ARGS[@]}"})
        if ! codex resume --last "${common_args[@]}"; then
            notify_resume_fallback
            exec codex "${common_args[@]}"
        fi
        ;;
    claude)
        common_args=()
        [[ "$AUTO_APPROVE" == "1" ]] && common_args+=(--dangerously-skip-permissions)
        if [[ -n "$AI_MODEL" ]]; then
            common_args+=("--model" "$AI_MODEL")
        fi
        _export_agent_key ANTHROPIC_API_KEY "sk-ant-"
        _export_agent_base ANTHROPIC_BASE_URL
        common_args+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        common_args+=(${ZELTRO_GUI_HOOK_ARGS[@]+"${ZELTRO_GUI_HOOK_ARGS[@]}"})
        if ! claude --continue "${common_args[@]}"; then
            notify_resume_fallback
            exec claude "${common_args[@]}"
        fi
        ;;
    qwen)
        _export_agent_key OPENAI_API_KEY ""
        _export_agent_base OPENAI_BASE_URL
        export QWEN_CODE_SUPPRESS_YOLO_WARNING=1
        # --auth-type is required for headless runs; --yolo is the approval bypass.
        common_args=(--auth-type openai)
        [[ "$AUTO_APPROVE" == "1" ]] && common_args+=(--yolo)
        common_args+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        if [[ -n "$AI_MODEL" ]]; then
            common_args+=("--model" "$AI_MODEL")
        fi
        # `--continue` resumes the most recent session. NOT `--resume latest`:
        # qwen's --resume takes a session ID/title, so "latest" is looked up as a
        # literal title and reports "No saved session found".
        if ! qwen --continue "${common_args[@]}"; then
            notify_resume_fallback
            exec qwen "${common_args[@]}"
        fi
        ;;
    gemini)
        common_args=()
        [[ "$AUTO_APPROVE" == "1" ]] && common_args+=(--yolo --skip-trust)
        if [[ -n "$AI_MODEL" ]]; then
            common_args+=("--model" "$AI_MODEL")
        fi
        if [[ -n "$PROJECTS_DIR_PATH" ]]; then
            common_args+=(--include-directories "$PROJECTS_DIR_PATH")
        fi
        if ! gemini --resume latest "${common_args[@]}"; then
            notify_resume_fallback
            exec gemini "${common_args[@]}"
        fi
        ;;
    opencode)
        zeltro_opencode_prepare
        common_args=(${ZELTRO_OPENCODE_ARGS[@]+"${ZELTRO_OPENCODE_ARGS[@]}"})
        [[ "$AUTO_APPROVE" == "1" ]] && common_args+=(--auto)
        # --continue reopens the last session in this directory; with none it
        # just opens a new one, which is the fallback anyway.
        exec opencode ${common_args[@]+"${common_args[@]}"} --continue
        ;;
    hermes)
        zeltro_hermes_prepare
        common_args=(${ZELTRO_HERMES_ARGS[@]+"${ZELTRO_HERMES_ARGS[@]}"})
        [[ "$AUTO_APPROVE" == "1" ]] && common_args+=(--yolo)
        # --in keeps --continue to this project's sessions, not the newest anywhere.
        if ! hermes chat ${common_args[@]+"${common_args[@]}"} --continue --in "$PWD"; then
            notify_resume_fallback
            exec hermes chat ${common_args[@]+"${common_args[@]}"}
        fi
        ;;
    aider)
        build_aider_args
        AIDER_ARGS+=(${ZELTRO_LANG_ARGS[@]+"${ZELTRO_LANG_ARGS[@]}"})
        AIDER_ARGS+=(${ZELTRO_GUI_HOOK_ARGS[@]+"${ZELTRO_GUI_HOOK_ARGS[@]}"})
        # --restore-chat-history replays this directory's .aider.chat.history.md.
        # There's nothing to fall back to: with no history aider just opens a
        # fresh session, which is the fallback behavior anyway.
        exec aider "${AIDER_ARGS[@]}" --restore-chat-history
        ;;
    *)
        echo-red "Unsupported AI agent: '$AI_AGENT_CLI_NAME'."
        echo-white "Supported agents: codex, claude, gemini, qwen, aider, opencode, hermes"
        exit 1
        ;;
esac
