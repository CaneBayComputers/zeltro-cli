#!/bin/bash

# In the Startup Applications manager enter this command to run this script to start up repos:
# gnome-terminal -- bash -c "/home/dev/repos/cbc-development-setup/startup.sh; exec bash"

set -e


# Store the current directory (should be projects directory)
PROJECTS_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"

cd ..

DEV_DIR=$(pwd)

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

source scripts/pre_check.sh

# Initialize debug logging
debug "Script started: startup.sh with args: $ORIGINAL_ARGS"
debug "PROJECTS_DIR: $PROJECTS_DIR"

# Return to projects directory for project operations
cd "$PROJECTS_DIR"
debug "Changed to projects directory: $(pwd)"


# Initialize variables. START_ALL is set to 1 by the 'zeltro up-all' dispatch
# (via the environment), not by a user-facing flag.
PROJECT_NAME=""
START_ALL="${START_ALL:-0}"
JSON_OUTPUT="${JSON_OUTPUT:-}"
NO_COLOR="${NO_COLOR:-}"

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --json-output)
            JSON_OUTPUT=1
            shift
            ;;
        --no-colors)
            NO_COLOR=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --help)
            echo-white "Usage: ${ZELTRO_CMD:-$0} [OPTIONS] <project_name>"
            echo-white "Start a project container (and shared services if not running)"
            echo-white ""
            echo-white "Arguments:"
            echo-white "  project_name      Project to start (required; use 'zeltro up-all' for every project)"
            echo-white ""
            echo-white "Options:"
            echo-white "  --json-output     Output results in JSON format"
            echo-white "  --no-colors       Disable colored output"
            echo-white "  --debug           Enable debug logging to /tmp/zeltro-cli-debug.log"
            echo-white "  --help            Show this help message"
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

if [[ "$START_ALL" == "1" && -n "$PROJECT_NAME" ]]; then
    error "Cannot combine 'zeltro up-all' with a project name."
fi

# A folder project has nothing to start: no container, no shared services.
if [[ -n "$PROJECT_NAME" ]] && zeltro_project_is_folder "$PROJECT_NAME"; then
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        echo "{\"action\": \"startup\", \"status\": \"skipped\", \"reason\": \"folder_project\", \"project\": \"$PROJECT_NAME\", \"kind\": \"folder\"}"
    else
        echo-white "'$PROJECT_NAME' is a folder project: there's nothing to start."
    fi
    exit 0
fi


# Functions
start_project() {

  PROJECT_FOLDER_NAME=$1
  debug "start_project called for: $PROJECT_FOLDER_NAME"

  echo-return; echo-cyan "Starting up $PROJECT_FOLDER_NAME ...";

  if ! [ -d "$PROJECT_FOLDER_NAME" ]; then
    debug "Project folder not found: $PROJECT_FOLDER_NAME"
    error "Project folder not found!"

  fi

  debug "Changing to project directory: $PROJECT_FOLDER_NAME"
  cd "$PROJECT_FOLDER_NAME"
  debug "Current directory: $(pwd)"

  # Check for Zeltro project docker-compose.yaml
  debug "Checking docker-compose.yaml type"
  local compose_type=$(check_docker_compose_type "docker-compose.yaml")
  debug "Docker compose type: $compose_type"
  
  case "$compose_type" in
      "none")
          echo-white "Run 'zeltro setup $PROJECT_FOLDER_NAME' to configure this project for Zeltro."
          echo-yellow "$PROJECT_FOLDER_NAME is not configured for Zeltro. Run: zeltro setup $PROJECT_FOLDER_NAME"
          cd ..
          return 1
          ;;
      "non-zeltro")
          echo-white "Run 'zeltro setup $PROJECT_FOLDER_NAME --overwrite-docker-compose' to configure for Zeltro."
          echo-yellow "$PROJECT_FOLDER_NAME has non-Zeltro docker-compose.yaml. Run: zeltro setup $PROJECT_FOLDER_NAME --overwrite-docker-compose"
          cd ..
          return 1
          ;;
      "zeltro-project")
          # Good to go - continue with startup
          ;;
  esac

  # Bring up whatever this project actually talks to. Services are profile-gated
  # and nothing is running by default, so this is what makes a project startable
  # on a machine that has never needed, say, Postgres before.
  ensure_services_for_project "$PROJECT_FOLDER_NAME" || true

  # Already up? Then this call has nothing to do. Reported by the GUI session:
  # `zeltro resume` on a running project ran a full start, which costs seconds
  # and can trigger a sudo prompt to change nothing — so "continue my AI
  # conversation" read as "restarted my project and asked for my password".
  # Every caller benefits, not just resume.
  if docker container inspect -f '{{.State.Running}}' "$PROJECT_FOLDER_NAME" 2>/dev/null | grep -q true; then
      cd ..
      record_last_on "$PROJECT_FOLDER_NAME" || true
      echo-green "Project $PROJECT_FOLDER_NAME is already running."; echo-return
      return 0
  fi

  # Not running, so a newer base image can be picked up here without
  # recreating anything mid-session: compose up replaces the container when
  # its image changed.
  zeltro_refresh_base_images docker-compose.yaml

  dockerup

  cd ..

  # Stamp when this project was last up, for the GUI's "last running" sort.
  # Best-effort: never let a metadata write affect whether a project starts.
  record_last_on "$PROJECT_FOLDER_NAME" || true

  echo-green "Project $PROJECT_FOLDER_NAME started successfully!"; echo-return
}


# Main
# Build start_services options
START_SERVICES_OPTIONS=""
if [[ "$JSON_OUTPUT" == "1" ]]; then
    START_SERVICES_OPTIONS="$START_SERVICES_OPTIONS --json-output"
fi
if [[ "$NO_COLOR" == "1" ]]; then
    START_SERVICES_OPTIONS="$START_SERVICES_OPTIONS --no-colors"
fi
if [[ "$DEBUG" == "1" ]]; then
    START_SERVICES_OPTIONS="$START_SERVICES_OPTIONS --debug"
fi

# If a single named project is already running, its shared services are
# necessarily up too — starting them again is pure cost. Skipping this is what
# removes the spurious sudo prompt, not just the compose call below.
PROJECT_ALREADY_RUNNING=0
if [[ -n "$PROJECT_NAME" && "$START_ALL" == "0" ]]; then
    if docker container inspect -f '{{.State.Running}}' "$PROJECT_NAME" 2>/dev/null | grep -q true; then
        PROJECT_ALREADY_RUNNING=1
    fi
fi

# Capture JSON output from start_services.sh if in JSON mode
if [[ "$PROJECT_ALREADY_RUNNING" == "1" ]]; then
    debug "Project $PROJECT_NAME already running; skipping shared-service startup"
elif [[ "$JSON_OUTPUT" == "1" ]]; then
    START_SERVICES_OUTPUT=$(source "$DEV_DIR/scripts/start_services.sh" $START_SERVICES_OPTIONS 2>&1)
    START_SERVICES_EXIT_CODE=$?
    if [ $START_SERVICES_EXIT_CODE -ne 0 ]; then
        echo "$START_SERVICES_OUTPUT"
        exit $START_SERVICES_EXIT_CODE
    fi
else
    source "$DEV_DIR/scripts/start_services.sh" $START_SERVICES_OPTIONS
fi

# Ensure we're back in the projects directory after sourcing other scripts
cd "$PROJECTS_DIR_PATH"

# A project name is required (or 'zeltro up-all', which sets START_ALL). Shared
# services have already been started above — the useful, non-destructive part.
if [[ -z "$PROJECT_NAME" && "$START_ALL" == "0" ]]; then
    echo-return
    echo-red "No project specified."
    echo-white "Usage: zeltro up <project>     # start one project"
    echo-white "       zeltro up-all           # start every project"
    exit 1
fi

# Decide which projects to start.
# Note: shared services have already been started above regardless of branch.
if [[ -n "$PROJECT_NAME" ]]; then
    # Refuse a disabled project rather than starting it. Disabling is an explicit
    # act, so silently overriding it here would make the state meaningless.
    if zeltro_project_is_disabled "$PROJECT_NAME"; then
        echo-return
        echo-yellow "Project '$PROJECT_NAME' is disabled and was not started."
        echo-white  "Re-enable it first:"
        echo-white  "  zeltro enable $PROJECT_NAME"
        echo-return
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            echo "{\"action\": \"startup\", \"status\": \"error\", \"error\": \"project_disabled\", \"project\": \"$PROJECT_NAME\", \"details\": \"Project is disabled. Run 'zeltro enable $PROJECT_NAME' first.\"}"
        fi
        exit 1
    fi
    debug "Starting specific project: $PROJECT_NAME"
    if start_project "$PROJECT_NAME"; then true; fi

elif [[ "$START_ALL" == "1" ]]; then
    debug "Starting all projects (up-all)"

    # Only iterate directories; avoid literal '*' / '*/' with nullglob.
    # Skip files and any directory whose name starts with a dot.
    shopt -s nullglob

    for PROJECT_FOLDER_NAME in */ ; do
        PROJECT_FOLDER_NAME=${PROJECT_FOLDER_NAME%/}

        # Skip non-directories and hidden directories
        [[ -d "$PROJECT_FOLDER_NAME" ]] || continue
        [[ "$PROJECT_FOLDER_NAME" == .* ]] && continue
        zeltro_project_is_folder "$PROJECT_FOLDER_NAME" && continue

        # A disabled project is parked: up-all must pass over it. Announced
        # rather than silent, so "why didn't that one start" is answerable
        # without going and reading the compose file.
        if zeltro_project_is_disabled "$PROJECT_FOLDER_NAME"; then
            echo-yellow "Skipping '$PROJECT_FOLDER_NAME' — disabled."
            continue
        fi

        debug "Attempting to start project: $PROJECT_FOLDER_NAME"
        start_project "$PROJECT_FOLDER_NAME" || true

    done

    shopt -u nullglob
fi


# Docker handles all networking automatically

# Build status options
STATUS_OPTIONS=""
if [[ "$JSON_OUTPUT" == "1" ]]; then
    STATUS_OPTIONS="$STATUS_OPTIONS --json-output"
fi
if [[ "$NO_COLOR" == "1" ]]; then
    STATUS_OPTIONS="$STATUS_OPTIONS --no-colors"
fi

# Allow containers time to finish booting before running status checks.
#
# Skipped when nothing was started: the GUI session traced 12.00s of a 12.58s
# no-op `zeltro up` to exactly this line. The early return above exits the
# per-project function, but this sits in the main body and ran regardless — so a
# command that did nothing still waited 12 seconds for containers that had been
# up for hours.
if [[ "$PROJECT_ALREADY_RUNNING" != "1" ]]; then
    sleep 12
fi

# Containers are recreated from their base image on every `up`, so anything pip
# installed INTO the container filesystem during setup is gone — only the
# bind-mounted project directory survives. The cbc:nginx-python3 image bakes in
# gunicorn/uvicorn/fastapi, so FastAPI projects restart fine, but any project
# with dependencies outside that set (Flask, and anything else in
# requirements.txt) comes back to a 502 because its app can't import.
#
# Reinstall requirements when the container is missing them. pip is a fast
# no-op once satisfied, and this only runs for projects that actually ship a
# requirements.txt.
if [ -n "$PROJECT_NAME" ] && [ -f "$PROJECTS_DIR_PATH/$PROJECT_NAME/requirements.txt" ]; then
    if docker exec "$PROJECT_NAME" bash -c 'command -v pip3 >/dev/null 2>&1' 2>/dev/null; then
        if ! docker exec "$PROJECT_NAME" bash -c \
            'cd /usr/share/nginx/html && pip3 install --break-system-packages --quiet --disable-pip-version-check -r requirements.txt' >/dev/null 2>&1; then
            echo-yellow "Warning: could not reinstall Python dependencies in $PROJECT_NAME."
        else
            # Restart the app so it picks up freshly-installed packages.
            docker exec "$PROJECT_NAME" supervisorctl restart python-app >/dev/null 2>&1 || true
        fi
    fi
fi

# The container is up but the app inside may still be binding its port (or
# finishing a dependency install). Let the HTTP check retry instead of
# reporting a false FAILED. Only affects freshly-started projects — plain
# `zeltro status` keeps its single fast attempt.
export HTTP_WAIT_SECS="${HTTP_WAIT_SECS:-45}"

# Show status to confirm successful startup
if [ -n "$PROJECT_NAME" ]; then
    source "$DEV_DIR/scripts/status.sh" $PROJECT_NAME $STATUS_OPTIONS
else
    source "$DEV_DIR/scripts/status.sh" $STATUS_OPTIONS
fi
