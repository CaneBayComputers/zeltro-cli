#!/bin/bash

# Zeltro CLI Arch Linux Installer Script
# Complete installation of Zeltro CLI with all dependencies for Arch-based systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/usr/local/share/zeltro-cli"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/CaneBayComputers/zeltro-cli.git"
NVM_FALLBACK_VERSION="v0.40.1"

get_latest_nvm_version() {
    local tag
    tag="$(
        curl -fsSL "https://api.github.com/repos/nvm-sh/nvm/releases/latest" 2>/dev/null | \
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | \
            head -n 1
    )"
    if [[ -n "$tag" ]]; then
        echo "$tag"
        return 0
    fi
    return 1
}

echo -e "${BLUE}Zeltro CLI Arch Installer${NC}"
echo "========================="
echo

# Ensure we're in a valid directory
if ! pwd &>/dev/null; then
    echo "⚠️  Current directory is invalid, changing to home directory..."
    cd "$HOME" || cd /tmp
fi

# Detect a local Zeltro CLI checkout (for development installs)
# Prefer the directory this script lives in, so running it by path from
# somewhere else (./zeltro-cli/install-ubuntu.sh) still finds the checkout
# instead of silently re-cloning master over the top of it. Falls back to the
# working directory. Piped through `curl | bash` there is no script file on
# disk, so neither candidate matches and the clone path below runs — which is
# the intended behaviour for that install method.
SELF_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
fi
CURRENT_DIR="$(pwd -P)"

LOCAL_REPO_DIR=""
for _candidate in "$SELF_DIR" "$CURRENT_DIR"; do
    if [[ -n "$_candidate" \
        && -f "$_candidate/README.md" \
        && -f "$_candidate/src/zeltro" \
        && -f "$_candidate/src/scripts/functions.sh" ]]; then
        LOCAL_REPO_DIR="$_candidate"
        break
    fi
done

# Basic help
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Zeltro CLI Arch Linux Installer"
            echo
            echo "Usage: $0 [options]"
            echo
            echo "Options:"
            echo "  --help, -h   Show this help message"
            echo
            echo "This installer targets Arch Linux and Arch-based distributions."
            exit 0
            ;;
    esac
done

# Check for Arch (or at least pacman)
if ! command -v pacman >/dev/null 2>&1; then
    echo -e "${RED}Error: This installer requires Arch Linux (pacman).${NC}"
    echo "For Ubuntu/Debian use install-ubuntu.sh, or install dependencies manually."
    exit 1
fi

# Check if running as root
# Re-exec from a real file when we were piped into bash.
#
# The documented install is `curl ... | bash`, which makes STDIN THE SCRIPT
# ITSELF. Any password prompt or `read` during the run then consumes installer
# source rather than user input. Seen for real on macOS: a mid-run sudo read
# three lines of the installer as three failed password attempts and corrupted
# everything after it. The same shape applies here -- there are dozens of sudo
# calls below, and any one of them can prompt if the timestamp lapses.
#
# Redirecting stdin in place will not work: bash is still reading the script
# from it. So fetch a real copy and re-exec with stdin on the terminal.
ZELTRO_INSTALLER_URL="${ZELTRO_INSTALLER_URL:-https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-arch.sh}"
# /dev/tty must be OPENABLE, not merely present: over `ssh host cmd` with no -t
# the device node exists but there is no controlling terminal, so the redirect
# below failed and, under set -e, killed the install before it started.
if [ ! -t 0 ] && [ -z "${ZELTRO_INSTALLER_REEXEC:-}" ]; then
    # Where the run's stdin comes from: the terminal if one can be opened,
    # otherwise nothing. With no terminal (ssh without -t, a CI job, the app
    # installing on a remote) this used to skip the re-exec, so brew/apt read
    # the rest of this script from the pipe; bash then hit EOF and exited 0
    # with nothing installed.
    if ( exec < /dev/tty ) 2>/dev/null; then _stdin=/dev/tty; else _stdin=/dev/null; fi
    if [ -f "${BASH_SOURCE[0]:-}" ]; then
        # Run from a file, not a pipe: stdin is not the script, so replace it
        # in place (and keep running this copy, not the one on master).
        exec < "$_stdin"
    else
        _self="$(mktemp -t zeltro-install.XXXXXX)" || _self=""
        if [ -n "$_self" ] && curl -fsSL "$ZELTRO_INSTALLER_URL" -o "$_self" 2>/dev/null && [ -s "$_self" ]; then
            export ZELTRO_INSTALLER_REEXEC=1
            exec bash "$_self" "$@" < "$_stdin"
        fi
        echo "Warning: running from a pipe. If anything asks for a password it may fail." >&2
        echo "         If that happens, download and run instead:" >&2
        echo "           curl -fsSL $ZELTRO_INSTALLER_URL -o /tmp/install.sh" >&2
        echo "           bash /tmp/install.sh" >&2
    fi
fi

if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}Error: This script should not be run as root.${NC}"
   echo "Please run as a regular user. The script will ask for sudo when needed."
   exit 1
fi

# Request sudo upfront with a clear explanation, then keep credentials alive.
# Probe with `sudo -n` first: systems that grant passwordless sudo (cloud
# images, CI runners) usually ALSO carry a password-requiring rule, and plain
# `sudo -v` authenticates against every matching rule — so it prompts even
# though each individual command would run fine without a password.
if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}✓ Passwordless sudo available${NC}"
else
    echo
    echo -e "${YELLOW}Zeltro needs sudo to install system packages and configure Docker.${NC}"
    echo -e "${YELLOW}You'll be asked for your password once — it won't be asked again during the install.${NC}"
    echo
    if ! sudo -v; then
        echo -e "${RED}Error: sudo access is required. Please run as a user with sudo privileges.${NC}"
        exit 1
    fi
fi
# `|| true` matters: set -e is inherited by this subshell, and `sudo -n -v`
# fails wherever a password-requiring sudoers rule coexists with NOPASSWD.
# Without it the keepalive dies instantly and the EXIT trap below kills a
# dead PID.
( while true; do sudo -n -v 2>/dev/null || true; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!
# Preserve the real exit status — a bare `exit` here would return the status
# of `kill`, reporting failure after a fully successful install.
trap 'rc=$?; kill $SUDO_KEEPALIVE_PID 2>/dev/null || true; exit $rc' INT TERM EXIT

echo -e "${CYAN}Installing system dependencies...${NC}"

###############################
# Update package databases
###############################
# Minimal Arch environments (cloud images, containers, fresh chroots) can ship
# without an initialized pacman keyring. Every install then dies with
# "required key missing from keyring" / "keyring is not writable". A normal
# desktop install already has this, so the probe skips it.
if ! sudo pacman-key --list-keys >/dev/null 2>&1; then
    echo -e "${BLUE}Initializing pacman keyring...${NC}"
    sudo pacman-key --init
    sudo pacman-key --populate archlinux
fi

echo -e "${BLUE}Updating package databases...${NC}"
sudo pacman -Syu --noconfirm

###############################
# Install core tools
###############################
echo -e "${BLUE}Installing base packages...${NC}"
# `docker-compose` is a SEPARATE package on Arch — it ships the Compose v2 CLI
# plugin that provides `docker compose`. Zeltro drives every project through
# `docker compose`, so without it `zeltro start-services` dies with
# "unknown shorthand flag: 'd' in -d".
sudo pacman -S --noconfirm --needed \
    git curl jq unzip \
    docker docker-compose \
    trash-cli \
    imagemagick librsvg

###############################
# Ensure local bin directory and PATH
###############################
mkdir -p "$HOME/.local/bin"
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

###############################
# Install Node.js and NPM via NVM
###############################
if ! command -v node &> /dev/null || [[ $(node -v | cut -d'v' -f2 | cut -d'.' -f1) -lt 16 ]]; then
    echo -e "${BLUE}Installing Node.js (via NVM)...${NC}"

    if [ ! -d "$HOME/.nvm" ]; then
        NVM_VERSION="$(get_latest_nvm_version || echo "$NVM_FALLBACK_VERSION")"
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    fi

    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1090
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v nvm >/dev/null 2>&1; then
        nvm install --lts
        nvm alias default 'lts/*'
        echo -e "${GREEN}✓ Node.js $(node -v) and NPM $(npm -v) installed via NVM${NC}"
    else
        echo -e "${YELLOW}⚠️ NVM did not initialize correctly; please install Node.js manually.${NC}"
    fi
else
    echo -e "${GREEN}✓ Node.js already installed${NC}"
fi

###############################
# Install GitHub CLI (optional but recommended)
###############################
if ! command -v gh >/dev/null 2>&1; then
    echo -e "${BLUE}Installing GitHub CLI...${NC}"
    if sudo pacman -S --noconfirm --needed github-cli; then
        echo -e "${GREEN}✓ GitHub CLI installed${NC}"
    else
        echo -e "${YELLOW}⚠️ GitHub CLI package not found or failed to install. Skipping.${NC}"
    fi
else
    echo -e "${GREEN}✓ GitHub CLI already installed${NC}"
fi

###############################
# Configure Docker
###############################
echo -e "${BLUE}Configuring Docker...${NC}"

# A full `pacman -Syu` can replace the running kernel. Its modules directory is
# swapped out from under it, so netfilter modules can no longer be loaded and
# dockerd dies with an opaque "iptables: Could not fetch rule set generation id:
# Invalid argument". Nothing fixes that but a reboot — detect it and say so
# plainly instead of failing on a systemd error the user has to go dig out.
KERNEL_REBOOT_REQUIRED=0
if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    KERNEL_REBOOT_REQUIRED=1
    echo
    echo -e "${YELLOW}The system upgrade replaced the running kernel ($(uname -r)).${NC}"
    echo -e "${YELLOW}Docker cannot start until this machine reboots.${NC}"
    echo
fi

# Enable and start Docker service
if ! systemctl is-enabled docker.service >/dev/null 2>&1; then
    sudo systemctl enable docker.service
fi

if [ "$KERNEL_REBOOT_REQUIRED" = "1" ]; then
    echo -e "${CYAN}Skipping Docker startup until after the reboot.${NC}"
elif ! systemctl is-active docker.service >/dev/null 2>&1; then
    sudo systemctl start docker.service
fi

# Add user to docker group
if ! id -nG "$USER" | grep -q "\bdocker\b"; then
    sudo usermod -aG docker "$USER"
    echo -e "${YELLOW}You were added to the 'docker' group. You may need to log out and back in for this to take effect. Desktop users: if logging out does not work, a full reboot is required.${NC}"
fi

###############################
# Install / Update Zeltro CLI
###############################
echo -e "${CYAN}Installing Zeltro CLI...${NC}"

if [[ -n "$LOCAL_REPO_DIR" ]]; then
    echo -e "${GREEN}✓ Detected existing Zeltro CLI checkout${NC}"
    echo -e "${CYAN}Using local directory:${NC} $LOCAL_REPO_DIR"

    desired_target="$(readlink -f "$LOCAL_REPO_DIR")"
    current_target="$(readlink -f "$INSTALL_DIR" 2>/dev/null || true)"

    if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
        if [[ -n "$current_target" && "$current_target" != "$desired_target" ]]; then
            echo -e "${YELLOW}Zeltro CLI is already installed at:${NC} $INSTALL_DIR -> $current_target"

            if [ -t 0 ]; then
                read -p "Do you want to repoint it to this local checkout? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Installation cancelled."
                    exit 0
                fi
            else
                echo -e "${CYAN}Non-interactive run - automatically repointing to local checkout...${NC}"
                sleep 1
            fi
        fi
    fi

    if [[ "$desired_target" == "$INSTALL_DIR" ]]; then
        echo -e "${BLUE}Using existing directory at installation path...${NC}"
    else
        echo -e "${BLUE}Linking installation directory to local checkout...${NC}"
        sudo mkdir -p "$(dirname "$INSTALL_DIR")"

        if [[ -L "$INSTALL_DIR" ]]; then
            sudo ln -sfn "$desired_target" "$INSTALL_DIR"
        elif [[ -e "$INSTALL_DIR" ]]; then
            backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
            echo -e "${YELLOW}Backing up existing install to:${NC} $backup_dir"
            sudo mv "$INSTALL_DIR" "$backup_dir"
            sudo ln -s "$desired_target" "$INSTALL_DIR"
        else
            sudo ln -s "$desired_target" "$INSTALL_DIR"
        fi
    fi

    echo -e "${BLUE}Creating command symlink...${NC}"
    sudo chmod +x "$INSTALL_DIR/src/zeltro" 2>/dev/null || true
    sudo ln -sf "$INSTALL_DIR/src/zeltro" "$BIN_DIR/zeltro"
else
    if [[ -d "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}Zeltro CLI is already installed.${NC}"
        if [ -t 0 ]; then
            read -p "Do you want to update it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Installation cancelled."
                exit 0
            fi
        else
            echo -e "${CYAN}Running in non-interactive mode - updating existing installation...${NC}"
        fi
        echo -e "${YELLOW}Updating existing installation...${NC}"
        sudo rm -rf "$INSTALL_DIR"
    fi

    sudo mkdir -p "$INSTALL_DIR"
    echo -e "${BLUE}Cloning repository...${NC}"
    sudo git clone "$REPO_URL" "$INSTALL_DIR"

    echo -e "${BLUE}Setting permissions...${NC}"
    sudo chmod +x "$INSTALL_DIR/src/zeltro"
    sudo chmod +x "$INSTALL_DIR/src/scripts"/*.sh
    sudo chown -R "$(whoami):$(id -gn)" "$INSTALL_DIR"
    sudo chown root:root "$INSTALL_DIR/src/zeltro"

    echo -e "${BLUE}Creating command symlink...${NC}"
    sudo ln -sf "$INSTALL_DIR/src/zeltro" "$BIN_DIR/zeltro"
fi

###############################
# Final verification and instructions
###############################
echo
echo -e "${GREEN}🎉 Installation Complete!${NC}"
echo "=========================="

if command -v zeltro >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Zeltro CLI installed successfully${NC}"
    echo
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    if [ "${KERNEL_REBOOT_REQUIRED:-0}" = "1" ]; then
        echo -e "  0. ${YELLOW}REBOOT NOW${NC} — the system upgrade replaced the running kernel, so Docker cannot start until you do (${BLUE}sudo reboot${NC})"
    fi
    echo -e "  1. ${YELLOW}Log out and back in${NC} so Docker group permissions take effect — SSH users: just reconnect; desktop users: reboot if a re-login does not work"
    echo -e "  2. Run ${BLUE}zeltro configure${NC} to set up your development environment"
    echo -e "  3. Create your first project:"
    echo -e "       ${BLUE}zeltro create${NC} \"A task tracker with user login\""
    echo -e "     or use a specific framework:"
    echo -e "       ${BLUE}zeltro new laravel my-project${NC}"
    echo
    echo -e "${CYAN}📖 Documentation:${NC}"
    echo "   https://github.com/CaneBayComputers/zeltro-cli"
    echo
    echo -e "${CYAN}🗑️  To Uninstall:${NC}"
    echo -e "  ${BLUE}zeltro uninstall${NC}"
    echo
else
    echo -e "${RED}✗ Installation failed.${NC}"
    echo "The zeltro command is not available in PATH."
    exit 1
fi
