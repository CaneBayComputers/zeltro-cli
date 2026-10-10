#!/bin/bash

# Disable or enable a project.
#
# A disabled project is PARKED, not removed: it is stopped, skipped by `up-all`,
# refused by `up`, and hidden from the GUI's default view. Its files, database
# and volumes are untouched — the only change is a `status` key in the project's
# own x-metadata, which travels with the project.
#
# Deliberately NOT a separate state file or registry. Keeping it in the compose
# metadata means the GUI reads it exactly the way it already reads emoji, display
# name and last_on, and a project carried to another machine keeps its state.
#
# Removal is still allowed on a disabled project — parking something is often the
# step before deleting it, and forcing an enable first would be busywork.

set -e

ORIG_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

ACTION="disable"          # set by the dispatcher via $ZELTRO_TOGGLE_ACTION
[ -n "${ZELTRO_TOGGLE_ACTION:-}" ] && ACTION="$ZELTRO_TOGGLE_ACTION"

PROJECT_NAME=""
JSON_OUTPUT="${JSON_OUTPUT:-}"

usage() {
    if [ "$ACTION" = "enable" ]; then
        echo-white "Usage: ${ZELTRO_CMD:-$0} <project> [--json-output]"
        echo-white "Re-enable a disabled project so it can be started again."
    else
        echo-white "Usage: ${ZELTRO_CMD:-$0} <project> [--json-output]"
        echo-white "Stop a project and park it: hidden from 'zeltro up-all' and from the"
        echo-white "GUI's default view, and refused by 'zeltro up' until re-enabled."
        echo-white ""
        echo-white "Nothing is deleted — files, database and volumes are left alone."
        echo-white "Re-enable with: zeltro enable <project>"
    fi
    echo-white ""
    echo-white "Options:"
    echo-white "  --json-output    Machine-readable result"
    echo-white "  --help           Show this message"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --json-output) JSON_OUTPUT=1; export JSON_OUTPUT; shift ;;
        --no-colors)   NO_COLOR=1; export NO_COLOR; shift ;;
        --help|-h)     usage; exit 0 ;;
        -*)            error "Unknown option: $1" ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then PROJECT_NAME="$1"; else error "Too many arguments"; fi
            shift ;;
    esac
done

if [ -z "$PROJECT_NAME" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project name is required"
    error "Error: project name is required. Usage: zeltro $ACTION <project>"
fi

# Folder projects have nothing to park: no container for up-all to start.
if zeltro_project_is_folder "$PROJECT_NAME"; then
    _act="${ZELTRO_TOGGLE_ACTION:-disable}"
    [[ "$JSON_OUTPUT" == "1" ]] && echo "{\"action\": \"$_act\", \"status\": \"skipped\", \"reason\": \"folder_project\", \"project\": \"$PROJECT_NAME\", \"kind\": \"folder\", \"changed\": false}"
    [[ "$JSON_OUTPUT" == "1" ]] || echo-white "'$PROJECT_NAME' is a folder project: there's nothing to $_act."
    exit 0
fi

PROJECT_DIR="$PROJECTS_DIR_PATH/$PROJECT_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project '$PROJECT_NAME' not found"
    error "Project '$PROJECT_NAME' not found in $PROJECTS_DIR_PATH."
fi

COMPOSE_FILE="$(zeltro_project_compose "$PROJECT_NAME")"
if [ -z "$COMPOSE_FILE" ]; then
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "project '$PROJECT_NAME' has no docker-compose file; run 'zeltro setup $PROJECT_NAME' first"
    error "Project '$PROJECT_NAME' has no docker-compose file. Run: zeltro setup $PROJECT_NAME"
fi

CURRENT="$(zeltro_project_status "$PROJECT_NAME")"

if [ "$ACTION" = "enable" ]; then
    if [ "$CURRENT" != "disabled" ]; then
        echo-cyan "Project '$PROJECT_NAME' is already enabled."
        [[ "$JSON_OUTPUT" == "1" ]] && echo "{\"action\": \"enable\", \"status\": \"success\", \"project\": \"$PROJECT_NAME\", \"project_status\": \"enabled\", \"changed\": false}"
        cd "$ORIG_DIR"; exit 0
    fi
    set_x_metadata_key "$COMPOSE_FILE" "$PROJECT_NAME" "status" "enabled" || {
        [[ "$JSON_OUTPUT" == "1" ]] && json_error "could not write project metadata"
        error "Could not update project metadata."
    }
    echo-green "Project '$PROJECT_NAME' enabled."
    echo-white "Start it with: zeltro up $PROJECT_NAME"
    [[ "$JSON_OUTPUT" == "1" ]] && echo "{\"action\": \"enable\", \"status\": \"success\", \"project\": \"$PROJECT_NAME\", \"project_status\": \"enabled\", \"changed\": true}"
    cd "$ORIG_DIR"; exit 0
fi

# --- disable ---------------------------------------------------------------
if [ "$CURRENT" = "disabled" ]; then
    echo-cyan "Project '$PROJECT_NAME' is already disabled."
    [[ "$JSON_OUTPUT" == "1" ]] && echo "{\"action\": \"disable\", \"status\": \"success\", \"project\": \"$PROJECT_NAME\", \"project_status\": \"disabled\", \"changed\": false}"
    cd "$ORIG_DIR"; exit 0
fi

# Stop it first. A disabled project that is still running would contradict its
# own state, and the metadata write must not be what stops it.
if docker container inspect -f '{{.State.Running}}' "$PROJECT_NAME" 2>/dev/null | grep -q true; then
    echo-cyan "Stopping '$PROJECT_NAME' ..."
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        (cd "$PROJECTS_DIR_PATH" && "$DEV_DIR/scripts/shutdown.sh" "$PROJECT_NAME" >/dev/null 2>&1) || true
    else
        (cd "$PROJECTS_DIR_PATH" && "$DEV_DIR/scripts/shutdown.sh" "$PROJECT_NAME") || true
    fi
fi

set_x_metadata_key "$COMPOSE_FILE" "$PROJECT_NAME" "status" "disabled" || {
    [[ "$JSON_OUTPUT" == "1" ]] && json_error "could not write project metadata"
    error "Could not update project metadata."
}

echo-green "Project '$PROJECT_NAME' disabled."
echo-white "It is stopped, skipped by 'zeltro up-all', and hidden in the GUI."
echo-white "Nothing was deleted. Re-enable with: zeltro enable $PROJECT_NAME"
[[ "$JSON_OUTPUT" == "1" ]] && echo "{\"action\": \"disable\", \"status\": \"success\", \"project\": \"$PROJECT_NAME\", \"project_status\": \"disabled\", \"changed\": true}"

cd "$ORIG_DIR"
