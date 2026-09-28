#!/bin/bash

# Zeltro CLI Installer Script
# Complete installation of Zeltro CLI with all dependencies

set -e

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --help)
            echo "Zeltro CLI Ubuntu Installer"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help           Show this help message"
            echo ""
            echo "This installer automatically detects if Docker is already available"
            echo "(e.g., from Docker Desktop) and skips Docker installation if found."
            exit 0
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/usr/local/share/zeltro-cli"
CONFIG_DIR="/etc/zeltro-cli"
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

echo -e "${BLUE}Zeltro CLI Complete Installer${NC}"
echo "=============================="

# Ensure we're in a valid directory (fix for "Unable to read current working directory" error)
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

echo

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
ZELTRO_INSTALLER_URL="${ZELTRO_INSTALLER_URL:-https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-ubuntu.sh}"
# /dev/tty must be OPENABLE, not merely present: over `ssh host cmd` with no -t
# the device node exists but there is no controlling terminal, so the redirect
# below failed and, under set -e, killed the install before it started.
if [ ! -t 0 ] && [ -z "${ZELTRO_INSTALLER_REEXEC:-}" ] && ( exec < /dev/tty ) 2>/dev/null; then
    _self="$(mktemp -t zeltro-install.XXXXXX)" || _self=""
    if [ -n "$_self" ] && curl -fsSL "$ZELTRO_INSTALLER_URL" -o "$_self" 2>/dev/null && [ -s "$_self" ]; then
        export ZELTRO_INSTALLER_REEXEC=1
        exec bash "$_self" "$@" < /dev/tty
    fi
    echo "Warning: running from a pipe. If anything asks for a password it may fail." >&2
    echo "         If that happens, download and run instead:" >&2
    echo "           curl -fsSL $ZELTRO_INSTALLER_URL -o /tmp/install.sh" >&2
    echo "           bash /tmp/install.sh" >&2
fi

if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}Error: This script should not be run as root${NC}"
   echo "Please run as a regular user. The script will ask for sudo when needed."
   exit 1
fi

# Check for Ubuntu/Debian
if ! command -v apt-get &> /dev/null; then
    echo -e "${RED}Error: This installer requires Ubuntu/Debian (apt-get)${NC}"
    echo "For other distributions, please install dependencies manually:"
    echo "- Docker"
    echo "- Node.js 16+"
    echo "- Git"
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

# If a docker.list from a previous run uses the wrong codename, fix it before apt-get update
if [ -f /etc/apt/sources.list.d/docker.list ]; then
    UBUNTU_BASE_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    if ! grep -q "$UBUNTU_BASE_CODENAME" /etc/apt/sources.list.d/docker.list; then
        echo -e "${YELLOW}Fixing incorrect Docker apt source from a previous install attempt...${NC}"
        sudo rm -f /etc/apt/sources.list.d/docker.list
    fi
fi

###############################
# Update package lists
###############################
echo -e "${BLUE}Updating package lists...${NC}"
sudo apt-get update -y -q

###############################
# Add Ubuntu repos
###############################
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse   # harmless if already enabled
sudo apt-get update -y -q

###############################
# Install basic packages
###############################
echo -e "${BLUE}Installing basic packages...${NC}"
sudo apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https \
    git jq software-properties-common trash-cli acl unzip \
    imagemagick librsvg2-bin

###############################
# Ensure local bin directory and PATH
###############################
mkdir -p "$HOME/.local/bin"
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

###############################
# Install Docker
###############################
# Check if Docker is already available (e.g., from Docker Desktop)
if command -v docker &> /dev/null && docker --version &> /dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null | head -n1)
    echo -e "${GREEN}✓ Docker already available: $DOCKER_VERSION${NC}"
    
    # Check if it's Docker Desktop (common on Windows/Mac)
    if docker context ls 2>/dev/null | grep -q "desktop-linux\|default.*docker-desktop"; then
        echo -e "${CYAN}  Detected Docker Desktop integration${NC}"
    fi
elif ! command -v docker &> /dev/null; then
    echo -e "${BLUE}Installing Docker...${NC}"
    
    # Remove any old Docker packages
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y $pkg 2>/dev/null || true
    done
    
    # Add Docker's official GPG key and repository
    UBUNTU_BASE_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # If a docker.list already exists but uses the wrong codename, replace it
    if [ -f /etc/apt/sources.list.d/docker.list ] && ! grep -q "$UBUNTU_BASE_CODENAME" /etc/apt/sources.list.d/docker.list; then
        echo -e "${YELLOW}Replacing incorrect Docker apt source (wrong distro codename detected)...${NC}"
        sudo rm -f /etc/apt/sources.list.d/docker.list
    fi

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $UBUNTU_BASE_CODENAME stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update -y -q
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    echo -e "${GREEN}✓ Docker installed${NC}"
else
    echo -e "${RED}Error: Docker command version check failed${NC}"
    exit 1
fi

# Add user to docker group even if docker is already installed
sudo usermod -aG docker "$USER"
echo -e "${YELLOW}Note: You may need to log out and back in for Docker group changes to take effect. Desktop users: if logging out does not work, a full reboot is required.${NC}"

###############################
# Install Node.js and NPM via NVM
###############################
if ! command -v node &> /dev/null || [[ $(node -v | cut -d'v' -f2 | cut -d'.' -f1) -lt 16 ]]; then
    echo -e "${BLUE}Installing Node.js (via NVM)...${NC}"

    # Install NVM if not present
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
if ! command -v gh &> /dev/null; then
    echo -e "${BLUE}Installing GitHub CLI...${NC}"
    
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    
    sudo apt-get update -y -q
    sudo apt-get install -y gh
    
    echo -e "${GREEN}✓ GitHub CLI installed${NC}"
else
    echo -e "${GREEN}✓ GitHub CLI already installed${NC}"
fi

###############################
# Clean up
###############################
sudo apt-get autoremove -y -q

###############################
# Install Zeltro CLI
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
    # Check if already installed
    if [[ -d "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}Zeltro CLI is already installed.${NC}"

        # Check if we're running in a pipe (curl | bash) or interactive terminal
        if [ -t 0 ]; then
            # Interactive terminal - ask user
            read -p "Do you want to update it? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Installation cancelled."
                exit 0
            fi
        else
            # Running via pipe (curl | bash) - auto-update
            echo -e "${CYAN}Running via curl | bash - automatically updating...${NC}"
            sleep 2
        fi

        echo -e "${YELLOW}Updating existing installation...${NC}"

        # Configuration is now stored in /etc/zeltro-cli/ and will persist across reinstalls
        sudo rm -rf "$INSTALL_DIR"
    fi

    # Create installation directory
    echo -e "${BLUE}Creating installation directory...${NC}"
    sudo mkdir -p "$INSTALL_DIR"

    # Clone repository
    echo -e "${BLUE}Downloading Zeltro CLI...${NC}"
    sudo git clone "$REPO_URL" "$INSTALL_DIR"

    # Set proper permissions
    echo -e "${BLUE}Setting permissions...${NC}"
    # Keep most files accessible to users, only set execute permissions for scripts
    sudo chmod +x "$INSTALL_DIR/src/zeltro"
    sudo chmod +x "$INSTALL_DIR/src/scripts"/*.sh
    # Make sure current user can read/write config files
    sudo chown -R "$(whoami):$(id -gn)" "$INSTALL_DIR"
    # Only the main binary needs special permissions
    sudo chown root:root "$INSTALL_DIR/src/zeltro"

    # Create symlink
    echo -e "${BLUE}Creating command symlink...${NC}"
    sudo ln -sf "$INSTALL_DIR/src/zeltro" "$BIN_DIR/zeltro"
fi

###############################
# Configure Docker service
###############################
echo -e "${BLUE}Configuring Docker service...${NC}"

# Enable and start Docker service
if ! systemctl is-enabled docker.service >/dev/null 2>&1; then
    sudo systemctl enable docker.service
fi

if ! systemctl is-active docker.service >/dev/null 2>&1; then
    sudo systemctl start docker.service
fi

###############################
# Final verification and instructions
###############################
echo
echo -e "${GREEN}🎉 Installation Complete!${NC}"
echo "=========================="

# Verify installation
if command -v zeltro &> /dev/null; then
    echo -e "${GREEN}✓ Zeltro CLI installed successfully${NC}"
    
    # Configuration is now permanently stored in /etc/zeltro-cli/ - no restoration needed
    
    echo
    echo -e "${CYAN}🚀 Next Steps:${NC}"
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
    echo -e "${RED}✗ Installation failed${NC}"
    echo "The zeltro command is not available in PATH."
    exit 1
fi
