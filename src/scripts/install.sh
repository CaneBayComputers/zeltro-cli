#!/bin/bash

set -e

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..
DEV_DIR=$(pwd)

source scripts/pre_check.sh

# Rewrite zeltro-<service> hostnames to the container names THIS machine runs.
# Reads stdin, writes stdout.
#
# Installers are written against the zeltro-* names, but a box installed under
# the Podium name runs podium-mariadb, podium-postgres and so on, and nothing
# answers to zeltro-* there. So `docker exec zeltro-mariadb ...` in a
# pre_install hook failed with "No such container", and a compose pointing
# DB_HOST at zeltro-postgres could never connect. Only whole names are
# rewritten: the character after the name must not continue it, so
# zeltro-mongo never eats the front of zeltro-mongo-express. A plain `cat` when
# the names already match, which is every machine installed after the rename.
_install_localize_service_names() {
    local svc name exprs=""
    for svc in mariadb postgres mongo redis memcached mailhog minio meilisearch; do
        name="$(zeltro_service_container "$svc")"
        [ "$name" = "zeltro-$svc" ] && continue
        exprs="${exprs}s/zeltro-${svc}([^A-Za-z0-9_-]|\$)/${name}\\1/g;"
    done
    if [ -z "$exprs" ]; then
        cat
    else
        sed -E "$exprs"
    fi
}

# This machine's LAN address, for the address other machines use. Same routing
# table lookup `zeltro status` does (iproute2 first; `hostname -I` does not
# exist on a minimal Arch install). Empty when it cannot be determined.
_install_lan_ip() {
    local ip=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ip=$(route get default 2>/dev/null | grep interface | awk '{print $2}' \
             | xargs ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    else
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
             | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i+1); exit }}')
        [ -n "$ip" ] || ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    fi
    printf '%s' "$ip"
}

# Replace http://<project> in an installer's notes/credentials with the real
# address. Installers write things like "Visit http://ghost/ghost/" -- sourced
# with $PROJECT_NAME already expanded -- and that host resolves nowhere now
# that Zeltro no longer writes /etc/hosts. Whole host only: http://ghost must
# not match the front of http://ghost-admin.
#   $1 text   $2 project name   $3 real URL (no trailing slash)
_install_real_urls() {
    local text="$1" name="$2" url="$3" esc
    [ -n "$text" ] && [ -n "$url" ] || { printf '%s' "$text"; return 0; }
    esc="$(printf '%s' "$name" | sed 's/[.]/\\./g')"
    printf '%s' "$text" | sed -E "s#http://${esc}([^A-Za-z0-9_.-]|\$)#${url}\\1#g"
}

SKIP_INTERACTIVE=0
APP=""
PROJECT_NAME=""
CUSTOM_IMAGE=""
LIST_ONLY=0
JSON_OUTPUT="${JSON_OUTPUT:-}"
NO_COLOR="${NO_COLOR:-}"
DEBUG="${DEBUG:-}"
ORIGINAL_ARGS="$*"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo-white "Usage: ${ZELTRO_CMD:-$0} <app> [name] [options]"
            echo-white "Installs a curated open-source app, fully configured and running"
            echo-white ""
            echo-white "Arguments:"
            echo-white "  app             Installer slug (see --list)"
            echo-white "  name            Project directory and hostname (default: the app slug)"
            echo-white ""
            echo-white "Options:"
            echo-white "  --list          List every available app and exit"
            echo-white "  --image REF     Override the image the installer would use"
            echo-white "  --one-off       Skip the AI session after install (for automation)"
            echo-white "  --json-output   Output JSON responses (for programmatic use)"
            echo-white "  --no-colors     Disable colored output"
            echo-white "  --debug         Enable debug logging to /tmp/zeltro-cli-debug.log"
            echo-white "  --help, -h      Show this help message"
            echo-white ""
            echo-white "Examples:"
            echo-white "  ${ZELTRO_CMD:-$0} grafana"
            echo-white "  ${ZELTRO_CMD:-$0} livewire sign-tools"
            echo-white "  ${ZELTRO_CMD:-$0} --list"
            exit 0
            ;;
        --one-off) SKIP_INTERACTIVE=1; shift ;;
        --list|-l) LIST_ONLY=1; shift ;;
        # These three used to fall through to the positional branch, so
        # `zeltro install --debug grafana` tried to install an app called
        # "--debug". They are also forwarded to setup and up below.
        --debug) DEBUG=1; export DEBUG; shift ;;
        --no-colors) NO_COLOR=1; export NO_COLOR; shift ;;
        --json-output) JSON_OUTPUT=1; export JSON_OUTPUT; shift ;;
        --image)
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                CUSTOM_IMAGE="$2"
                shift 2
            else
                error "Error: --image requires a Docker image reference (e.g. canebaycomputers/cbc:nginx-php8)"
            fi
            ;;
        -*)
            error "Unknown option: $1. Use --help for usage information"
            ;;
        *)
            # Positional order: <app> [name]. The app selects the installer; the
            # optional name is the project directory/hostname (defaults to app).
            if [ -z "$APP" ]; then
                APP="$1"
            elif [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            else
                error "Too many arguments. Usage: zeltro install <app> [name] [--image <ref>]"
            fi
            shift
            ;;
    esac
done

debug "Script started: install.sh with args: $ORIGINAL_ARGS"

# Project name defaults to the app slug when not given a custom name.
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="$APP"
fi

# List available installers
if [ "$LIST_ONLY" = "1" ]; then
    echo-return
    echo-white "Available installers:"
    for f in "$DEV_DIR/installers/"*.sh; do
        [ -f "$f" ] && echo-cyan "  zeltro install $(basename "$f" .sh)"
    done
    echo-return
    exit 0
fi

if [ -z "$APP" ]; then
    # An app name is required — no interactive picker.
    echo-red "No app specified."
    echo-white "Usage: zeltro install <app> [name] [--image <ref>]     (run 'zeltro install --list' to see all)"
    exit 1
fi

INSTALLER="$DEV_DIR/installers/$APP.sh"
if [ ! -f "$INSTALLER" ]; then
    # The mirror of the check in new_project.sh: if this is a framework, the
    # user wants `zeltro new` — say so rather than making them go read a list.
    if [ -f "$DEV_DIR/frameworks/$APP.sh" ]; then
        echo-yellow "'$APP' is a framework, not a prebuilt app."
        echo-white "Frameworks are scaffolded into a project you write, rather than installed."
        echo-return
        echo-cyan "Run this instead:"
        echo-white "  zeltro new $APP ${PROJECT_NAME:-<project-name>}"
        echo-return
        echo-red "Wrong command for '$APP' — use 'zeltro new'."
        exit 1
    fi
    # Apps that were retired or renamed: say where they went rather than
    # leaving someone with an old command in a script to go digging.
    case "$APP" in
        trilium)
            echo-yellow "'trilium' ran the unmaintained zadam/trilium image and has been removed."
            echo-white "TriliumNext is the maintained successor. Run this instead:"
            echo-white "  zeltro install triliumnext${PROJECT_NAME:+ $PROJECT_NAME}"
            exit 1 ;;
        whoogle)
            echo-yellow "'whoogle' has been removed: the project ended on 2026-07-24 and no longer returns results."
            echo-white "For a self-hosted metasearch engine, try:  zeltro install searxng"
            exit 1 ;;
    esac
    echo-red "No installer found for: $APP"
    echo-white "Run 'zeltro install --list' to see available apps."
    exit 1
fi

PROJECTS_DIR="$(get_projects_dir)"
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"

# Already installed? (only skip if actually running)
# Existence is a directory question, not an /etc/hosts question. Zeltro no
# longer writes that file, and a leftover entry used to make a long-deleted
# project look installed.
if [ -d "$PROJECTS_DIR_PATH/$PROJECT_NAME" ]; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
        echo-yellow "$PROJECT_NAME is already installed and running."
        _url="$(zeltro_project_url "$PROJECT_NAME")"
        echo-white "Visit: ${_url:-the address 'zeltro status $PROJECT_NAME' prints}"
        exit 0
    fi
fi

# Defaults (overridable by installer)
INSTALL_DISPLAY="$PROJECT_NAME"
INSTALL_CREDENTIALS=""
INSTALL_NOTES=""

# Installers name the shared services by their zeltro-* hostnames. A machine
# installed under the Podium name runs podium-* containers instead, so source a
# copy with this machine's names in it -- that covers the pre_install hook's
# `docker exec` and every file write_files generates, in one place.
INSTALLER_SRC="$(mktemp "${TMPDIR:-/tmp}/zeltro-install.XXXXXX")"
_install_localize_service_names < "$INSTALLER" > "$INSTALLER_SRC"
source "$INSTALLER_SRC"
rm -f "$INSTALLER_SRC"

echo-return
echo-green "Installing $INSTALL_DISPLAY..."
echo-return

# Bring up the services this installer talks to, BEFORE pre_install runs — that
# hook creates databases and therefore needs the server already up. The project's
# compose does not exist yet, so the installer file itself is what we read.
_needed="$(services_referenced_in "$(cat "$INSTALLER" 2>/dev/null)")"
[ -n "$_needed" ] && ensure_services_running $_needed

# Pre-install hook (DB creation, key generation, etc.)
if declare -f pre_install > /dev/null 2>&1; then
    pre_install
fi

# Write project files
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
write_files

# Setup and start.
# Prebuilt-image apps (the default) only need their compose adapted, then a start —
# so setup runs with --no-startup and 'zeltro up' brings the container online.
# Source-based apps (INSTALL_SETUP_FULL=1, e.g. a Laravel scaffold) need the full
# setup pipeline — composer install, front-end build, .env wiring, migrations — which
# only runs when setup is NOT given --no-startup. Setup starts the container itself in
# that case, so no separate 'zeltro up' is required.
# Forward a user-supplied --image override to setup (empty array → no extra args).
IMAGE_ARGS=()
[ -n "$CUSTOM_IMAGE" ] && IMAGE_ARGS=(--image "$CUSTOM_IMAGE")
# Flags this command was given that setup and up understand too.
PASS_ARGS=()
[ "$DEBUG" = "1" ] && PASS_ARGS+=(--debug)
[ "$NO_COLOR" = "1" ] && PASS_ARGS+=(--no-colors)

# `zeltro setup <project> [database_engine]`: the engine is setup's second
# positional argument (there is no --database flag on setup). Passed only when
# the installer names one, and quoted, so an empty or odd value can never
# shift or split the arguments after it.
SETUP_ARGS=("$PROJECT_NAME")
[ -n "${INSTALL_SETUP_DB:-}" ] && SETUP_ARGS+=("$INSTALL_SETUP_DB")

# Call this install's own dispatcher, not whichever `zeltro` is first on PATH:
# a checkout run as ./src/zeltro otherwise sourced its own installer and then
# handed the project to a different copy of Zeltro to set up.
ZELTRO_BIN="$DEV_DIR/zeltro"

# The ${arr[@]+...} guard keeps an empty array from tripping bash 3.2 (macOS).
if [ "${INSTALL_SETUP_FULL:-0}" = "1" ]; then
    "$ZELTRO_BIN" setup "${SETUP_ARGS[@]}" ${IMAGE_ARGS[@]+"${IMAGE_ARGS[@]}"} ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
else
    "$ZELTRO_BIN" setup "${SETUP_ARGS[@]}" --no-startup ${IMAGE_ARGS[@]+"${IMAGE_ARGS[@]}"} ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
    "$ZELTRO_BIN" up "$PROJECT_NAME" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
fi

# Verify, against the address the project really has. Zeltro no longer writes
# /etc/hosts, so http://<project>/ resolves nowhere on the host: probing it
# made every install wait out the full timeout, report "may still be
# initializing" for an app that was already up, and print a URL that could not
# be opened. zeltro_project_url is the container IP on Linux and
# localhost:<port> on macOS/Windows, read from the compose setup just wrote --
# the same LOCAL/LAN pair `zeltro status` shows.
PROJECT_URL="$(zeltro_project_url "$PROJECT_NAME")"
PROJECT_PORT="$(zeltro_project_port "$PROJECT_NAME")"
LAN_IP="$(_install_lan_ip)"
LAN_URL=""
[ -n "$LAN_IP" ] && [ -n "$PROJECT_PORT" ] && LAN_URL="http://$LAN_IP:$PROJECT_PORT"
INSTALL_CREDENTIALS="$(_install_real_urls "$INSTALL_CREDENTIALS" "$PROJECT_NAME" "$PROJECT_URL")"
INSTALL_NOTES="$(_install_real_urls "$INSTALL_NOTES" "$PROJECT_NAME" "$PROJECT_URL")"

echo-return
echo-white "Waiting for $INSTALL_DISPLAY to be ready at ${PROJECT_URL:-(no address found)} ..."
# 15 x 5s = 75s suits most apps, but some do first-run migrations or asset
# builds that take minutes. An installer can declare INSTALL_READY_RETRIES to
# wait longer; without it a working app reports failure purely for being slow.
READY_RETRIES="${INSTALL_READY_RETRIES:-15}"
RETRIES=0
HTTP_CODE="000"
while [ $RETRIES -lt "$READY_RETRIES" ]; do
    # Two traps here. curl -w already prints 000 when it cannot connect, so the
    # original `|| echo "000"` produced "HTTP 000000". But that `||` was ALSO
    # shielding the assignment from `set -e` — curl exits 7 on connection
    # refused, which is the normal case while an app is still booting, and
    # without a guard the whole install aborts mid-wait with status 7.
    # No address at all means setup never wrote one; there is nothing to wait on.
    [ -n "$PROJECT_URL" ] || break
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$PROJECT_URL/" 2>/dev/null) || true
    [ -z "$HTTP_CODE" ] && HTTP_CODE="000"
    first_digit="${HTTP_CODE:0:1}"
    if [ "$first_digit" = "2" ] || [ "$first_digit" = "3" ]; then
        break
    fi
    RETRIES=$((RETRIES + 1))
    sleep 5
done

echo-return
first_digit="${HTTP_CODE:0:1}"
if [ "$first_digit" = "2" ] || [ "$first_digit" = "3" ]; then
    echo-green "$INSTALL_DISPLAY is ready! (HTTP $HTTP_CODE)"
    echo-return
    echo-white "  URL: $PROJECT_URL/"
    [ -n "$LAN_URL" ] && echo-white "  LAN: $LAN_URL/  (from other machines on your network)"
    [ -n "$INSTALL_CREDENTIALS" ] && echo-white "  Credentials: $INSTALL_CREDENTIALS"
    [ -n "$INSTALL_NOTES" ] && echo-yellow "  Note: $INSTALL_NOTES"
elif [ -z "$PROJECT_URL" ]; then
    echo-yellow "Could not find an address for $PROJECT_NAME in its compose file."
    echo-white "  Check: zeltro status $PROJECT_NAME"
    echo-white "  Logs:  zeltro logs $PROJECT_NAME"
else
    echo-yellow "$INSTALL_DISPLAY returned HTTP $HTTP_CODE — it may still be initializing."
    echo-white "  Check: curl -sI $PROJECT_URL/"
    echo-white "  Logs:  zeltro logs $PROJECT_NAME"
    [ -n "$INSTALL_CREDENTIALS" ] && echo-white "  Credentials: $INSTALL_CREDENTIALS"
    [ -n "$INSTALL_NOTES" ] && echo-yellow "  Note: $INSTALL_NOTES"
fi
echo-return

# Drop into an interactive AI session inside the project (skipped when --one-off,
# JSON mode, non-TTY, or no AI agent configured).
INSTALL_CMD="zeltro install $APP"
[ "$PROJECT_NAME" != "$APP" ] && INSTALL_CMD="zeltro install $APP $PROJECT_NAME"
ai_handoff "$PROJECT_NAME" "This project is managed by the Zeltro CLI — a Docker-based local development environment manager — and was created by running '$INSTALL_CMD'. Before doing anything: (1) read /usr/local/share/zeltro-cli/AGENTS.md for how Zeltro works; (2) run 'zeltro help' for the full command list. $INSTALL_DISPLAY is running at ${PROJECT_URL:-the address 'zeltro status $PROJECT_NAME' prints}/ (the project name is not a hostname on the host; containers reach it as http://$PROJECT_NAME/). You are the developer."
