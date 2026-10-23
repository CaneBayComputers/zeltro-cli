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

# Report a port another container or program holds, by name, and stop here:
# compose would only say "port is already allocated". Nothing is stopped for
# the user; their old containers may still serve something.
_report_port_conflicts() { # $1 = conflict lines from zeltro_service_port_conflicts
    local port holder names="" podium="" msg="" lines="" json_items=""
    while IFS="$(printf '\t')" read -r port holder; do
        [ -n "$port" ] || continue
        if [ "$holder" = "-" ]; then
            lines="$lines  Port $port is in use by a program outside Docker.\n"
        else
            lines="$lines  Port $port is held by the container $holder.\n"
            names="$names${names:+ }$holder"
            case "$holder" in podium-*) podium=1 ;; esac
        fi
        json_items="$json_items${json_items:+,}{\"port\": $port, \"container\": \"$( [ "$holder" = "-" ] || echo "$holder")\"}"
    done <<EOF_RPC
$1
EOF_RPC
    msg="Zeltro's shared services can't start: a port they need is taken."
    local fix=""
    if [ -n "$podium" ]; then
        local pp pn pd
        pp=$(zeltro_podium_projects); pn=$(printf '%s' "$pp" | cut -f 1); pd=$(printf '%s' "$pp" | cut -f 2)
        msg="$msg It is held by an older Podium install (Zeltro's previous name), whose shared services are still running."
        if [ "$pn" -gt 0 ] 2>/dev/null; then
            msg="$msg Podium still has $pn project(s) in $pd, which use those services; stopping them stops those projects' databases."
        fi
    fi
    if [ -n "$names" ]; then
        fix="docker update --restart=no $names && docker stop $names"
        msg="$msg Stop it (its data is kept; 'docker start' brings it back), then run 'zeltro start-services' again: $fix"
    else
        msg="$msg Stop the program using that port, then run 'zeltro start-services' again."
    fi
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        python3 -c 'import json,sys; print(json.dumps({"action": "start_services", "status": "error", "error": "port_conflict", "conflicts": json.loads("[" + sys.argv[1] + "]"), "podium": sys.argv[2] == "1", "fix": sys.argv[3], "message": sys.argv[4]}))' \
            "$json_items" "$podium" "$fix" "$msg"
    else
        echo-red "Zeltro's shared services can't start: a port they need is taken."
        printf "$lines"
        local why="${msg#*taken. }"
        if [ -n "$fix" ]; then
            echo-yellow "${why%%: docker update*}:"
            echo-white "  $fix"
        else
            echo-yellow "$why"
        fi
    fi
    cd "$ORIG_DIR"
    exit 1
}

if [ "$_services_up" = "0" ]; then
    _conflicts="$(zeltro_service_port_conflicts)"
    [ -z "$_conflicts" ] || _report_port_conflicts "$_conflicts"
    echo-cyan "Starting services ..."; echo-white
    cd /etc/zeltro-cli
    if ! dockerup; then
        cd "$DEV_DIR"
        # Taken between the check and the start, or a port the check can't see.
        _conflicts="$(zeltro_service_port_conflicts)"
        [ -z "$_conflicts" ] || _report_port_conflicts "$_conflicts"
        if [[ "$JSON_OUTPUT" == "1" ]]; then
            python3 -c 'import json,sys; print(json.dumps({"action": "start_services", "status": "error", "error": "start_failed", "message": sys.argv[1]}))' \
                "$(tail -n 5 /tmp/zeltro-docker-progress.log 2>/dev/null | tr '\n' ' ')"
        else
            echo-red "Zeltro's shared services failed to start (see Docker's message above)."
        fi
        cd "$ORIG_DIR"
        exit 1
    fi
    cd "$DEV_DIR"
fi

# JSON output for service start
if [[ "$JSON_OUTPUT" == "1" ]]; then
    echo "{\"action\": \"start_services\", \"status\": \"success\"}"
else
    echo-green "Services are running!"; echo-white
fi

cd "$ORIG_DIR"
