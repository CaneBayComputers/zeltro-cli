#!/bin/bash

set -e

CALLER_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

DEV_DIR=$(pwd)

# Run standard pre-checks (loads /etc/zeltro-cli/.env, validates projects dir, etc.)
source scripts/pre_check.sh

SCRIPT_DIR="$DEV_DIR/scripts"

usage() {
    echo-white "Usage: zeltro create [--one-off] [-f|--file PATH] [\"project idea\"]"
    echo-white ""
    echo-white "Describe a project in plain English and your configured AI agent will"
    echo-white "create a working Zeltro-managed project for you."
    echo-white ""
    echo-white "The AI creates the project, writes an AGENTS.md handoff file into it,"
    echo-white "then cd's into the new project directory and hands off to your agent"
    echo-white "with a prompt to read that file."
    echo-white ""
    echo-white "Options:"
    echo-white "  --one-off        Stop after creation; skip the handoff (for automation)"
    echo-white "  -f, --file PATH  Read the project idea from a file instead of an argument"
    echo-white "  --classify-only  Work out the stack, print it, and stop. Creates nothing"
    echo-white "                   and never prompts. Combine with --json-output for a"
    echo-white "                   machine-readable result (for GUIs and other front ends)."
    echo-white ""
    echo-white "If neither a positional idea nor --file is given, zeltro create reads"
    echo-white "from stdin if it's piped or redirected. Falls back to an interactive"
    echo-white "prompt only when stdin is a terminal."
    echo-white ""
    echo-white "Examples:"
    echo-white "  zeltro create"
    echo-white "  zeltro create \"A task tracker with user auth\""
    echo-white "  zeltro create \"https://github.com/user/repo\""
    echo-white "  zeltro create --one-off \"A notes app in Express with postgres\""
    echo-white "  zeltro create -f big-prompt.md            # read idea from file"
    echo-white "  zeltro create < big-prompt.md             # via redirection"
    echo-white "  cat big-prompt.md | zeltro create         # via pipe"
    echo-white "  zeltro create <<< \"\$(cat big-prompt.md)\"  # via here-string"
}

SKIP_INTERACTIVE=0
CLASSIFY_ONLY=0
PROMPT_FILE=""
IDEA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --one-off)
            SKIP_INTERACTIVE=1
            shift
            ;;
        --classify-only)
            # Implies non-interactive: the contract is that this never prompts,
            # which includes never prompting for the idea itself.
            CLASSIFY_ONLY=1
            SKIP_INTERACTIVE=1
            shift
            ;;
        -f|--file|--prompt-file)
            if [[ -z "$2" ]]; then
                echo-red "Error: $1 requires a file path."
                usage
                exit 1
            fi
            PROMPT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            # Explicit end of options, so an idea may still begin with a dash.
            shift
            while [[ $# -gt 0 ]]; do IDEA_ARGS+=("$1"); shift; done
            ;;
        -*)
            # Previously any argument, flags included, was swallowed into the
            # idea text. That made a typo silently change the prompt, and made
            # an older CLI handed a newer flag BUILD A PROJECT rather than
            # reject the flag -- `zeltro create --classify-only "..."` on a CLI
            # without that flag created the project instead of classifying it.
            echo-red "Unknown option: $1"
            echo-white "Use '$ZELTRO_CMD --help' for the option list, or '--' before an idea that starts with a dash."
            exit 1
            ;;
        *)
            IDEA_ARGS+=("$1")
            shift
            ;;
    esac
done

USER_IDEA="${IDEA_ARGS[*]}"
STDIN_CONSUMED=0

# 1. --file takes precedence if no positional idea was provided
if [[ -z "$USER_IDEA" && -n "$PROMPT_FILE" ]]; then
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo-red "Prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    USER_IDEA=$(cat "$PROMPT_FILE")
fi

# 2. If stdin is piped/redirected and we still have no idea, slurp it all
if [[ -z "$USER_IDEA" && ! -t 0 ]]; then
    USER_IDEA=$(cat)
    STDIN_CONSUMED=1
fi

# 3. Still nothing? Ask, but only when a human is definitely there.
#    `zeltro create` already prompts for framework, database and project name,
#    so refusing to ask for the idea itself was the odd one out. The agent
#    guarantee is preserved by gating on exactly the same conditions the menus
#    use: scripts, CI, --one-off and --json-output still get a hard error.
if [[ -z "$USER_IDEA" ]]; then
    if [[ -t 0 && "$SKIP_INTERACTIVE" != "1" && "$JSON_OUTPUT" != "1" ]]; then
        echo-return
        echo-cyan "What would you like to build?"
        echo-white "Describe it in plain English — a sentence is enough, more detail is better."
        echo-return
        while [[ -z "$USER_IDEA" ]]; do
            echo-yellow -ne "> "
            read USER_IDEA || USER_IDEA=""
            # Blank input on a terminal means they changed their mind.
            if [[ -z "$USER_IDEA" ]]; then
                echo-white "Nothing entered — run 'zeltro create \"<idea>\"' when you're ready."
                exit 1
            fi
        done
        echo-return
    elif [[ "$JSON_OUTPUT" == "1" ]]; then
        # echo-red/echo-white are suppressed in JSON mode, so without this a
        # machine consumer got exit 1 and an empty stdout.
        json_error "no project idea provided; pass it as an argument, via -f <file>, or on stdin"
    else
        echo-red "No project idea provided."
        echo-white "Usage: zeltro create \"<idea>\"   |   zeltro create -f <file>   |   ... | zeltro create"
        exit 1
    fi
fi

# If we slurped stdin from a pipe/redirect, the interactive Phase 2 won't have
# a working stdin. Reattach it to the controlling terminal if there is one;
# otherwise force --one-off so we don't drop into a broken interactive session.
if [[ "$STDIN_CONSUMED" == "1" && "$SKIP_INTERACTIVE" == "0" ]]; then
    if [[ -e /dev/tty ]]; then
        exec </dev/tty
    else
        SKIP_INTERACTIVE=1
    fi
fi

# ---------------------------------------------------------------------------
# Phase 1: classify — decide the stack, confirm with the user
# ---------------------------------------------------------------------------
# The AI is asked ONLY which stack fits, and answers in JSON. Zeltro then does
# the creating itself. Previously one prompt had to hold the 100-app catalogue
# AND build the app, and a wrong stack guess wasn't visible until after a full
# build had been paid for.
source "$SCRIPT_DIR/classify.sh"

# Both phases need a working agent. Check it up front: the classifier discards
# the agent's stderr and retries, which would turn "ZELTRO_AI_AGENT names an
# agent that isn't installed" into a vague "could not determine a stack".
if ! _ai_problem=$(zeltro_ai_agent_problem); then
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        _action=create; [[ "$CLASSIFY_ONLY" == "1" ]] && _action=classify
        python3 -c 'import json,sys; print(json.dumps({"action": sys.argv[1], "status": "error", "error": "ai_agent_unavailable", "message": sys.argv[2]}))' "$_action" "$_ai_problem"
    else
        echo-red "$_ai_problem" >&2
    fi
    exit 1
fi

# Menus need a human. Anything scripted takes the top recommendation silently,
# preserving the promise that no zeltro command ever blocks an agent.
# --classify-only stops here: run phase 1, report, and create nothing. Placed
# before the menus rather than inside classify_project so no interactive code
# path is reachable at all.
if [[ "$CLASSIFY_ONLY" == "1" ]]; then
    classify_only "$USER_IDEA" "$JSON_OUTPUT" || exit 1
    exit 0
fi

CLASSIFY_NONINTERACTIVE=0
if [[ "$SKIP_INTERACTIVE" == "1" || "$JSON_OUTPUT" == "1" || ! -t 0 ]]; then
    CLASSIFY_NONINTERACTIVE=1
fi

CHOSEN_KIND=""; CHOSEN_SLUG=""; CHOSEN_DB=""; CHOSEN_NAME=""; CHOSEN_CUSTOMIZE="yes"

if ! classify_project "$USER_IDEA" "$CLASSIFY_NONINTERACTIVE"; then
    echo-yellow "Could not determine a stack automatically."
    echo-white "Create the project yourself, then describe what to build:"
    echo-white "  zeltro new <framework> <name>   or   zeltro install <app>"
    echo-white "  cd \"$PROJECTS_DIR_PATH/<name>\" && zeltro ai \"$USER_IDEA\""
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 2: create — Zeltro does this, not the AI
# ---------------------------------------------------------------------------
echo-return
if [[ "$CHOSEN_KIND" == "app" ]]; then
    echo-cyan "Installing $CHOSEN_SLUG as '$CHOSEN_NAME' ..."
else
    echo-cyan "Creating $CHOSEN_SLUG project '$CHOSEN_NAME'${CHOSEN_DB:+ with $CHOSEN_DB} ..."
fi
echo-return

# A pre-existing directory means a stale project of the same name; `create`
# always means start fresh.
if [[ -d "$PROJECTS_DIR_PATH/$CHOSEN_NAME" ]]; then
    echo-yellow "Project '$CHOSEN_NAME' already exists — replacing it."
    "$SCRIPT_DIR/remove_project.sh" "$CHOSEN_NAME" --force --force-db-delete >/dev/null 2>&1 || true
fi

# --one-off on the inner command: the hand-off below is ours to run, and we do
# not want a nested agent session firing in the middle of create.
if [[ "$CHOSEN_KIND" == "app" ]]; then
    "$SCRIPT_DIR/install.sh" "$CHOSEN_SLUG" "$CHOSEN_NAME" --one-off || {
        echo-red "Install of '$CHOSEN_SLUG' failed."; exit 1; }
else
    "$SCRIPT_DIR/new_project.sh" "$CHOSEN_SLUG" "$CHOSEN_NAME" ${CHOSEN_DB:+--database "$CHOSEN_DB"} --one-off || {
        echo-red "Creating '$CHOSEN_NAME' failed."; exit 1; }
fi

PROJECT_DIR="$PROJECTS_DIR_PATH/$CHOSEN_NAME"
if [[ ! -d "$PROJECT_DIR" ]]; then
    echo-red "Expected project directory not found: $PROJECT_DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 3: build — hand the ORIGINAL idea to the agent, inside the project
# ---------------------------------------------------------------------------
# Skipped entirely for a plain app install. install.sh has already polled until
# the app answered 2xx/3xx and printed its URL, credentials (INSTALL_CREDENTIALS)
# and gotchas (INSTALL_NOTES) — so an agent session here would spend real tokens
# re-deriving what Zeltro reported seconds ago. It only earns its keep when the
# user asked for something beyond standing the software up.
write_project_agents_md "$CHOSEN_NAME" "$PROJECT_DIR"

if [[ "$CHOSEN_KIND" == "app" && "$CHOSEN_CUSTOMIZE" != "yes" ]]; then
    echo-return
    echo-green "Done — $CHOSEN_SLUG is installed and serving."
    echo-white "Nothing beyond the install was requested, so no AI build step was needed."
    echo-return
    echo-cyan "To customize it from here:"
    echo-white "  cd \"$PROJECT_DIR\""
    echo-white "  zeltro ai \"<what you want changed>\""
    echo-return
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        echo "{\"action\": \"create\", \"project_name\": \"$CHOSEN_NAME\", \"kind\": \"app\", \"slug\": \"$CHOSEN_SLUG\", \"build_step\": \"skipped\", \"status\": \"success\"}"
    fi
    cd "$CALLER_DIR"
    exit 0
fi

# The environment already exists, so this prompt carries none of the creation
# rules the old single-phase prompt needed. The per-project AGENTS.md written
# above supplies the URL, database and command patterns.
COMMON_RULES="Rules:
- Run project tooling inside the container (zeltro exec / zeltro art / zeltro django manage / zeltro npm ...), never on the host.
- Python containers provide python3, not python. For Django use 'zeltro django manage <args>'.
- To restart processes use 'zeltro supervisor restart all', never 'zeltro exec supervisorctl'.
- Never pass --json-output to a zeltro command; it hides the success/failure distinction.
- Before verifying, RESTART the app so your changes are actually loaded:
  'zeltro supervisor restart all'. A long-running server keeps serving the code
  it started with, so curling without restarting can return 200 from the
  pre-edit process and hide a broken app.
- If you imported a package, add it to requirements.txt / package.json /
  composer.json AND install it in the container. An import that was never
  installed only fails once the process restarts.
- You are NOT done until, AFTER that restart, 'curl -s -o /dev/null -w \"%{http_code}\" --max-time 10 http://$CHOSEN_NAME/' returns 2xx or 3xx AND the response reflects what you built rather than the scaffold's placeholder page. If it does not, check 'docker logs $CHOSEN_NAME', fix it, and re-verify."

if [[ "$CHOSEN_KIND" == "app" ]]; then
    # The software is already installed, configured and serving. Framing this as
    # "build X" invites the agent to rebuild the whole app from scratch, so the
    # install is stated as done and only the leftover work is asked for.
    BUILD_PROMPT="This Zeltro project is an existing, already-running install of '$CHOSEN_SLUG'. It is installed, configured and serving at http://$CHOSEN_NAME/.

Do NOT install, reinstall, rebuild or scaffold it. Do NOT run zeltro new, zeltro clone or zeltro install. The software itself is finished.

Read AGENTS.md in this directory first: it has the local URL, the database and the command patterns to use inside the container.

The user's original request was:

$USER_IDEA

The install part of that request is already complete. Address ONLY the remaining customization — the parts that go beyond standing the software up. If, on reading it again, nothing remains to be done, just verify the app responds and say so rather than inventing work.

$COMMON_RULES"
else
    BUILD_PROMPT="You are the developer on an existing Zeltro project. The project has been created and is running — do NOT run zeltro new, zeltro clone or zeltro install, and do not create another project.

Read AGENTS.md in this directory first: it has the local URL, the database, and the command patterns to use inside the container.

Build this:

$USER_IDEA

- Use framework-native conventions: migrations, models, seeders, routes, controllers, templates.
- Do not require the user to create database tables by hand.
- Update this project's README with the local URL, useful commands, and any default credentials.

$COMMON_RULES"
fi

echo-return
echo-green "Project ready: $CHOSEN_NAME"
echo-white "Local URL: http://$CHOSEN_NAME/"
echo-white "Directory: $PROJECT_DIR"
echo-return
# Asked for once, here, at the moment something actually worked -- not on `up`,
# `status` or anything else people run all day. echo-white is a no-op under
# --json-output, so machine consumers never see it.
echo-white "Zeltro is free and always will be. If it saved you time: https://ko-fi.com/canebaycomputers"
echo-return

if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "{\"action\": \"create\", \"project_name\": \"$CHOSEN_NAME\", \"kind\": \"$CHOSEN_KIND\", \"slug\": \"$CHOSEN_SLUG\", \"database\": \"$CHOSEN_DB\", \"status\": \"success\"}"
    cd "$CALLER_DIR"
    exit 0
fi

cd "$PROJECT_DIR"
exec "$SCRIPT_DIR/ai.sh" "$BUILD_PROMPT"
