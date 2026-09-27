#!/bin/bash

set -e


ORIG_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"

cd ..

DEV_DIR=$(pwd)

source scripts/functions.sh

# Define SCRIPT_DIR for file operations
SCRIPT_DIR="$DEV_DIR/scripts"

# Parse arguments. Track flag-supplied values separately so we can distinguish
# "user explicitly passed this" from "value loaded from /etc/zeltro-cli/.env".
GIT_NAME=""
GIT_EMAIL=""
FLAG_PROJECTS_DIR=""
FLAG_VPC_SUBNET=""
NON_INTERACTIVE=0

# Capture original arguments for debug logging
ORIGINAL_ARGS="$*"

while [[ $# -gt 0 ]]; do
    case $1 in
        --json-output)
            export JSON_OUTPUT=1
            shift
            ;;
        --git-name)
            GIT_NAME="$2"
            shift 2
            ;;
        --git-email)
            GIT_EMAIL="$2"
            shift 2
            ;;
        --projects-dir)
            FLAG_PROJECTS_DIR="$2"
            shift 2
            ;;
        --vpc-subnet)
            FLAG_VPC_SUBNET="$2"
            shift 2
            ;;
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=1
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --help)
            echo "Usage: ${ZELTRO_CMD:-$0} [OPTIONS]"
            echo ""
            echo "Configure Zeltro development environment. Re-running is safe — values"
            echo "from /etc/zeltro-cli/.env are kept as defaults, and prompts let you"
            echo "change them if you want."
            echo ""
            echo "Pass --non-interactive for a fully unattended run (scripts, CI, agents)."
            echo ""
            echo "Options:"
            echo "  --json-output           Output results in JSON format"
            echo "  --debug                 Enable debug logging to /tmp/zeltro-cli-debug.log"
            echo "  --git-name NAME         Git user name"
            echo "  --git-email EMAIL       Git user email"
            echo "  --projects-dir DIR      Projects directory (default: existing or ~/zeltro-projects)"
            echo "  --vpc-subnet A.B.C      Custom Docker VPC subnet (default: existing or random 10.x.x)"
            echo "  --non-interactive, -y   Never prompt; accept defaults for anything not passed as a flag"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        -*)
            # Previously any unrecognised argument was silently shifted away, so
            # a mistyped flag looked like it had been applied when it had not.
            echo-red "Unknown option: $1"
            echo-white "Use '$ZELTRO_CMD --help' for the option list."
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done




# Initialize debug logging
debug "Script started: configure.sh with args: $ORIGINAL_ARGS"

# Check for and set up environment variables
# Use /etc/zeltro-cli/ as primary config location
sudo mkdir -p /etc/zeltro-cli

if ! [ -f /etc/zeltro-cli/.env ]; then

	sudo cp "$SCRIPT_DIR/../docker-stack/env.example" /etc/zeltro-cli/.env

	# Generate a random subnet for the first run. Subsequent runs default to
	# whatever's already in .env so re-running configure doesn't reshuffle IPs.
	B_CLASS=$((RANDOM % 255 + 1))
	C_CLASS=$((RANDOM % 256))
	sudo-zeltro-sed-change "/^VPC_SUBNET=/" "VPC_SUBNET=10.$B_CLASS.$C_CLASS" /etc/zeltro-cli/.env

fi

# Load existing configuration so we can use current values as defaults below.
# shellcheck disable=SC1091
source /etc/zeltro-cli/.env

# Resolve VPC_SUBNET. An explicit --vpc-subnet wins; otherwise keep whatever is
# already in .env (a random 10.B.C generated on first run). We deliberately do
# NOT ask: the generated subnet is a private /24 that never uses 10.0.x — the B
# octet is 1-255 — so it cannot collide with the 10.0.0.0/24 that most home and
# office LANs use. Asking every user to rule on a detail that almost never
# matters is friction; --vpc-subnet remains the escape hatch if it ever does.
if [[ -n "$FLAG_VPC_SUBNET" ]]; then
	if [[ ! "$FLAG_VPC_SUBNET" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		error "Invalid --vpc-subnet '$FLAG_VPC_SUBNET'. Format must be A.B.C (e.g. 10.247.177)."
	fi
	if [[ "$FLAG_VPC_SUBNET" != "$VPC_SUBNET" ]] && docker network inspect "$(zeltro_network_name)" >/dev/null 2>&1; then
		echo-yellow "The $(zeltro_network_name) network already exists at $VPC_SUBNET."
		echo-white "Changing the subnet requires recreating it: run 'zeltro uninstall'"
		echo-white "(preserves projects), then re-run 'zeltro configure --vpc-subnet $FLAG_VPC_SUBNET'."
		echo-return
	fi
	VPC_SUBNET="$FLAG_VPC_SUBNET"
fi

sudo-zeltro-sed-change "/^VPC_SUBNET=/" "VPC_SUBNET=\"$VPC_SUBNET\"" /etc/zeltro-cli/.env

# Check for and set up docker compose yaml (idempotent — never overwrites)
if ! [ -f /etc/zeltro-cli/docker-compose.yaml ]; then
	sudo cp docker-stack/docker-compose.services.yaml /etc/zeltro-cli/docker-compose.yaml
	echo-return
fi

# Check if running as root
if [[ "$(whoami)" == "root" ]]; then
	error "Do NOT run with sudo or as root! Please run as regular user (you may be prompted for sudo password when needed)."
fi

# Install Zeltro command globally
echo-return
echo-cyan "Installing Zeltro command globally..."
echo-white "Creating 'zeltro' command accessible from anywhere on your system."
echo-return

# Probe for passwordless sudo before prompting. `sudo -v` authenticates against
# every matching sudoers rule, so on hosts where NOPASSWD coexists with a
# password-requiring rule (cloud images, CI runners) it demands a password —
# and fails outright without a TTY — even though every sudo call below succeeds.
if ! sudo -n true 2>/dev/null; then
	echo-white "You'll be prompted for your password to install to /usr/local/bin"
	echo-return
	if ! sudo -v; then
		error "No sudo privileges. Root access required!"
	fi
fi

# Remove existing symlink if it exists
sudo rm -f /usr/local/bin/zeltro 2>/dev/null || true

# Create symlink to zeltro script
sudo ln -sf "$DEV_DIR/zeltro" /usr/local/bin/zeltro

# Install bash tab-completion (idempotent). bash-completion 2.x prefers the
# on-demand location /usr/share/bash-completion/completions/<cmd>; the older
# /etc/bash_completion.d is eager-sourced. Install to whichever dirs exist so
# completion loads regardless of bash-completion version. Harmless if the
# package isn't installed.
if [ -f "$DEV_DIR/completion/zeltro.bash" ]; then
	_comp_installed=0
	if [ -d /usr/share/bash-completion/completions ]; then
		sudo ln -sf "$DEV_DIR/completion/zeltro.bash" /usr/share/bash-completion/completions/zeltro 2>/dev/null && _comp_installed=1
	fi
	sudo mkdir -p /etc/bash_completion.d 2>/dev/null || true
	if [ -d /etc/bash_completion.d ]; then
		sudo ln -sf "$DEV_DIR/completion/zeltro.bash" /etc/bash_completion.d/zeltro 2>/dev/null && _comp_installed=1
	fi
	if [ "$_comp_installed" = "1" ]; then
		echo-cyan "Bash completion installed — open a new terminal (or run 'source $DEV_DIR/completion/zeltro.bash') to use it."
	fi
fi



###############################
# Create ssh key
###############################
if ! [ -f ~/.ssh/id_rsa ]; then

  if ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa; then true; fi

fi



###############################
# Set up git committer info
###############################
echo-return; echo-cyan 'Setting up Git ...'; echo-white



# Ask for a name and email, NOT "your Git name and email". These are stored as
# the git identity, but naming the tool in the prompt confused people who did
# not think of themselves as setting up git -- they are just telling Zeltro who
# they are. The --git-name/--git-email flags keep their names for compatibility.
#
# An explicit --git-name/--git-email wins in EVERY mode; only
# fall back to prompting when the flag wasn't given, git doesn't already know
# the value, and we're interactive. (These flags used to be honored only under
# --json-output, so they silently did nothing on a normal run.)
if [[ -n "$GIT_NAME" ]]; then

	git config --global user.name "$GIT_NAME"

	echo-cyan "Name set to: $GIT_NAME"

elif [[ "$JSON_OUTPUT" != "1" && "$NON_INTERACTIVE" != "1" ]] && ! git config user.name > /dev/null 2>&1; then

	echo-yellow -ne 'Full name: '

	echo-white -ne

	read GIT_NAME || GIT_NAME=""

	if ! [ -z "${GIT_NAME}" ]; then

		git config --global user.name "$GIT_NAME"

	fi

	echo-return

fi

if [[ -n "$GIT_EMAIL" ]]; then

	git config --global user.email "$GIT_EMAIL"

	echo-cyan "Email set to: $GIT_EMAIL"

elif [[ "$JSON_OUTPUT" != "1" && "$NON_INTERACTIVE" != "1" ]] && ! git config user.email > /dev/null 2>&1; then

	echo-yellow -ne 'Email address: '

	echo-white -ne

	read GIT_EMAIL || GIT_EMAIL=""

	if ! [ -z "${GIT_EMAIL}" ]; then

		git config --global user.email "$GIT_EMAIL"

	fi

	echo-return

fi

if [[ "$JSON_OUTPUT" != "1" ]]; then
    git --version; echo
fi

echo-green "Git configured!"; echo-white; echo


###############################
# Helper: Detect closest AWS region by latency
###############################
detect_closest_aws_region() {
    local regions=(
        us-east-1
        us-east-2
        us-west-1
        us-west-2
        ca-central-1
        eu-west-1
        eu-west-2
        eu-west-3
        eu-central-1
        eu-north-1
        ap-south-1
        ap-southeast-1
        ap-southeast-2
        ap-northeast-1
        ap-northeast-2
        sa-east-1
    )
    local best_region=""
    local best_time=""

    echo-return >&2
    echo "Detecting closest AWS region (latency test) ..." >&2

    for region in "${regions[@]}"; do
        local endpoint="https://ec2.${region}.amazonaws.com"
        local time_total

        time_total=$(curl -o /dev/null -s -w '%{time_total}' "$endpoint" || echo "")

        if [[ -z "$time_total" ]]; then
            echo "  $region: error (unreachable)" >&2
            continue
        fi

        echo "  $region: ${time_total}s" >&2

        if [[ -z "$best_time" ]] || awk "BEGIN {exit !($time_total < $best_time)}"; then
            best_time="$time_total"
            best_region="$region"
        fi
    done

    if [[ -n "$best_region" ]]; then
        echo "Closest AWS region by latency: $best_region" >&2
        echo "$best_region"   # stdout (captured by caller)
        return 0
    fi

    echo "Could not automatically detect closest AWS region." >&2
    return 1
}



###############################
# Set up projects directory
###############################
echo-return; echo-cyan 'Configuring projects directory ...'; echo-white

# Resolve PROJECTS_DIR: explicit flag wins, otherwise prompt with current as default.
# Current = whatever was sourced from .env, falling back to ~/zeltro-projects.
CURRENT_PROJECTS_DIR="${PROJECTS_DIR:-$HOME/zeltro-projects}"
# Expand ~ for display + use
CURRENT_PROJECTS_DIR="${CURRENT_PROJECTS_DIR/#\~/$HOME}"

if [[ -n "$FLAG_PROJECTS_DIR" ]]; then
    PROJECTS_DIR="${FLAG_PROJECTS_DIR/#\~/$HOME}"
elif [[ "$JSON_OUTPUT" != "1" && "$NON_INTERACTIVE" != "1" ]]; then
    echo-yellow "Where would you like to store your development projects?"
    echo-white "Current: $CURRENT_PROJECTS_DIR"
    echo-yellow -ne 'Enter projects directory or press Enter to keep current: '
    echo-white -ne
    read USER_PROJECTS_DIR || USER_PROJECTS_DIR=""

    if [[ -z "$USER_PROJECTS_DIR" ]]; then
        PROJECTS_DIR="$CURRENT_PROJECTS_DIR"
    else
        PROJECTS_DIR="${USER_PROJECTS_DIR/#\~/$HOME}"
    fi
    echo-return
else
    PROJECTS_DIR="$CURRENT_PROJECTS_DIR"
fi

# Create projects directory if it doesn't exist
if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo-cyan "Creating projects directory: $PROJECTS_DIR"
    mkdir -p "$PROJECTS_DIR"
fi

# Verify directory exists and is writable
if [[ ! -d "$PROJECTS_DIR" || ! -w "$PROJECTS_DIR" ]]; then
    error "ERROR: Cannot create or write to projects directory: $PROJECTS_DIR"
fi

# Agent guide for the projects directory (kept current by every later zeltro run).
zeltro_sync_projects_agents_md "$PROJECTS_DIR"

# SELinux (Fedora/RHEL): every project is bind-mounted into its container. Docker
# CE disables SELinux confinement by default (containers run as spc_t), so this
# isn't required on a stock install — but with "selinux-enabled": true in
# daemon.json an unlabeled projects dir yields Permission denied on every mount.
# Verified on Fedora 44: unlabeled user_home_t -> denied, container_file_t -> OK.
# Applied to the whole projects dir so it covers greenfield projects, adapted
# composes and installer-written composes alike. No-op where SELinux isn't
# enforcing, and cheap insurance where it is.
if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    if command -v semanage >/dev/null 2>&1; then
        echo-cyan "SELinux enforcing — labeling projects directory for container access ..."
        # -a fails if the rule already exists; that's the idempotent no-op case.
        sudo semanage fcontext -a -t container_file_t "${PROJECTS_DIR}(/.*)?" 2>/dev/null || true
        sudo restorecon -R "$PROJECTS_DIR" 2>/dev/null || true
        echo-green "Projects directory labeled container_file_t."
    else
        echo-yellow "SELinux is enforcing but 'semanage' is not installed."
        echo-white "Containers will be denied access to $PROJECTS_DIR. Install it with:"
        echo-white "  sudo dnf install policycoreutils-python-utils"
    fi
    echo-white; echo
fi

# Update .env file with projects directory (handles both commented and uncommented lines)
# MUST be quoted. /etc/zeltro-cli/.env is `source`d by bash, so an unquoted
# value containing a space becomes two words: a path like
# /Users/First Last/zeltro-projects writes
#     PROJECTS_DIR=/Users/First Last/zeltro-projects
# which assigns "/Users/First" and then tries to RUN "Last/zeltro-projects".
# Every later zeltro command then fails with "command not found" — including
# `zeltro configure` itself, which sources .env before it can rewrite it, so
# there is no way back out through the CLI.
#
# Same reasoning already applied to OPTIONAL_SERVICES in enable_service.sh.
sudo-zeltro-sed-change "/^#PROJECTS_DIR=/" "PROJECTS_DIR=\"$PROJECTS_DIR\"" /etc/zeltro-cli/.env
sudo-zeltro-sed-change "/^PROJECTS_DIR=/" "PROJECTS_DIR=\"$PROJECTS_DIR\"" /etc/zeltro-cli/.env

echo-green "Projects directory configured: $PROJECTS_DIR"
echo-white; echo





echo-white



# Docker and Node installation handled by platform-specific installers



###############################
# Shared services
###############################
# Nothing to sync into /etc/hosts — Zeltro no longer writes that file at all.
#
# Containers reach each other by name through Docker's own DNS on the shared
# network, which needs no help from the host: verified with a container
# carrying no hosts mount, which resolved every service anyway. The host
# reaches them by published port. Those entries only ever served
# host-to-container name resolution, which never worked on macOS or Windows
# because Docker keeps container IPs inside a VM there.

echo-return

echo-green "Configuration completed successfully!"; echo-white




###############################
# Start services
###############################
# Build start_services options
START_SERVICES_OPTIONS=""
if [[ "$JSON_OUTPUT" == "1" ]]; then
    START_SERVICES_OPTIONS="$START_SERVICES_OPTIONS --json-output"
fi
if [[ "$DEBUG" == "1" ]]; then
    START_SERVICES_OPTIONS="$START_SERVICES_OPTIONS --debug"
fi

if [[ "$JSON_OUTPUT" == "1" ]]; then
    # Capture start_services JSON output
    START_SERVICES_OUTPUT=$(source "$DEV_DIR/scripts/start_services.sh" $START_SERVICES_OPTIONS 2>&1)
    START_SERVICES_RESULT=$?
    
    if [ $START_SERVICES_RESULT -eq 0 ]; then
        # Merge the start_services JSON output with configure result
        echo "{\"action\": \"configure\", \"status\": \"success\", \"services_result\": $START_SERVICES_OUTPUT}"
    else
        echo "{\"action\": \"configure\", \"status\": \"success\", \"warning\": \"Services failed to start but configuration completed\", \"services_result\": null}"
    fi
    cd "$ORIG_DIR"
    exit 0
fi

# Start services first in interactive mode
source "$DEV_DIR/scripts/start_services.sh" $START_SERVICES_OPTIONS

# Then run AI agent configuration as the final step
if [[ "$JSON_OUTPUT" != "1" ]]; then
    echo-return
    echo-return
    echo-cyan "Checking AI agent ..."; echo-white
    echo-return
    # Always non-interactive, even from a terminal.
    #
    # The picker asked people to choose a CLI agent, then a model, then an API
    # base and key, in the middle of first-time setup and before they had any
    # reason to care. It read as a required decision rather than an optional
    # one, and it is the step people got stuck on.
    #
    # The default — claude, no model override — is right for almost everyone,
    # and `zeltro ai-set` exists for the rest. A closed stdin makes ai_set keep
    # whatever is already configured and print it, so this still confirms what
    # the agent is without demanding an answer.
    "$DEV_DIR/scripts/ai_set.sh" < /dev/null
fi

cd "$ORIG_DIR"
