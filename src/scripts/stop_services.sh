#!/bin/bash

set -e

ORIG_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"

cd ..

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
        --debug)
            DEBUG=1
            shift
            ;;
        --no-colors)
            NO_COLOR=1
            shift
            ;;
        --help)
            echo-white "Usage: ${ZELTRO_CMD:-$0} [OPTIONS]"
            echo-white "Stop Zeltro shared services"
            echo-white ""
            echo-white "Options:"
            echo-white "  --json-output     Output results in JSON format"
            echo-white "  --debug           Enable debug logging to /tmp/zeltro-cli-debug.log"
            echo-white "  --no-colors       Disable colored output"
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

# Initialize debug logging
debug "Script started: stop_services.sh with args: $ORIGINAL_ARGS"



# Main
# Stop CBC stack services
if check-mariadb; then

    echo-cyan "Stopping services ..."; echo-white

    cd /etc/zeltro-cli

    # Before `compose down` removes the container and orphans its anonymous volume.
    zeltro_fix_postgres_data_volume || true

    dockerdown

    cd ..

else

    echo-yellow "Services are already stopped."; echo-white

fi

# JSON output for service stop
if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "{\"action\": \"stop_services\", \"status\": \"success\"}"
else
    echo-green "Services stopped!"; echo-white
fi

cd "$ORIG_DIR"
