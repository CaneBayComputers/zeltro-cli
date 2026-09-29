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

source scripts/pre_check.sh

# Initialize variables
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
        --no-colors)
            NO_COLOR=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --help)
            echo-white "Usage: ${ZELTRO_CMD:-$0} [OPTIONS]"
            echo-white "Start Zeltro shared services"
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
            error "Unexpected argument: $1. Use --help for usage information"
            ;;
    esac
done

echo-return; echo-return

# Initialize debug logging
debug "Script started: start_services.sh with args: $ORIGINAL_ARGS"

# Main
source "$DEV_DIR/scripts/pre_check.sh"

# Start whatever is ENABLED. Every service is profile-gated now, so a machine
# with nothing enabled has nothing to start — and that is a legitimate state, not
# an error. `docker compose up` with no profiles selected exits non-zero with
# "no service selected", which used to abort project creation on a fresh box.
# Redis, Memcached and Mailhog carry no profile, so they always start. Databases
# and admin UIs are profile-gated and only join once something asks for them.
#
# check-mariadb is no longer the right probe: MariaDB not running is normal on a
# Postgres-only machine. Check the always-on trio plus whatever is enabled.
zeltro_fix_postgres_data_volume || true

_services_up=1
for _svc in redis memcached mailhog ${OPTIONAL_SERVICES:-}; do
    _cname="$(zeltro_service_container "$_svc")"
    docker container inspect -f '{{.State.Running}}' "$_cname" 2>/dev/null | grep -q true || _services_up=0
done

if [ "$_services_up" = "0" ]; then
    echo-cyan "Starting services ..."; echo-white
    cd /etc/zeltro-cli
    dockerup
    cd "$DEV_DIR"
fi

# JSON output for service start
if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "{\"action\": \"start_services\", \"status\": \"success\"}"
else
    echo-green "Services are running!"; echo-white
fi

cd "$ORIG_DIR"
