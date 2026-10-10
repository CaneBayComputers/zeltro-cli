#!/bin/bash
# zeltro new folder <name>: a folder project. A plain folder in the projects
# directory with an AI session and nothing else: no container, framework,
# database or address. See the "Folder projects" block in functions.sh.
#
#   zeltro new folder <name> [--one-off] [--json-output]

set -e

ORIG_DIR=$(pwd)
cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

PROJECT_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json-output) JSON_OUTPUT=1; shift ;;
        --one-off) SKIP_INTERACTIVE=1; shift ;;
        --no-colors|--debug) shift ;;
        --help|-h)
            echo-white "Usage: zeltro new folder <name> [--one-off] [--json-output]"
            echo-white ""
            echo-white "A folder project: a folder plus an AI session, with no container, framework,"
            echo-white "database or address. For scripts, scrapers, documents, data clean-ups, CLI tools"
            echo-white "and bots. To use a folder you already have, see 'zeltro add'."
            exit 0 ;;
        -*) shift ;;
        *) [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$1"; shift ;;
    esac
done

fail() { # <code> <message>
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c 'import json,sys; print(json.dumps({"action":"new_project","kind":"folder","status":"error","error":sys.argv[1],"message":sys.argv[2]}))' "$1" "$2"
    else
        echo-red "$2"
    fi
    exit 1
}

[ -n "$PROJECT_NAME" ] || fail "missing_name" "Give the project a name: zeltro new folder <name>"
PROJECT_NAME="$(zeltro_clean_project_name "$PROJECT_NAME")"
[ -n "$PROJECT_NAME" ] || fail "bad_name" "Project names use letters, numbers, dashes and underscores."
zeltro_project_name_taken "$PROJECT_NAME" && fail "name_taken" "There is already a project called '$PROJECT_NAME'."

PROJECT_DIR="$PROJECTS_DIR_PATH/$PROJECT_NAME"
mkdir -p "$PROJECTS_DIR_PATH"
mkdir "$PROJECT_DIR"
trap '[ $? -eq 0 ] || { rm -rf "$PROJECT_DIR"; zeltro_folder_py forget "$PROJECT_NAME" >/dev/null 2>&1; }' EXIT

REAL_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
zeltro_folder_py create "$PROJECT_NAME" created "$REAL_DIR"

cd "$PROJECT_DIR"
printf '.env\n.env.*\n!.env.example\n' > .gitignore
zeltro_write_folder_agents_md "$PROJECT_DIR" "$PROJECT_NAME"
if command -v git >/dev/null 2>&1; then
    git init -q 2>/dev/null || true
    git add . >/dev/null 2>&1 || true
    git commit -q -m "New folder project" >/dev/null 2>&1 || true
fi

# Zeltro made this folder, so the first AI session can skip the agent's
# "do you trust this folder?" question.
zeltro_trust_project_for_agents "$PROJECT_DIR" >/dev/null 2>&1 || true

if [[ "$JSON_OUTPUT" == "1" ]]; then
    python3 -c 'import json,sys; print(json.dumps({"action":"new_project","project_name":sys.argv[1],"kind":"folder","origin":"created","path":sys.argv[2],"status":"success"}))' "$PROJECT_NAME" "$REAL_DIR"
    exit 0
fi

echo-green "Folder project '$PROJECT_NAME' created: $REAL_DIR"
echo-white "No container or address: your AI agent works directly in the folder."

ai_handoff "$PROJECT_NAME"
cd "$ORIG_DIR"
