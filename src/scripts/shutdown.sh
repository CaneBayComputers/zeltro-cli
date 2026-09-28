#!/bin/bash

set -e

# Store current working directory (should be projects directory)
PROJECTS_DIR=$(pwd)

# Get the directory of this script, handling both direct execution and sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
else
    # Script is being executed directly
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
fi

cd "$SCRIPT_DIR/.."
DEV_DIR=$(pwd)

source scripts/pre_check.sh

# Return to projects directory
cd "$PROJECTS_DIR"

echo-return; echo-return


# Initialize variables. STOP_ALL is set to 1 by the 'zeltro down-all' dispatch
# (via the environment), not by a user-facing flag.
PROJECT_NAME=""
STOP_ALL="${STOP_ALL:-0}"
JSON_OUTPUT="${JSON_OUTPUT:-}"
NO_COLOR="${NO_COLOR:-}"

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json-output)
            JSON_OUTPUT=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --no-colors)
            NO_COLOR=1
            shift
            ;;
        --help)
            echo-white "Usage: zeltro down [OPTIONS] <project_name>"
            echo-white "Shut down a project container. Shared services keep running."
            echo-white ""
            echo-white "Arguments:"
            echo-white "  project_name      Project to stop (required; use 'zeltro down-all' for every project)"
            echo-white ""
            echo-white "Options:"
            echo-white "  --json-output     Output results in JSON format"
            echo-white "  --debug           Enable debug logging to /tmp/zeltro-cli-debug.log"
            echo-white "  --no-colors       Disable colored output"
            echo-white "  --help            Show this help message"
            echo-white ""
            echo-white "Use 'zeltro stop-services' separately to stop the shared services."
            exit 0
            ;;
        -*)
            error "Unknown option: $1. Use --help for usage information"
            ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            else
                error "Too many arguments"
            fi
            shift
            ;;
    esac
done

if [[ "$STOP_ALL" == "1" && -n "$PROJECT_NAME" ]]; then
    error "Cannot combine 'zeltro down-all' with a project name."
fi

# A project name is required (or 'zeltro down-all', which sets STOP_ALL).
if [[ -z "$PROJECT_NAME" && "$STOP_ALL" == "0" ]]; then
    echo-red "No project specified."
    echo-white "Usage: zeltro down <project>   # stop one project"
    echo-white "       zeltro down-all         # stop every project"
    exit 1
fi

# Initialize debug logging
debug "Script started: shutdown.sh with args: $ORIGINAL_ARGS"


# Functions
# Docker handles all networking - no iptables rules needed

shutdown_project() {
    local PROJECT_NAME="$1"
    local PROJECT_FOLDER="$2"
    
    # Check if project folder exists
    if [ ! -d "$PROJECT_FOLDER" ]; then
        error "Project folder does not exist: $PROJECT_FOLDER"
    fi
    
    # Check for docker-compose.yaml file
    COMPOSE_FILE="$PROJECT_FOLDER/docker-compose.yaml"
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo-return; echo-yellow "No docker-compose.yaml found in project: $PROJECT_NAME"
        return 1
    fi
    
    # Check if it's a Zeltro project
    COMPOSE_TYPE=$(check_docker_compose_type "$COMPOSE_FILE")
    
    if [ "$COMPOSE_TYPE" != "zeltro-project" ]; then
        echo-return; echo-yellow "Project $PROJECT_NAME is not a Zeltro project"
        return 1
    fi
    
    # Check if container is running and shut it down
    if [ "$(docker ps -q -f name=$PROJECT_NAME)" ]; then
        echo-return; echo-cyan "Shutting down $PROJECT_NAME ..."; echo-white; echo-return
        
        # Save current directory to return to it after dockerdown
        CURRENT_DIR=$(pwd)
        cd "$PROJECT_FOLDER"
        dockerdown
        cd "$CURRENT_DIR"

        # Re-stamp on stop: the value then reads as "last time this was
        # running", not "last time somebody started it".
        record_last_on "$PROJECT_NAME" || true
        
        echo-green "Successfully shut down $PROJECT_NAME!"; echo-white; echo-return
        
        divider
        return 0
    else
        echo-return; echo-yellow "Container $PROJECT_NAME is not running!"; echo-white; echo-return
        return 1
    fi
}



#######################################################
# Main
#######################################################

# Shut down Docker containers
if [ -z "$PROJECT_NAME" ]; then

    # Iterate through each folder in the projects directory (PROJECTS_DIR_PATH set by pre_check)
    for PROJECT_FOLDER in "$PROJECTS_DIR_PATH"/*; do

        # Skip if not a directory
        if [ ! -d "$PROJECT_FOLDER" ]; then
            continue
        fi

        # Get the project name (folder name)
        PROJECT_FOLDER_NAME=$(basename "$PROJECT_FOLDER")

        # Use the reusable shutdown function (but don't exit on errors in loop)
        shutdown_project "$PROJECT_FOLDER_NAME" "$PROJECT_FOLDER" || true
    done

    # Note: shared services are intentionally left running. Use 'zeltro stop-services'
    # explicitly when you want to stop them.

else
    # Shutdown specific project (PROJECTS_DIR_PATH set by pre_check)
    PROJECT_FOLDER="$PROJECTS_DIR_PATH/$PROJECT_NAME"
    
    # Use the reusable shutdown function
    shutdown_project "$PROJECT_NAME" "$PROJECT_FOLDER"

fi

# Final output
if [[ "$JSON_OUTPUT" == "1" ]]; then

    if [ -n "$PROJECT_NAME" ]; then
        echo "{\"action\": \"shutdown\", \"target\": \"project\", \"project_name\": \"$PROJECT_NAME\", \"status\": \"success\"}"
    else
        echo "{\"action\": \"shutdown\", \"target\": \"all_projects\", \"status\": \"success\"}"
    fi

else
    echo-return; echo-green "Project containers shut down. (Shared services are still running — use 'zeltro stop-services' to stop them.)"; echo-white; echo-return
fi

