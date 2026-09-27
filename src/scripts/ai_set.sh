#!/bin/bash

set -e

ORIG_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

DEV_DIR=$(pwd)

# This script writes AI_* to the .env, so it must see the .env values, never a
# per-session ZELTRO_AI_* override (which would then get persisted).
ZELTRO_AI_NO_OVERRIDE=1
source scripts/functions.sh

SCRIPT_DIR="$DEV_DIR/scripts"

NEW_AGENT=""
NEW_MODEL=""
NEW_API_KEY=""
API_KEY_PROVIDED=0
API_BASE_PROVIDED=0
NEW_API_BASE=""
# "" = not requested (leave the agent's config alone), "allow", or "revoke".
UNATTENDED_REQUEST=""
INSTALL_ONLY=0

# AI agent configuration rules (summary)
# --------------------------------------
# Supported agents and how global vars apply:
#   - codex
#       * AI_MODEL: OPTIONAL (when set, passed as `--model "$AI_MODEL"` to `codex`)
#       * AI_API_KEY: OPTIONAL (when set, passed as `--api-key "$AI_API_KEY"` to `codex`) if you choose API-key auth
#   - claude
#       * AI_MODEL: OPTIONAL (when set, passed as `--model "$AI_MODEL"` to `claude`)
#       * AI_API_KEY: OPTIONAL (when set, passed as `--api-key "$AI_API_KEY"` to `claude`)
#   - gemini
#       * AI_MODEL: OPTIONAL (when set, passed as `--model "$AI_MODEL"` to `gemini`)
#       * AI_API_KEY: not used (gemini uses Google account auth or GEMINI_API_KEY env var)
#   - aider
#       * AI_MODEL: REQUIRED in practice — aider has no login of its own, so the
#         model name is what picks the provider (openai/gpt-4o, anthropic/…, ollama/…)
#       * AI_API_KEY: REQUIRED — passed as `--api-key provider=$AI_API_KEY`, where
#         the provider is taken from the AI_MODEL prefix unless the key is already
#         tagged (contains `=`)
#       * AI_API_BASE: OPTIONAL — passed as `--openai-api-base "$AI_API_BASE"`, for
#         OpenAI-compatible servers (Ollama, LM Studio, OpenRouter, vLLM)
#
# Initial-prompt behavior (driven by `zeltro ai "<prompt>"`):
#   - codex  : `codex [--model "$AI_MODEL"] [--api-key "$AI_API_KEY"] "<prompt>"`
#   - claude : `claude [--model "$AI_MODEL"] [--api-key "$AI_API_KEY"] "<prompt>"`
#   - gemini : `gemini [--model "$AI_MODEL"] -i "<prompt>"`
#   - aider  : `aider --no-auto-commits --no-check-update [--model …] [--api-key …] [--openai-api-base …] --message "<prompt>"`
#              (interactive seeds the session with `--load` + `/code <prompt>`, since
#               aider's --message processes the prompt and exits)
#
# Approval-bypass flags are NOT passed. Whether an agent runs unattended is the
# user's decision, recorded in that agent's own config — see `zeltro ai-unattended`.

usage() {
    echo-white "Usage: zeltro ai-set [--agent NAME] [--model NAME] [--api-key KEY] [--api-base URL] [--json-output]"
    echo-white ""
    echo-white "Configure or inspect the global AI agent settings used by Zeltro."
    echo-white ""
    echo-white "Options:"
    echo-white "  --agent NAME       Set the AI agent CLI (codex, claude, gemini, qwen, or aider)."
    echo-white "  --model NAME       Set the AI model name (optional for codex, claude, gemini; required for qwen and aider)."
    echo-white "  --api-key KEY      Set the AI API key (optional for codex and claude; required for aider)."
    echo-white "                     Pass an empty value (--api-key \"\") to clear a stored key."
    echo-white "  --api-base URL     Set a custom API endpoint. Works with codex, qwen and aider"
    echo-white "                     (OpenAI-compatible: OpenRouter, Ollama, vLLM, LM Studio),"
    echo-white "                     and with claude via an Anthropic-compatible proxy."
    echo-white "  --json-output      Output configuration in JSON format (non-interactive)."
    echo-white "  --allow-unattended    Let the agent run without approval prompts. Writes the setting"
    echo-white "                        to the agent's OWN config; applies non-interactively."
    echo-white "  --no-allow-unattended Turn that back off. Omit both to leave the setting unchanged."
    echo-white "  --install-only        With --agent: install that agent's CLI if missing, without"
    echo-white "                        making it the default. Writes nothing to the configuration."
    echo-white ""
    echo-white "Notes:"
    echo-white "  - When --json-output is used, no interactive prompts are shown."
    echo-white "  - If called with only --json-output, the current configuration is returned as JSON."
    echo-white "    That call is read-only: it installs nothing and writes nothing."
    echo-white "  - To use a different agent for one run without changing the default, set"
    echo-white "    ZELTRO_AI_AGENT / ZELTRO_AI_MODEL / ZELTRO_AI_API_BASE / ZELTRO_AI_API_KEY"
    echo-white "    (or ZELTRO_AI_API_KEY_FILE) in the environment. See 'zeltro help'."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json-output)
            export JSON_OUTPUT=1
            shift
            ;;
        # Tri-state on purpose: ABSENT means "leave unchanged". A GUI form that
        # submits its whole state on Save needs to be able to turn this OFF as
        # easily as on — a safety setting that is one-way is the wrong direction
        # to be one-way in.
        --allow-unattended)
            UNATTENDED_REQUEST="allow"
            shift
            ;;
        --no-allow-unattended)
            UNATTENDED_REQUEST="revoke"
            shift
            ;;
        --install-only)
            INSTALL_ONLY=1
            shift
            ;;
        --agent)
            NEW_AGENT="$2"
            shift 2
            ;;
        --model)
            NEW_MODEL="$2"
            shift 2
            ;;
        --api-key)
            # Tracked separately from its value so an explicit empty string
            # ("clear it") is distinguishable from the option being absent.
            NEW_API_KEY="$2"
            API_KEY_PROVIDED=1
            shift 2
            ;;
        --api-base)
            NEW_API_BASE="$2"
            API_BASE_PROVIDED=1
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            if [[ "$JSON_OUTPUT" == "1" ]]; then
                echo "{\"action\": \"ai_set\", \"status\": \"error\", \"error\": \"unknown_option\", \"details\": \"Unknown option: $1\"}"
            else
                echo-red "Unknown option: $1"
                usage
            fi
            exit 1
            ;;
    esac
done

# Apply non-interactive overrides
if [[ -n "$NEW_AGENT" ]]; then
    AI_AGENT="$NEW_AGENT"
    # If the agent changed and no explicit model was provided, clear any stale model
    if [[ -z "$NEW_MODEL" ]]; then
        AI_MODEL=""
    fi
    # Endpoints are provider-specific too — a base URL left over from the
    # previous agent would silently point the new one at the wrong server.
    if [[ -z "$NEW_API_BASE" ]]; then
        AI_API_BASE=""
    fi
fi
if [[ -n "$NEW_MODEL" ]]; then
    AI_MODEL="$NEW_MODEL"
fi
if [[ "$API_KEY_PROVIDED" == "1" ]]; then
    AI_API_KEY="$NEW_API_KEY"
fi
if [[ "$API_BASE_PROVIDED" == "1" ]]; then
    # "none" and "" both mean clear it. The interactive prompt has always
    # accepted "none"; the flag stored it as a literal endpoint, which then got
    # exported as OPENAI_BASE_URL=none and broke the agent.
    if [[ "$NEW_API_BASE" == "none" ]]; then
        AI_API_BASE=""
    else
        AI_API_BASE="$NEW_API_BASE"
    fi
fi

NONINTERACTIVE=0
# No TTY on stdin means nobody can answer a prompt — reading would hit EOF and
# either abort under `set -e` or spin the selection loop forever. Treat it as
# non-interactive so scripted runs (and `zeltro configure < /dev/null`) keep the
# existing configuration instead of hanging or dying.
if [[ "$JSON_OUTPUT" == "1" || -n "$NEW_AGENT" || -n "$NEW_MODEL" || -n "$NEW_API_KEY" || -n "$NEW_API_BASE" || -n "$UNATTENDED_REQUEST" || ! -t 0 ]]; then
    NONINTERACTIVE=1
fi

select_ai_agent() {
    local previous_agent="$AI_AGENT"

    while true; do
        echo-return
        echo-cyan 'AI Agent CLI Selection'; echo-white
        echo-white 'Choose the AI agent CLI you prefer to use:'
        echo-white '  1) codex'
        echo-white '  2) claude'
        echo-white '  3) gemini'
        echo-white '  4) aider   (bring your own API key — any model/provider)'
        echo-white '  5) qwen    (Qwen Code — cheap/local models via an OpenAI-compatible endpoint)'
        echo-return
        echo-yellow -ne 'Enter your choice (1-5): '
        echo-white -ne
        read AI_AGENT_CHOICE
        echo-return

        case "$AI_AGENT_CHOICE" in
            1)
                AI_AGENT="codex"
                sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
                break
                ;;
            2)
                AI_AGENT="claude"
                sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
                break
                ;;
            3)
                AI_AGENT="gemini"
                sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
                break
                ;;
            4)
                AI_AGENT="aider"
                sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
                break
                ;;
            5)
                AI_AGENT="qwen"
                sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
                break
                ;;
            *)
                echo-yellow "Invalid selection. Please enter 1, 2, 3, 4, or 5."
                ;;
        esac
    done

    # Model names and endpoints don't carry across agents — a leftover
    # "gemini-2.5-pro" handed to aider is just a broken run.
    if [[ -n "$previous_agent" && "$AI_AGENT" != "$previous_agent" ]]; then
        AI_MODEL=""
        AI_API_BASE=""
    fi
}

prompt_ai_model() {
    echo-return
    echo-cyan "AI Model Configuration"; echo-white

    if [[ -n "$AI_MODEL" ]]; then
        echo-white "Current model: $AI_MODEL"
    else
        echo-white "No model is currently configured."
    fi

    # Aider is the one agent with no login of its own — the model name is what
    # selects the provider, so it can't be skipped the way it can elsewhere.
    if [[ "$AI_AGENT" == "aider" ]]; then
        echo-return
        echo-white "Aider needs a model — the name is what picks the provider:"
        echo-white "  openai/gpt-4o                     OpenAI"
        echo-white "  anthropic/claude-sonnet-4-5       Anthropic"
        echo-white "  gemini/gemini-2.5-pro             Google"
        echo-white "  deepseek/deepseek-chat            DeepSeek"
        echo-white "  openai/<name>  + an API endpoint  Ollama / LM Studio / OpenRouter / vLLM"
        echo-white "Full list: https://aider.chat/docs/llms.html"
        echo-return
        echo-yellow -ne 'Enter model name: '
    else
        echo-yellow -ne 'Enter model name (optional, press Enter to leave blank): '
    fi

    echo-white -ne
    read NEW_MODEL
    echo-return
    if [[ -n "$NEW_MODEL" ]]; then
        AI_MODEL="$NEW_MODEL"
    fi

    if [[ "$AI_AGENT" == "aider" && -z "$AI_MODEL" ]]; then
        echo-yellow "No model set. 'zeltro ai' will fall back to whatever aider defaults to,"
        echo-yellow "which depends on which API key it finds in the environment."
        echo-return
    fi
}

prompt_ai_api_base() {
    echo-return
    echo-cyan "API Endpoint (optional)"; echo-white
    echo-white "Leave this blank to use the provider's own hosted API."
    echo-white "Set it only to point aider at an OpenAI-compatible server, e.g.:"
    echo-white "  http://localhost:11434/v1     Ollama"
    echo-white "  http://localhost:1234/v1      LM Studio"
    echo-white "  https://openrouter.ai/api/v1  OpenRouter"

    if [[ -n "$AI_API_BASE" ]]; then
        echo-return
        echo-white "Current endpoint: $AI_API_BASE"
        echo-yellow "Press Enter to keep it, or type 'none' to clear it."
    fi

    echo-return
    echo-yellow -ne 'Enter API endpoint URL (Enter to skip): '
    echo-white -ne
    read -r NEW_AI_API_BASE
    echo-return

    if [[ "$NEW_AI_API_BASE" == "none" ]]; then
        AI_API_BASE=""
    elif [[ -n "$NEW_AI_API_BASE" ]]; then
        AI_API_BASE="$NEW_AI_API_BASE"
    fi
}

configure_ai_api_key() {
    echo-return
    echo-cyan "AI API key configuration"; echo-white
    if [[ -n "$AI_API_KEY" ]]; then
        echo-white "An AI API key is already configured."
        echo-yellow "You can press Enter to keep it, or enter a new key."
    else
        echo-white "No AI API key is currently configured."
    fi
    echo-yellow -ne 'Enter AI API key (Enter to keep existing): '
    echo-white -ne
    read -r NEW_AI_API_KEY
    echo-return

    if [[ -n "$NEW_AI_API_KEY" ]]; then
        AI_API_KEY="$NEW_AI_API_KEY"
    fi
}

configure_codex_auth() {
    echo-return
    echo-cyan "Codex Authentication"; echo-white
    echo-white "You can authenticate Codex via:"
    echo-white "  1) Login (recommended - uses your ChatGPT billing/account)"
    echo-white "  2) API key"
    echo-return
    echo-yellow -ne "Choose authentication method for Codex (1-2): "
    echo-white -ne
    read CODEX_AUTH_CHOICE
    echo-return

    case "$CODEX_AUTH_CHOICE" in
        1)
            while true; do
                echo-yellow "Starting 'codex login' ..."; echo-white
                if codex login; then
                    echo-green "Codex login completed successfully."; echo-white
                    echo-return
                    break
                fi
                echo-yellow "Codex login failed or was cancelled."; echo-white
                echo-yellow -ne "Would you like to try 'codex login' again? (y/N): "
                echo-white -ne
                read RETRY_CODEX_LOGIN
                echo-return
                if [[ ! "$RETRY_CODEX_LOGIN" =~ ^[Yy]$ ]]; then
                    echo-cyan "Continuing without successful Codex login."; echo-white
                    echo-return
                    break
                fi
            done
            ;;
        2)
            echo-return
            echo-white "OpenAI API keys: https://platform.openai.com/api-keys"
            configure_ai_api_key
            ;;
        *)
            echo-yellow "Invalid selection. Skipping Codex authentication helper."; echo-white
            ;;
    esac
}

configure_claude_auth() {
    echo-return
    echo-cyan "Claude Authentication"; echo-white
    echo-white "You can configure Claude via:"
    echo-white "  1) Interactive CLI (run 'claude' to configure)"
    echo-white "  2) API key"
    echo-return
    echo-yellow -ne "Choose authentication method for Claude (1-2): "
    echo-white -ne
    read CLAUDE_AUTH_CHOICE
    echo-return

    case "$CLAUDE_AUTH_CHOICE" in
        1)
            while true; do
                echo-yellow "Starting 'claude' ..."; echo-white
                if claude; then
                    echo-green "Claude CLI finished without errors."; echo-white
                    echo-return
                    break
                fi
                echo-yellow "Claude CLI exited with an error or was cancelled."; echo-white
                echo-yellow -ne "Would you like to run 'claude' again? (y/N): "
                echo-white -ne
                read RETRY_CLAUDE
                echo-return
                if [[ ! "$RETRY_CLAUDE" =~ ^[Yy]$ ]]; then
                    echo-cyan "Continuing without additional Claude setup."; echo-white
                    echo-return
                    break
                fi
            done
            ;;
        2)
            echo-return
            echo-white "Claude API keys: https://console.anthropic.com/"
            configure_ai_api_key
            ;;
        *)
            echo-yellow "Invalid selection. Skipping Claude authentication helper."; echo-white
            ;;
    esac
}

configure_gemini_auth() {
    echo-return
    echo-cyan "Gemini Authentication"; echo-white
    echo-white "You can configure Gemini via:"
    echo-white "  1) Interactive CLI (run 'gemini' to configure)"
    echo-white "  2) API key"
    echo-return
    echo-yellow -ne "Choose authentication method for Gemini (1-2): "
    echo-white -ne
    read GEMINI_AUTH_CHOICE
    echo-return

    case "$GEMINI_AUTH_CHOICE" in
        1)
            while true; do
                echo-yellow "Starting 'gemini' ..."; echo-white
                if gemini; then
                    echo-green "Gemini CLI finished without errors."; echo-white
                    echo-return
                    break
                fi
                echo-yellow "Gemini CLI exited with an error or was cancelled."; echo-white
                echo-yellow -ne "Would you like to run 'gemini' again? (y/N): "
                echo-white -ne
                read RETRY_GEMINI
                echo-return
                if [[ ! "$RETRY_GEMINI" =~ ^[Yy]$ ]]; then
                    echo-cyan "Continuing without additional Gemini setup."; echo-white
                    echo-return
                    break
                fi
            done
            ;;
        2)
            echo-return
            echo-white "Gemini API keys: https://aistudio.google.com/app/api-keys"
            configure_ai_api_key
            ;;
        *)
            echo-yellow "Invalid selection. Skipping Gemini authentication helper."; echo-white
            ;;
    esac
}

ensure_ai_agent_installed() {
    local cli_command="$1"
    local exec_command="$cli_command"

    if [[ -z "$cli_command" ]]; then
        return 0
    fi

    # If the CLI is already available, nothing to do beyond checking that it can
    # actually run unattended — Zeltro's AI commands stall otherwise.
    if command -v "$exec_command" >/dev/null 2>&1; then
        echo-green "AI agent CLI '$cli_command' is already installed (command: $exec_command)."
        echo-white
        zeltro_offer_agent_autonomy "$cli_command"
        return 0
    fi

    echo-yellow "AI agent CLI '$cli_command' is not installed. Attempting automatic installation..."

    case "$cli_command" in
        codex)
            npm install -g @openai/codex
            ;;
        gemini)
            npm install -g @google/gemini-cli
            ;;
        qwen)
            npm install -g @qwen-code/qwen-code
            ;;
        claude)
            curl -fsSL https://claude.ai/install.sh | bash
            ;;
        aider)
            curl -LsSf https://aider.chat/install.sh | sh
            # aider installs into ~/.local/bin, which isn't necessarily on PATH
            # in this shell yet — make the check below (and this run) see it.
            case ":$PATH:" in
                *":$HOME/.local/bin:"*) ;;
                *) export PATH="$HOME/.local/bin:$PATH" ;;
            esac
            ;;
        *)
            echo-yellow "Automatic installation for '$cli_command' is not configured. Please install it manually."
            ;;
    esac

    if command -v "$exec_command" >/dev/null 2>&1; then
        echo-green "AI agent CLI '$cli_command' installed successfully (command: $exec_command)."
        echo-white
        zeltro_offer_agent_autonomy "$cli_command"
        return 0
    fi

    echo-yellow "AI agent CLI '$cli_command' is still not available on PATH."
    echo-yellow "You can install it manually and re-run 'zeltro ai-set' or choose a different CLI."
    echo-white
}

# Known agents whose CLI is on PATH, as a JSON array.
installed_agents_json() {
    local a out=""
    for a in $ZELTRO_KNOWN_AI_AGENTS; do
        command -v "$a" >/dev/null 2>&1 && out="$out${out:+, }\"$a\""
    done
    printf '[%s]' "$out"
}

# The current (.env) configuration. session_overrides tells a caller this CLI
# honours ZELTRO_AI_* per run; installed_agents says which of them can run here.
print_config_json() {
    local has_api_key="false"
    [[ -n "$AI_API_KEY" ]] && has_api_key="true"
    # `unattended` is true/false/unknown — never an error. The GUI renders
    # "unknown" as unchecked with a note, which beats a failed call: a config
    # it cannot parse should not stop the whole settings panel from loading.
    local unattended
    unattended=$(zeltro_read_agent_autonomy "${AI_AGENT:-}")
    echo "{\"action\": \"ai_set\", \"status\": \"success\", \"agent\": \"${AI_AGENT:-}\", \"model\": \"${AI_MODEL:-}\", \"api_base\": \"${AI_API_BASE:-}\", \"has_api_key\": $has_api_key, \"unattended\": \"$unattended\", \"session_overrides\": true, \"agent_bus\": 1, \"installed_agents\": $(installed_agents_json)}"
}

# --install-only: make an agent runnable here without making it the default,
# so a per-session ZELTRO_AI_AGENT profile can use it. Touches no configuration.
if [[ "$INSTALL_ONLY" == "1" ]]; then
    _bad=""
    if [[ -z "$NEW_AGENT" ]]; then
        _bad="--install-only needs --agent NAME."
    elif [[ -n "$NEW_MODEL" || "$API_KEY_PROVIDED" == "1" || "$API_BASE_PROVIDED" == "1" ]]; then
        _bad="--install-only takes only --agent (plus --allow-unattended / --no-allow-unattended); it does not change the configuration."
    else
        case " $ZELTRO_KNOWN_AI_AGENTS " in
            *" $NEW_AGENT "*) ;;
            *) _bad="Unknown AI agent '$NEW_AGENT'. Known agents: $ZELTRO_KNOWN_AI_AGENTS." ;;
        esac
    fi
    if [[ -n "$_bad" ]]; then
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            echo "{\"action\": \"ai_install\", \"status\": \"error\", \"agent\": \"$NEW_AGENT\", \"details\": \"$_bad\"}"
        else
            echo-red "$_bad"
        fi
        exit 1
    fi

    [ -n "$UNATTENDED_REQUEST" ] && export ZELTRO_UNATTENDED_EXPLICIT=1
    # The installer output is for humans; keep it off stdout in JSON mode.
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        ensure_ai_agent_installed "$NEW_AGENT" >&2 || true
    else
        ensure_ai_agent_installed "$NEW_AGENT" || true
    fi

    if ! command -v "$NEW_AGENT" >/dev/null 2>&1; then
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            echo "{\"action\": \"ai_install\", \"status\": \"error\", \"agent\": \"$NEW_AGENT\", \"installed\": false, \"details\": \"$NEW_AGENT is still not on PATH after the install attempt.\", \"installed_agents\": $(installed_agents_json)}"
        else
            echo-red "$NEW_AGENT is still not on PATH after the install attempt."
        fi
        exit 1
    fi

    case "$UNATTENDED_REQUEST" in
        allow)  zeltro_allow_agent_autonomy  "$NEW_AGENT" ;;
        revoke) zeltro_revoke_agent_autonomy "$NEW_AGENT" ;;
    esac

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        echo "{\"action\": \"ai_install\", \"status\": \"success\", \"agent\": \"$NEW_AGENT\", \"installed\": true, \"unattended\": \"$(zeltro_read_agent_autonomy "$NEW_AGENT")\", \"installed_agents\": $(installed_agents_json)}"
    else
        echo-green "$NEW_AGENT is installed. The default agent is unchanged (${AI_AGENT:-<none>})."
    fi
    cd "$ORIG_DIR"
    exit 0
fi

# A bare `--json-output` is a probe: report and change nothing. It used to fall
# through to the write path below, so reading the settings could sudo-rewrite
# the .env and even try to install the configured agent.
if [[ "$JSON_OUTPUT" == "1" && -z "$NEW_AGENT" && -z "$NEW_MODEL" && "$API_KEY_PROVIDED" != "1" && "$API_BASE_PROVIDED" != "1" && -z "$UNATTENDED_REQUEST" ]]; then
    print_config_json
    cd "$ORIG_DIR"
    exit 0
fi

if [[ "$NONINTERACTIVE" -eq 1 ]]; then
    # An explicit --allow-unattended / --no-allow-unattended suppresses the
    # interactive consent prompt inside ensure_ai_agent_installed: the caller has
    # already answered, so asking twice is noise.
    [ -n "$UNATTENDED_REQUEST" ] && export ZELTRO_UNATTENDED_EXPLICIT=1

    ensure_ai_agent_installed "$AI_AGENT"

    case "$UNATTENDED_REQUEST" in
        allow)  zeltro_allow_agent_autonomy  "$AI_AGENT" ;;
        revoke) zeltro_revoke_agent_autonomy "$AI_AGENT" ;;
    esac

    # Persist configuration
    if [[ -n "$AI_AGENT" ]]; then
        sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
    fi

    # Model and endpoint are written unconditionally: switching agents clears
    # them above, and that clearing has to reach the file or the next run picks
    # the old agent's model back up.
    sudo-zeltro-env-set "AI_MODEL" "${AI_MODEL:-}" /etc/zeltro-cli/.env
    sudo-zeltro-env-set "AI_API_BASE" "${AI_API_BASE:-}" /etc/zeltro-cli/.env

    sudo-zeltro-env-set "AI_API_KEY" "${AI_API_KEY:-}" /etc/zeltro-cli/.env

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        print_config_json
    else
        echo-green "AI agent configuration updated."
        echo-white "  Agent: ${AI_AGENT:-<none>}"
        echo-white "  Model: ${AI_MODEL:-<none>}"
        [[ -n "$AI_API_BASE" ]] && echo-white "  Endpoint: $AI_API_BASE"
        echo-return
    fi

    cd "$ORIG_DIR"
    exit 0
fi

echo-return
echo-cyan "Zeltro AI Agent Configuration"; echo-white

if [[ -n "$AI_AGENT" ]]; then
    echo-white "Current AI agent: $AI_AGENT"
    echo-yellow -ne "Do you want to change the AI agent? (y/N): "
    echo-white -ne
    read CHANGE_AGENT
    echo-return
    if [[ "$CHANGE_AGENT" =~ ^[Yy]$ ]]; then
        select_ai_agent
    else
        # Ensure current agent is persisted immediately as well
        sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
    fi
else
    select_ai_agent
fi

prompt_ai_model

# codex/claude/gemini can authenticate with their own login on first run, so the
# key and endpoint questions are skipped for them. Aider can't — it only talks
# to a provider API — so ask up front rather than failing at the first prompt.
if [[ "$AI_AGENT" == "aider" ]]; then
    echo-cyan "Aider has no login of its own — it authenticates with the provider's API key."
    echo-white "  OpenAI:    https://platform.openai.com/api-keys"
    echo-white "  Anthropic: https://console.anthropic.com/"
    echo-white "  Google:    https://aistudio.google.com/app/api-keys"
    echo-white "(A local server such as Ollama usually accepts any placeholder key.)"
    configure_ai_api_key
    prompt_ai_api_base
fi

# An explicit --allow-unattended / --no-allow-unattended suppresses the
# interactive consent prompt inside ensure_ai_agent_installed: the caller has
# already answered, so asking twice is noise.
[ -n "$UNATTENDED_REQUEST" ] && export ZELTRO_UNATTENDED_EXPLICIT=1

ensure_ai_agent_installed "$AI_AGENT"

case "$UNATTENDED_REQUEST" in
    allow)  zeltro_allow_agent_autonomy  "$AI_AGENT" ;;
    revoke) zeltro_revoke_agent_autonomy "$AI_AGENT" ;;
esac

# Persist configuration
if [[ -n "$AI_AGENT" ]]; then
    sudo-zeltro-sed-change "/^AI_AGENT=/" "AI_AGENT=\"$AI_AGENT\"" /etc/zeltro-cli/.env
fi

# Written unconditionally so that clearing a value (switching agents, or
# answering 'none' to the endpoint) actually reaches the file.
sudo-zeltro-env-set "AI_MODEL" "${AI_MODEL:-}" /etc/zeltro-cli/.env
sudo-zeltro-env-set "AI_API_BASE" "${AI_API_BASE:-}" /etc/zeltro-cli/.env

sudo-zeltro-env-set "AI_API_KEY" "${AI_API_KEY:-}" /etc/zeltro-cli/.env

echo-green "AI agent configuration complete."
echo-white "  Agent: ${AI_AGENT:-<none>}"
echo-white "  Model: ${AI_MODEL:-<none>}"
[[ -n "$AI_API_BASE" ]] && echo-white "  Endpoint: $AI_API_BASE"
echo-return
if [[ "$AI_AGENT" == "aider" ]]; then
    echo-white "Aider uses the API key above on every run — there is no separate login step."
else
    echo-white "Authentication will happen automatically the first time you run 'zeltro create' or 'zeltro ai'."
fi
echo-return

_unattended_state=$(zeltro_read_agent_autonomy "$AI_AGENT")
if [ "$_unattended_state" = "true" ]; then
    echo-yellow "IMPORTANT:"
    echo-white "  $AI_AGENT is configured to run WITHOUT approval prompts, so it can edit files"
    echo-white "  and run commands in your projects unattended. Only use 'zeltro ai' and"
    echo-white "  'zeltro create' in directories you are comfortable letting it modify freely."
    echo-white "  Turn this off with: zeltro ai-unattended $AI_AGENT --revoke"
else
    echo-cyan "Note:"
    echo-white "  $AI_AGENT will ask before each action. That is the safe default, but it stalls"
    echo-white "  unattended runs such as 'zeltro create'."
    echo-white "  Allow it to run unattended with: zeltro ai-unattended $AI_AGENT"
fi
echo-return

cd "$ORIG_DIR"
