#!/bin/bash

set -e


ORIG_DIR=$(pwd)

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

source scripts/functions.sh

# Do not run as root
if [[ "$(whoami)" == "root" ]]; then
  error "Do NOT run with sudo!"
fi


# Check if this environment is configured
if ! [ -f /etc/zeltro-cli/.env ]; then
  error "Development environment has not been configured! Run: zeltro configure" 0
fi

# Source the environment file
source /etc/zeltro-cli/.env
# Re-sourcing reset any AI_* the caller overrode for this run; apply them again.
zeltro_apply_ai_overrides

# Check Docker is accessible — catches both "not in docker group yet" and "Docker not running"
if command -v docker >/dev/null 2>&1; then
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not accessible. If you just installed Zeltro, your Docker group permissions may not have taken effect yet. SSH users: reconnect. Desktop users: log out and back in, or reboot if that does not work. If Docker is already set up, make sure the Docker service is running." 0
    fi
fi

# Set up projects directory path and validate it exists
PROJECTS_DIR_PATH=$(get_projects_dir)
if [ ! -d "$PROJECTS_DIR_PATH" ]; then
    error "Projects directory does not exist: $PROJECTS_DIR_PATH"
fi

# Export for use by other scripts
export PROJECTS_DIR_PATH

cd "$ORIG_DIR"