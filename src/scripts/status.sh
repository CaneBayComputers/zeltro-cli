#!/bin/bash

set -e

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

# Function to display usage
usage() {
    echo-white "Usage: ${ZELTRO_CMD:-$0} [project_name] [options]"
    echo-white "Shows status of running Docker projects"
    echo-white ""
    echo-white "Arguments:"
    echo-white "  project_name     Name of specific project to check (optional)"
    echo-white ""
    echo-white "Options:"
    echo-white "  --all            Show every project (default: only active/running projects)"
    echo-white "  --running        Only show projects whose container is running (the default)"
    echo-white "  --json-output    Output JSON responses (for programmatic use)"
    echo-white "  --debug          Enable debug logging to /tmp/zeltro-cli-debug.log"
    echo-white "  --no-colors      Disable colored output"
    echo-white "  --help           Show this help message"
    echo-white ""
    echo-white "Examples:"
    echo-white "  ${ZELTRO_CMD:-$0}                    # Show only active (running) projects"
    echo-white "  ${ZELTRO_CMD:-$0} --all              # Show every project"
    echo-white "  ${ZELTRO_CMD:-$0} my-project         # Show specific project (shown even if stopped)"
    echo-white "  ${ZELTRO_CMD:-$0} --json-output      # JSON output for active projects"
}

# Initialize variables
PROJECT_NAME=""
# Project listing defaults to active (running) projects only; --all shows every project.
RUNNING_ONLY=1
JSON_OUTPUT="${JSON_OUTPUT:-}"
NO_COLOR="${NO_COLOR:-}"

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            RUNNING_ONLY=0
            shift
            ;;
        --running)
            RUNNING_ONLY=1
            shift
            ;;
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
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
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

# Initialize debug logging
debug "Script started: status.sh with args: $ORIGINAL_ARGS"

RUNNING_SITES=""

RUNNING_INTERNAL=""

RUNNING_EXTERNAL=""

# Get LAN IP (cross-platform)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - use route to find default interface IP
    LAN_IP=$(route get default | grep interface | awk '{print $2}' | xargs ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
else
    # Linux. `hostname -I` comes from inetutils/net-tools, which a minimal Arch
    # install does not have — there `hostname` is a different binary with no -I
    # flag, so this produced an EMPTY string and the status screen printed
    # "LAN ACCESS: http://:246", handing the user a dead URL. It failed silently
    # because the empty result is indistinguishable from "no LAN IP".
    #
    # `ip` is in iproute2, which is present on any machine that can run Docker,
    # so it is the more reliable primary. hostname -I stays as a fallback.
    # Ask the routing table which local address is used to reach the network.
    # This is the actual LAN IP by definition, and unlike filtering by address
    # range it cannot mistake a Docker bridge for the LAN, or — the reason not to
    # filter — mistake a real 10.0.0.0/8 LAN for a Docker network. No traffic is
    # sent; the lookup is local.
    LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null \
             | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i+1); exit }}')

    # Fallbacks: first global address, then hostname -I where that exists.
    if [ -z "$LAN_IP" ]; then
        LAN_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    fi
    if [ -z "$LAN_IP" ] && command -v hostname >/dev/null 2>&1; then
        LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
fi

# Docker handles port mapping automatically

# /etc/hosts is no longer read or written. Addresses come from each project's
# own compose file, which is what actually claims them.

RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}")


# Functions
service_running() {
    local name="$1"
    echo "$RUNNING_CONTAINERS" | grep -q "^${name}$"
}

# A shared service's IP on the Docker network. Probes used the container NAME,
# which only resolved on the host through /etc/hosts entries Zeltro no longer
# writes -- so every healthy service printed "PING ... FAILED". The IP is what a
# host-side probe can actually reach. Falls back to the name if inspect fails.
service_addr() {
    local ip
    ip=$(docker container inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" 2>/dev/null | awk '{print $1}')
    if [ -n "$ip" ]; then printf '%s' "$ip"; else printf '%s' "$1"; fi
}

ping_host() {
    local hostname="$1"
    local resolved_ip
    if [[ "$hostname" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        resolved_ip="$hostname"
    elif command -v getent >/dev/null 2>&1; then
        resolved_ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -n 1)
    elif command -v host >/dev/null 2>&1; then
        resolved_ip=$(host "$hostname" 2>/dev/null | awk '/has address/ {print $4; exit}')
    else
        resolved_ip=""
    fi

    # The fallback exists because `-W` is not portable (Linux takes seconds,
    # macOS takes milliseconds and uses -t for the deadline). It must still be
    # bounded: a hostname that resolves but never answers -- stale /etc/hosts
    # entries after a subnet change, say -- blocks for the OS default of ~10s,
    # which across the shared services turned `zeltro status` into a ~60s hang.
    if ping -c 1 -W 1 "$hostname" >/dev/null 2>&1 || timeout 2 ping -c 1 "$hostname" >/dev/null 2>&1; then
        if [ -n "$resolved_ip" ]; then
            echo-green "OK ($resolved_ip)"
        else
            echo-green "OK"
        fi
    else
        echo-red "FAILED"
    fi
}

curl_check() {
    local url="$1"

    if curl -fsS --max-time 3 --connect-timeout 2 "$url" >/dev/null 2>&1; then
        echo-green "OK ($url)"
    else
        echo-red "FAILED ($url)"
    fi
}

resolve_host() {
    local hostname="$1"
    if command -v getent >/dev/null 2>&1; then
        getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -n 1
    elif command -v host >/dev/null 2>&1; then
        host "$hostname" 2>/dev/null | awk '/has address/ {print $4; exit}'
    else
        echo ""
    fi
}

ping_status() {
    local hostname="$1"
    # The fallback exists because `-W` is not portable (Linux takes seconds,
    # macOS takes milliseconds and uses -t for the deadline). It must still be
    # bounded: a hostname that resolves but never answers -- stale /etc/hosts
    # entries after a subnet change, say -- blocks for the OS default of ~10s,
    # which across the shared services turned `zeltro status` into a ~60s hang.
    if ping -c 1 -W 1 "$hostname" >/dev/null 2>&1 || timeout 2 ping -c 1 "$hostname" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# One quick attempt by default, so `zeltro status` (and `--all` across many
# projects) stays fast and a stopped project doesn't stall the report.
#
# Callers that have JUST started a container set HTTP_WAIT_SECS to give the app
# time to bind its port — a freshly created project reports HTTP: FAILED
# otherwise, purely because the status check outran the app's startup.
curl_status() {
    local url="$1"
    local wait_secs="${HTTP_WAIT_SECS:-0}"
    local deadline=$(( $(date +%s) + wait_secs ))
    local dotted=0

    while true; do
        if curl -fsS --max-time 3 --connect-timeout 2 "$url" >/dev/null 2>&1; then
            # Close the progress dots so the verdict lands on the same line.
            [ "$dotted" = "1" ] && echo-white -n " "
            return 0
        fi

        [ "$(date +%s)" -ge "$deadline" ] && {
            [ "$dotted" = "1" ] && echo-white -n " "
            return 1
        }

        # Show progress so a legitimate wait doesn't look like a hang.
        if [[ "$JSON_OUTPUT" != "1" ]]; then
            echo-white -n "."
            dotted=1
        fi
        sleep 2
    done
}

# Parse docker-compose.yaml to get all services dynamically
parse_docker_compose_services() {
    local compose_file="$1"
    local vpc_subnet="$2"
    local services_json="{}"
    
    # Get list of running containers once for performance
    local running_containers=$(docker ps --format "{{.Names}}")
    
    if [ ! -f "$compose_file" ]; then
        echo "$services_json"
        return
    fi
    
    # Extract all service definitions using simple grep/awk
    # Look for lines that define services (2+ spaces, name, colon) but only in the services section
    local service_names=$(awk '
        /^services:/ { in_services=1; next }
        /^[a-zA-Z]/ && !/^services:/ { in_services=0 }
        in_services && /^  [a-zA-Z0-9_-]+:/ { 
            gsub(/^  /, ""); 
            gsub(/:.*/, ""); 
            print 
        }
    ' "$compose_file")
    
    # Process each service
    while IFS= read -r service_name; do
        [ -z "$service_name" ] && continue
        
        # Extract details for this service using simple grep with line numbers
        local service_start=$(grep -n "^  $service_name:" "$compose_file" | cut -d: -f1)
        local next_service=$(grep -n "^  [a-zA-Z0-9_-]*:" "$compose_file" | awk -F: -v start="$service_start" '$1 > start {print $1; exit}')
        
        # If no next service found, use end of file
        if [ -z "$next_service" ]; then
            next_service=$(wc -l < "$compose_file")
        fi
        
        # Extract the service section
        local service_section=$(sed -n "${service_start},${next_service}p" "$compose_file")
        
        local container_name=$(echo "$service_section" | grep -E "^\s+container_name:" | head -1 | sed 's/.*container_name: *\(.*\)/\1/' | tr -d '"'"'")
        # Resolve ${VAR:-default} the way compose does: VAR if set, else the
        # default. Taking the default unconditionally made this look for
        # zeltro-mariadb on a box whose container is podium-mariadb, so the JSON
        # (what the GUI reads) reported every running service as stopped.
        local _cn_re='^\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}$'
        if [[ "$container_name" =~ $_cn_re ]]; then
            local _cn_var="${BASH_REMATCH[1]}" _cn_def="${BASH_REMATCH[3]}"
            container_name="${!_cn_var:-$_cn_def}"
        fi
        local image_name=$(echo "$service_section" | grep -E "^\s+image:" | head -1 | sed 's/.*image: *\(.*\)/\1/')
        local ip_suffix=$(echo "$service_section" | grep -E "^\s+ipv4_address:" | head -1 | sed 's/.*\${VPC_SUBNET}\.\([0-9]*\).*/\1/')
        local port=$(echo "$service_section" | grep -A 5 "expose:" | grep -E "^\s+- " | head -1 | grep -o '[0-9]\+' | head -1)
        
        # Use container_name if available, otherwise use service name
        local final_container_name="${container_name:-$service_name}"
        local display_name="${container_name:-$service_name}"
        local ip_address=""
        
        # Build IP address if we have both VPC_SUBNET and suffix
        if [ -n "$vpc_subnet" ] && [ -n "$ip_suffix" ]; then
            ip_address="${vpc_subnet}.${ip_suffix}"
        fi
        
        # Check if container is running
        local status="stopped"
        if echo "$running_containers" | grep -q "^${final_container_name}$"; then
            status="running"
        fi
        
        # Add to JSON
        services_json=$(echo "$services_json" | jq --arg key "$final_container_name" \
            --arg name "$display_name" \
            --arg status "$status" \
            --arg ip "$ip_address" \
            --arg port "$port" \
            '.[$key] = {name: $name, status: $status, ip_address: $ip, port: $port}')
            
    done <<< "$service_names"
    
    echo "$services_json"
}

get_project_status() {
    local proj_name="$1"
    local project_data="{}"
    
    # Project folder check
    if [ -d "$proj_name" ]; then
        project_data=$(echo "$project_data" | jq --arg name "$proj_name" '. + {name: $name, folder_exists: true}')
        
    else
        project_data=$(echo "$project_data" | jq --arg name "$proj_name" '. + {name: $name, folder_exists: false}')
    fi
    
    # Display metadata straight from the project's x-metadata block, so nothing
    # downstream has to open docker-compose.yaml to render a project. Nested
    # under `metadata` rather than flattened because two keys collide: the
    # block's `name` is the human label while `name` here is the slug, and its
    # `status` is enabled/disabled while `status` elsewhere means running/stopped.
    #
    # `{}` for projects with no block, which is most of the ones created before
    # x-metadata existed.
    local _meta_file _meta_json
    _meta_file="$(zeltro_project_compose "$proj_name" 2>/dev/null)"
    _meta_json="$(read_x_metadata_json "$_meta_file")"
    [ -n "$_meta_json" ] || _meta_json="{}"
    project_data=$(echo "$project_data" | jq --argjson meta "$_meta_json" '. + {metadata: $meta}')

    # Host entry check
    local resolved_ip=""
    EXT_PORT="$(zeltro_project_port "$proj_name")"
    resolved_ip="$(zeltro_project_ip "$proj_name")"
    if [ -n "$EXT_PORT" ]; then
        project_data=$(echo "$project_data" | jq --arg port "$EXT_PORT" --arg ip "$resolved_ip" '. + {external_port: $port, project_ip: $ip}')
    else
        project_data=$(echo "$project_data" | jq '. + {external_port: null, project_ip: null}')
    fi
    
    project_data=$(echo "$project_data" | jq --arg ip "$resolved_ip" '. + {resolved_ip: (if ($ip|length>0) then $ip else null end)}')
    
    # Docker status check
    ping_state="skipped"
    http_state="skipped"
    if [ "$(docker ps -q -f name=$proj_name)" ]; then
        project_data=$(echo "$project_data" | jq '. + {docker_running: true}')
        
        # "not_applicable" rather than "failed" where the host cannot route to
        # container IPs at all. Reporting failed would be true and useless: a
        # consumer cannot tell a broken project from a platform that has never
        # supported this route, and would mark every healthy macOS project down.
        if zeltro_host_reaches_containers; then
            if ping_status "$proj_name"; then
                ping_state="ok"
            else
                ping_state="failed"
            fi
        else
            ping_state="not_applicable"
        fi
        
        # Port mapping check (only if running)
        if docker port "$proj_name" 80/tcp > /dev/null 2>&1; then
            project_data=$(echo "$project_data" | jq '. + {port_mapped: true}')
            # Probe whichever URL actually works on this host — the hostname on
            # Linux, the published port on macOS.
            if zeltro_host_reaches_containers; then
                _probe_url="http://$resolved_ip"
            else
                _probe_url="http://localhost:$EXT_PORT"
            fi
            if curl_status "$_probe_url"; then
                http_state="ok"
            else
                http_state="failed"
            fi
        else
            project_data=$(echo "$project_data" | jq '. + {port_mapped: false}')
            http_state="skipped"
        fi
    else
        project_data=$(echo "$project_data" | jq '. + {docker_running: false, port_mapped: false}')
    fi
    
    project_data=$(echo "$project_data" | jq --arg ping "$ping_state" --arg http "$http_state" '. + {ping_status: $ping, http_status: $http}')
    
    # URLs
    if [ -n "$EXT_PORT" ]; then
        # local_url is always an address now, never a hostname — Zeltro no longer
        # writes /etc/hosts, so a name would not resolve anywhere.
        #
        # Where the host can route to container IPs (Linux, and inside WSL) the
        # container address is the direct route. Where it cannot (macOS, and
        # Windows looking into WSL) the published port on localhost is the only
        # one that exists.
        if zeltro_host_reaches_containers && [ -n "$resolved_ip" ]; then
            _local_url="http://$resolved_ip"
        else
            _local_url="http://localhost:$EXT_PORT"
        fi
        project_data=$(echo "$project_data" | jq --arg local "$_local_url" --arg lan "http://$LAN_IP:$EXT_PORT" '. + {local_url: $local, lan_url: $lan}')
    else
        project_data=$(echo "$project_data" | jq '. + {local_url: null, lan_url: null}')
    fi
    
    echo "$project_data"
}

project_status() {
  PROJ_NAME=$1

  if [[ "$JSON_OUTPUT" == "1" ]]; then
    # JSON output is handled in main section
    return 0
  fi

  echo -n PROJECT:
  echo-yellow " $PROJ_NAME"

  echo-white -n PROJECT FOLDER:
  if ! [ -d "$PROJ_NAME" ]; then
    echo-red " NOT FOUND"
    echo-white -n SUGGESTION:; echo-yellow " Check spelling or clone repo"
    return 1
  else
    echo-green " FOUND"
  fi

  echo-white -n ADDRESS: 
  EXT_PORT="$(zeltro_project_port "$PROJ_NAME")"
  RESOLVED_IP="$(zeltro_project_ip "$PROJ_NAME")"
  if [ -z "$EXT_PORT" ]; then
    echo-red " NOT FOUND"
    echo-white -n SUGGESTION:; echo-yellow " cd \$(zeltro projects-dir)/$PROJ_NAME && zeltro setup $PROJ_NAME"
    return 1
  else
    echo-green " FOUND"
  fi

  echo-white -n DOCKER STATUS:
  if ! [ "$(docker ps -q -f name=$PROJ_NAME)" ]; then
    echo-red " NOT RUNNING"
    echo-white -n SUGGESTION:; echo-yellow " cd \$(zeltro projects-dir)/$PROJ_NAME && zeltro up"
    return 1
  else
    echo-green " RUNNING"
  fi

  echo-white -n DOCKER PORT MAPPING:
  # EXT_PORT / RESOLVED_IP already read from the compose file above.
  # Check if Docker container has port mapping
  if ! docker port "$PROJ_NAME" 80/tcp > /dev/null 2>&1; then
    echo-red " NOT MAPPED"
    echo-white -n SUGGESTION:; echo-yellow " cd \$(zeltro projects-dir)/$PROJ_NAME && zeltro down && zeltro up"
    return 1
  else
    echo-green " MAPPED"
  fi



  # On a host that cannot route to container IPs (macOS), checking the hostname
  # is guaranteed to fail and tells the user nothing. Check the published port
  # instead, which is the only route that exists there.
  if zeltro_host_reaches_containers; then
    # Probe the address, not the name. Zeltro no longer writes /etc/hosts, so
    # the project name resolves nowhere and testing it would always fail.
    echo-white -n "PING: "
    if [ -n "$RESOLVED_IP" ] && ping_status "$RESOLVED_IP"; then
      echo-green "OK ($RESOLVED_IP)"
    else
      echo-red "FAILED"
    fi

    echo-white -n "HTTP: "
    if curl_status "http://$RESOLVED_IP"; then
      echo-green "OK (http://$RESOLVED_IP)"
    else
      echo-red "FAILED (http://$RESOLVED_IP)"
    fi
  else
    echo-white -n "PING: "
    echo-cyan "n/a (Docker Desktop keeps container IPs inside a VM)"

    echo-white -n "HTTP: "
    if curl_status "http://localhost:$EXT_PORT"; then
      echo-green "OK (http://localhost:$EXT_PORT)"
    else
      echo-red "FAILED (http://localhost:$EXT_PORT)"
    fi
  fi

  # Two addresses, always shown, never a hostname — Zeltro no longer writes
  # /etc/hosts, so a name would resolve nowhere.
  #
  # LOCAL is the route from this machine; LAN is the route from another machine
  # on the network. They differ, and conflating them is how someone ends up
  # sending a colleague a link only they can open.
  echo-white -n "LOCAL ACCESS:"
  if zeltro_host_reaches_containers && [ -n "$RESOLVED_IP" ]; then
    # Linux, and inside WSL: the container address is directly routable.
    echo-yellow " http://$RESOLVED_IP"
  else
    # macOS, and Windows looking into WSL: container IPs live inside a VM, so
    # the published port is the only way in.
    echo-yellow " http://localhost:$EXT_PORT"
  fi
  echo-white -n "LAN ACCESS:  "; echo-yellow " http://$LAN_IP:$EXT_PORT"
}


# Main

# Do not run as root
if [[ "$(whoami)" == "root" ]]; then

  error "Do NOT run with sudo!"

fi


# Check if this environment is installed
if ! [ -f /etc/zeltro-cli/.env ]; then
    error "Development environment has not been configured! Run: zeltro configure"
fi

if ! [ -f /etc/zeltro-cli/docker-compose.yaml ]; then
    error "Development environment has not been configured! Run: zeltro configure"
fi

# Services are profile-gated and enabled on demand, so "mariadb is not running"
# is a normal state on a Postgres-only or SQLite-only machine — not a broken
# environment. Only say something when NOTHING is enabled at all, and say it as
# information rather than an error.
if [ -z "${OPTIONAL_SERVICES:-}" ]; then
    echo-yellow "No shared services are enabled yet."
    echo-white  "They are enabled automatically when a project needs one, or turn one on with:"
    echo-white  "  zeltro enable-service <name>"
    echo-return
fi


# Handle JSON output - ALWAYS return JSON when requested, regardless of service state
if [[ "$JSON_OUTPUT" == "1" ]]; then
    # Get VPC subnet from .env file
    VPC_SUBNET=""
    if [ -f "/etc/zeltro-cli/.env" ]; then
        VPC_SUBNET=$(grep "^VPC_SUBNET=" /etc/zeltro-cli/.env | cut -d'=' -f2)
    fi
    
    # Initialize JSON structure
    JSON_DATA='{"shared_services": {}, "projects": []}'
    
    # Parse docker-compose.yaml to get all services dynamically
    COMPOSE_FILE="/etc/zeltro-cli/docker-compose.yaml"
    if [ ! -f "$COMPOSE_FILE" ]; then
        # Try fallback location
        COMPOSE_FILE="$DEV_DIR/docker-stack/docker-compose.services.yaml"
    fi
    
    if [ -f "$COMPOSE_FILE" ]; then
        SERVICES_JSON=$(parse_docker_compose_services "$COMPOSE_FILE" "$VPC_SUBNET")
        
        # Add connectivity details to services JSON
        if [ -n "$SERVICES_JSON" ]; then
            while IFS= read -r service_name; do
                [ -z "$service_name" ] && continue
                
                service_status=$(echo "$SERVICES_JSON" | jq -r --arg name "$service_name" '.[$name].status')
                resolved_ip=""
                [ "$service_status" = "running" ] && resolved_ip=$(service_addr "$service_name")
                case "$resolved_ip" in *[!0-9.]*) resolved_ip="" ;; esac
                
                ping_state="skipped"
                http_state="skipped"
                http_url=""
                
                if [ "$service_status" = "running" ] && ! zeltro_host_reaches_containers; then
                    # Docker Desktop (macOS/Windows): container IPs are not
                    # routable from the host, so a probe could only ever fail.
                    ping_state="not_applicable"
                elif [ "$service_status" = "running" ]; then
                    if ping_status "${resolved_ip:-$service_name}"; then
                        ping_state="ok"
                    else
                        ping_state="failed"
                    fi

                    # Keys are container names (podium-phpmyadmin), so the bare
                    # "phpmyadmin)" pattern never matched and these never ran.
                    case "$service_name" in
                        *phpmyadmin)
                            http_url="http://${resolved_ip:-$service_name}/"
                            ;;
                        *mailhog)
                            http_url="http://${resolved_ip:-$service_name}:8025/"
                            ;;
                    esac
                    
                    if [ -n "$http_url" ]; then
                        if curl_status "$http_url"; then
                            http_state="ok"
                        else
                            http_state="failed"
                        fi
                    fi
                fi
                
                SERVICES_JSON=$(echo "$SERVICES_JSON" | jq \
                    --arg name "$service_name" \
                    --arg resolved "$resolved_ip" \
                    --arg ping "$ping_state" \
                    --arg http "$http_state" \
                    --arg url "$http_url" \
                    '.[$name].resolved_ip = ( ($resolved | select(length>0)) // null)
                     | .[$name].ping_status = $ping
                     | (if ($url|length>0) then .[$name].http_url = $url | .[$name].http_status = $http else . end)')
            done <<< "$(echo "$SERVICES_JSON" | jq -r 'keys[]')"
        fi
        
        JSON_DATA=$(echo "$JSON_DATA" | jq --argjson services "$SERVICES_JSON" '.shared_services = $services')
    fi
    
    # Use projects directory from pre_check
    if [ -d "$PROJECTS_DIR_PATH" ]; then
        cd "$PROJECTS_DIR_PATH"
        
        if ! [ -z "$PROJECT_NAME" ]; then
            # Single project requested — always shown, even if stopped.
            if [ -d "$PROJECT_NAME" ]; then
                PROJECT_JSON=$(get_project_status "$PROJECT_NAME")
                JSON_DATA=$(echo "$JSON_DATA" | jq --argjson project "$PROJECT_JSON" '.projects += [$project]')
            fi
        else
            # All projects (optionally only running ones)
            for item in *; do
                if [ -d "$item" ] && [ "$item" != "." ] && [ "$item" != ".." ]; then
                    if [ "$RUNNING_ONLY" = "1" ] && ! service_running "$item"; then
                        continue
                    fi
                    PROJECT_JSON=$(get_project_status "$item")
                    JSON_DATA=$(echo "$JSON_DATA" | jq --argjson project "$PROJECT_JSON" '.projects += [$project]')
                fi
            done
        fi
    fi
    
    echo "$JSON_DATA"
    
    # Use return if sourced, exit if called directly
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    else
        exit 0
    fi
fi

# Traditional text output
# These probe the shared services by container hostname, which only works on a
# host that can route to container IPs. On macOS none of them can succeed —
# Docker Desktop keeps containers in a VM — so running them produces a screen
# of FAILED for services that are healthy, and reports a running MariaDB as
# "enabled but NOT RUNNING". Say so once instead.
if zeltro_host_reaches_containers; then
    echo-cyan "SHARED SERVICES CONNECTIVITY:"
    echo-return

    if service_running "$MARIADB_CONTAINER_NAME"; then
        echo-white -n "PING (MariaDB): "
        ping_host "$(service_addr "$MARIADB_CONTAINER_NAME")"
    else
        echo-yellow "PING (MariaDB): skipped (not running)"
    fi

    if service_running "$PHPMYADMIN_CONTAINER_NAME"; then
        echo-white -n "PING (phpMyAdmin): "
        ping_host "$(service_addr "$PHPMYADMIN_CONTAINER_NAME")"
    else
        echo-yellow "PING (phpMyAdmin): skipped (not running)"
    fi

    if service_running "$REDIS_CONTAINER_NAME"; then
        echo-white -n "PING (Redis): "
        ping_host "$(service_addr "$REDIS_CONTAINER_NAME")"
    else
        echo-yellow "PING (Redis): skipped (not running)"
    fi

    if service_running "$MEMCACHED_CONTAINER_NAME"; then
        echo-white -n "PING (Memcached): "
        ping_host "$(service_addr "$MEMCACHED_CONTAINER_NAME")"
    else
        echo-yellow "PING (Memcached): skipped (not running)"
    fi

    if service_running "$POSTGRES_CONTAINER_NAME"; then
        echo-white -n "PING (PostgreSQL): "
        ping_host "$(service_addr "$POSTGRES_CONTAINER_NAME")"
    else
        echo-yellow "PING (PostgreSQL): skipped (not running)"
    fi

    if service_running "$MONGO_CONTAINER_NAME"; then
        echo-white -n "PING (MongoDB): "
        ping_host "$(service_addr "$MONGO_CONTAINER_NAME")"
    else
        echo-yellow "PING (MongoDB): skipped (not running)"
    fi

    if service_running "$MAILHOG_CONTAINER_NAME"; then
        echo-white -n "PING (MailHog): "
        ping_host "$(service_addr "$MAILHOG_CONTAINER_NAME")"
    else
        echo-yellow "PING (MailHog): skipped (not running)"
    fi

    # Optional shared services, only reported when this machine has them enabled —
    # otherwise every install would show two permanently-skipped lines for services
    # it deliberately does not run.
        for _opt in ${OPTIONAL_SERVICES:-}; do
            case "$_opt" in
                # Databases became opt-in, so they appear in OPTIONAL_SERVICES --
                # but they are already reported above. "mysql" in particular was
                # looked up as <prefix>-mysql, which never exists, and printed a
                # running MariaDB as "enabled but NOT RUNNING".
                mysql|mariadb|postgres|postgresql|mongo|mongodb|redis|memcached|mailhog|phpmyadmin) continue ;;
                minio)       _opt_label="MinIO" ;;
                meilisearch) _opt_label="Meilisearch" ;;
                *)           _opt_label="$_opt" ;;
            esac
            _opt_host="$(zeltro_service_container "$_opt")"
            if service_running "$_opt_host"; then
                echo-white -n "PING ($_opt_label): "
                ping_host "$(service_addr "$_opt_host")"
        else
            echo-yellow "PING ($_opt_label): enabled but NOT RUNNING — try 'zeltro start-services'"
        fi
    done

    echo-return
    divider
    echo-cyan "SHARED SERVICE HTTP CHECKS:"
    echo-return

    if service_running "$PHPMYADMIN_CONTAINER_NAME"; then
        echo-white -n "HTTP (phpMyAdmin): "
        curl_check "http://$(service_addr "$PHPMYADMIN_CONTAINER_NAME")/"
    else
        echo-yellow "HTTP (phpMyAdmin): skipped (not running)"
    fi

    if service_running "$MAILHOG_CONTAINER_NAME"; then
        echo-white -n "HTTP (MailHog): "
        curl_check "http://$(service_addr "$MAILHOG_CONTAINER_NAME"):8025/"
    else
        echo-yellow "HTTP (MailHog): skipped (not running)"
    fi
else
    echo-return
    divider
    echo-cyan "SHARED SERVICES CONNECTIVITY:"
    echo-return
    echo-white "  Not checked from the host: Docker Desktop keeps container IPs inside a"
    echo-white "  VM, so they are unreachable from macOS by design. Containers still reach"
    echo-white "  each other by hostname normally — this affects host-side checks only."
    echo-return
    echo-white "  Service state above reflects whether each container is running."
fi

divider

# Iterate through projects folder (from pre_check)
cd "$PROJECTS_DIR_PATH"

if ! [ -z "$PROJECT_NAME" ]; then
    # A specifically named project is always shown, even if stopped.
    if project_status $PROJECT_NAME; then true; fi
    divider
else
    # Count project directories (only running ones when --running is set)
    PROJECT_COUNT=0
    for item in *; do
        if [ -d "$item" ] && [ "$item" != "." ] && [ "$item" != ".." ]; then
            if [ "$RUNNING_ONLY" = "1" ] && ! service_running "$item"; then
                continue
            fi
            PROJECT_COUNT=$((PROJECT_COUNT + 1))
        fi
    done

    if [ $PROJECT_COUNT -eq 0 ]; then
        echo-cyan "PROJECTS STATUS:"
        echo-return
        if [ "$RUNNING_ONLY" = "1" ]; then
            echo-yellow "No running projects."
            echo-white "Start one with: zeltro up <project>"
        else
            echo-yellow "No projects found in $(pwd)"
            echo-white "Create your first project with: zeltro new"
        fi
        divider
    else
        echo-cyan "PROJECTS STATUS:"
        echo-return
        for PROJECT_NAME in *; do
            if [ -d "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "." ] && [ "$PROJECT_NAME" != ".." ]; then
                if [ "$RUNNING_ONLY" = "1" ] && ! service_running "$PROJECT_NAME"; then
                    continue
                fi
                if project_status $PROJECT_NAME; then true; fi
                divider
            fi
        done
    fi
fi
