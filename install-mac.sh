#!/bin/bash

# Zeltro CLI Mac Installer Script
# Complete installation of Zeltro CLI with all dependencies for macOS

set -e

# Clear screen and suppress script echoing
clear 2>/dev/null || true

# Immediate feedback to user (prevents showing script content)
echo "🚀 Starting Zeltro CLI installation..."

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

sleep 1

# Check for dry-run mode
DRY_RUN=0
if [[ "$1" == "--dry-run" || "$1" == "--test" ]]; then
    DRY_RUN=1
    echo "🧪 DRY RUN MODE - No actual installations will be performed"
    echo
fi

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

echo -e "${BLUE}Zeltro CLI Mac Installer${NC}"
echo "========================"
echo

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This installer is for macOS only${NC}"
    echo "For Linux, use: curl -fsSL https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install.sh | bash"
    exit 1
fi

# Check if running as root
# Re-exec from a real file when we were piped into bash.
#
# The documented install is `curl ... | bash`, which makes STDIN THE SCRIPT
# ITSELF. Any password prompt or `read` during the run then consumes installer
# source instead of user input. Observed on a real Mac: Homebrew's cask install
# ran its own sudo, sudo read the "password" from stdin, ate three lines of this
# file as three failed attempts, and corrupted everything after it --
#
#     sudo ln -sf "$INSTALL_DIR/src/podiusudo: 3 incorrect password attempts
#
# -- with Docker Desktop rolled back and nothing installed. The user's password
# was never wrong.
#
# Redirecting stdin in place is not an option: bash is still reading the script
# from it. So fetch a real copy and re-exec with stdin on the terminal.
ZELTRO_INSTALLER_URL="${ZELTRO_INSTALLER_URL:-https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-mac.sh}"
# /dev/tty must be OPENABLE, not merely present: over `ssh host cmd` with no -t
# the device node exists but there is no controlling terminal, so the redirect
# below failed and, under set -e, killed the install before it started.
if [ ! -t 0 ] && [ -z "${ZELTRO_INSTALLER_REEXEC:-}" ] && ( exec < /dev/tty ) 2>/dev/null; then
    _self="$(mktemp -t zeltro-install)" || _self=""
    if [ -n "$_self" ] && curl -fsSL "$ZELTRO_INSTALLER_URL" -o "$_self" 2>/dev/null && [ -s "$_self" ]; then
        export ZELTRO_INSTALLER_REEXEC=1
        exec bash "$_self" "$@" < /dev/tty
    fi
    # Could not re-exec (offline, or no terminal). Carry on rather than refuse,
    # but say what will happen, because the failure is otherwise baffling.
    echo "Warning: running from a pipe. If anything asks for a password it may fail." >&2
    echo "         If that happens, download and run instead:" >&2
    echo "           curl -fsSL $ZELTRO_INSTALLER_URL -o /tmp/install-mac.sh" >&2
    echo "           bash /tmp/install-mac.sh" >&2
fi

if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}Error: This script should not be run as root${NC}"
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
# Xcode Command Line Tools
###############################
# Must come before Homebrew. Homebrew cannot install without the CLT, and on a
# clean Mac /usr/bin/git is only a stub that opens a GUI dialog instead of
# running git. Homebrew triggers that dialog, does not wait for it, and dies on
# `git init` -- after having already created a half-built /opt/homebrew. The
# user is left with someone else's error message, no explanation, and a dirty
# tree that the next attempt starts from.
#
# Checking here means we fail before writing anything, and say why.
clt_present() {
    # Must NOT run /usr/bin/git to test this. Without the tools installed that
    # path is a stub whose only behaviour is to open the "install developer
    # tools" dialog -- so probing for the tools with it POPS THE DIALOG WE ARE
    # trying to avoid, on exactly the machines where the check matters.
    #
    # `xcode-select -p` is safe: it prints the path or fails, and never
    # triggers the installer. Checking for the real binary underneath it
    # confirms usability without executing anything.
    local dir
    dir="$(xcode-select -p 2>/dev/null)" || return 1
    [ -n "$dir" ] && [ -x "$dir/usr/bin/git" ]
}

if clt_present; then
    echo -e "${GREEN}✓ Xcode Command Line Tools already installed${NC}"
elif [ "$DRY_RUN" = "1" ]; then
    echo "  [DRY RUN] Would install Xcode Command Line Tools"
else
    echo -e "${BLUE}Installing Xcode Command Line Tools...${NC}"
    echo "This is a large download and can take several minutes."

    # This marker is what makes the CLT appear in `softwareupdate --list`.
    # Without it the tools can only be installed through the GUI dialog, which
    # is no use over SSH, in CI, or in any unattended run.
    CLT_MARKER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    sudo touch "$CLT_MARKER"

    CLT_LABEL="$(softwareupdate --list 2>/dev/null \
        | grep -E 'Label: Command Line Tools' \
        | sed 's/^.*Label: //' \
        | sed 's/[[:space:]]*$//' \
        | tail -1)"

    if [ -n "$CLT_LABEL" ]; then
        echo -e "${BLUE}Found: $CLT_LABEL${NC}"
        sudo softwareupdate --install "$CLT_LABEL" --verbose || true
    fi

    sudo rm -f "$CLT_MARKER"

    if clt_present; then
        echo -e "${GREEN}✓ Xcode Command Line Tools installed${NC}"
    else
        echo
        echo -e "${RED}Error: Xcode Command Line Tools could not be installed automatically.${NC}"
        echo
        if [ -z "$CLT_LABEL" ]; then
            # The common cause, and not obvious from anything macOS reports.
            echo -e "${YELLOW}Apple's update server is not offering the Command Line Tools for this${NC}"
            echo -e "${YELLOW}version of macOS. That usually means macOS itself is behind: Apple${NC}"
            echo -e "${YELLOW}publishes the tools only for the current release, so a Mac a few point${NC}"
            echo -e "${YELLOW}releases back gets an install dialog that can never succeed.${NC}"
            echo
            echo -e "You are on macOS $(sw_vers -productVersion)."
            echo
        fi
        echo -e "${CYAN}Fix it either way, then re-run this installer:${NC}"
        echo
        echo -e "  ${BLUE}1. Update macOS${NC} (System Settings > General > Software Update),"
        echo -e "     or from this terminal:"
        echo -e "       ${BLUE}sudo softwareupdate --install --all --restart${NC}"
        echo
        echo -e "  ${BLUE}2. Or install the tools by hand${NC} — no macOS update needed:"
        echo -e "       ${BLUE}https://developer.apple.com/download/all/${NC}"
        echo -e "     Sign in, download \"Command Line Tools for Xcode\", open the .dmg."
        echo
        echo -e "${CYAN}Nothing has been installed or changed on this Mac.${NC}"
        exit 1
    fi
fi

###############################
# Install Homebrew if not present
###############################
if ! command -v brew &> /dev/null; then
    echo -e "${BLUE}Installing Homebrew...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would install Homebrew"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Add Homebrew to PATH for this session
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        # Apple Silicon Mac
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        # Intel Mac
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    echo -e "${GREEN}✓ Homebrew installed${NC}"
else
    echo -e "${GREEN}✓ Homebrew already installed${NC}"
fi

###############################
# Update Homebrew
###############################
echo -e "${BLUE}Updating Homebrew...${NC}"
if [ "$DRY_RUN" = "1" ]; then
    echo "  [DRY RUN] Would update Homebrew"
else
    brew update
fi

###############################
# Install Docker Desktop
###############################
if ! command -v docker &> /dev/null; then
    echo -e "${BLUE}Installing Docker Desktop...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would install Docker Desktop via: brew install --cask docker"
    else
        brew install --cask docker
        
        echo -e "${GREEN}✓ Docker Desktop installed${NC}"
        echo -e "${YELLOW}⚠️  Docker Desktop must be running before Zeltro can start anything${NC}"

        # The documented install is `curl ... | bash`, so stdin is the script
        # itself. An unguarded `read` there does not pause — it consumes the
        # bytes bash has not parsed yet, eating part of the installer. Read
        # from the terminal instead, and where there is no terminal (piped,
        # CI, ssh without -t) print what to do rather than blocking on input
        # nobody can supply.
        if [ -e /dev/tty ]; then
            echo -e "${BLUE}Starting Docker Desktop...${NC}"
            open -a Docker 2>/dev/null || true
            echo "Press any key once Docker Desktop has finished starting..."
            read -n 1 -s < /dev/tty 2>/dev/null || sleep 5
            echo
        else
            echo -e "${YELLOW}   Start it with: open -a Docker${NC}"
            echo -e "${YELLOW}   Then re-run any zeltro command once it is up.${NC}"
        fi
    fi
else
    echo -e "${GREEN}✓ Docker already installed${NC}"
fi

###############################
# Install Node.js and NPM via NVM
###############################
if ! command -v node &> /dev/null || [[ $(node -v | cut -d'v' -f2 | cut -d'.' -f1) -lt 16 ]]; then
    echo -e "${BLUE}Installing Node.js (via NVM)...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would install NVM and latest LTS Node.js"
    else
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
    fi
else
    echo -e "${GREEN}✓ Node.js already installed${NC}"
fi

###############################
# Install additional tools
###############################
echo -e "${BLUE}Installing additional tools...${NC}"

# Install git if not present (usually pre-installed)
if ! command -v git &> /dev/null; then
    brew install git
fi

# Install other useful tools
echo -e "Installing: jq, trash, imagemagick, librsvg ..."
brew install jq trash imagemagick librsvg >/dev/null 2>&1 && echo -e "${GREEN}✓ Additional tools installed${NC}" || echo -e "${YELLOW}⚠️ Some tools may have failed to install${NC}"

###############################
# Ensure local bin directory and PATH
###############################
mkdir -p "$HOME/.local/bin"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" ]] && ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$rc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    fi
done

# Install GitHub CLI (optional but recommended)
if ! command -v gh &> /dev/null; then
    echo -e "Installing GitHub CLI..."
    brew install gh >/dev/null 2>&1 && echo -e "${GREEN}✓ GitHub CLI installed${NC}" || echo -e "${YELLOW}⚠️ GitHub CLI installation failed${NC}"
else
    echo -e "${GREEN}✓ GitHub CLI already installed${NC}"
fi



###############################
# Install / Update Zeltro CLI
###############################
echo -e "${CYAN}Installing Zeltro CLI...${NC}"

if [[ -n "$LOCAL_REPO_DIR" ]]; then
    echo -e "${GREEN}✓ Detected existing Zeltro CLI checkout${NC}"
    echo -e "${CYAN}Using local directory:${NC} $LOCAL_REPO_DIR"

    desired_target="$(cd "$LOCAL_REPO_DIR" 2>/dev/null && pwd -P)"
    current_target="$(cd "$INSTALL_DIR" 2>/dev/null && pwd -P || true)"

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
        if [ "$DRY_RUN" = "1" ]; then
            echo "  [DRY RUN] Would link $INSTALL_DIR -> $desired_target"
        else
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
    fi

    echo -e "${BLUE}Creating command symlink...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would symlink $BIN_DIR/zeltro -> $INSTALL_DIR/src/zeltro"
    else
        sudo chmod +x "$INSTALL_DIR/src/zeltro" 2>/dev/null || true
        sudo ln -sf "$INSTALL_DIR/src/zeltro" "$BIN_DIR/zeltro"
    fi
else
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
        if [ "$DRY_RUN" = "1" ]; then
            echo "  [DRY RUN] Would remove existing install at $INSTALL_DIR"
        else
            sudo rm -rf "$INSTALL_DIR"
        fi
    fi

    # Create installation directory
    echo -e "${BLUE}Creating installation directory...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would create $INSTALL_DIR"
    else
        sudo mkdir -p "$INSTALL_DIR"
    fi

    # Clone repository
    echo -e "${BLUE}Downloading Zeltro CLI...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would clone $REPO_URL to $INSTALL_DIR"
    else
        sudo git clone "$REPO_URL" "$INSTALL_DIR"
    fi

    # Set proper permissions
    echo -e "${BLUE}Setting permissions...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would chmod/chown installed files"
    else
        # Keep most files accessible to users, only set execute permissions for scripts
        sudo chmod +x "$INSTALL_DIR/src/zeltro"
        sudo chmod +x "$INSTALL_DIR/src/scripts"/*.sh
        # Make sure current user can read/write config files
        sudo chown -R "$(whoami):$(id -gn)" "$INSTALL_DIR"
        # Only the main binary needs special permissions
        sudo chown root:wheel "$INSTALL_DIR/src/zeltro"
    fi

    # Create symlink
    echo -e "${BLUE}Creating command symlink...${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "  [DRY RUN] Would symlink $BIN_DIR/zeltro -> $INSTALL_DIR/src/zeltro"
    else
        sudo ln -sf "$INSTALL_DIR/src/zeltro" "$BIN_DIR/zeltro"
    fi
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
    
    # Check Docker status
    if ! docker info &>/dev/null; then
        echo -e "${YELLOW}⚠️  Docker Desktop needs to be running${NC}"
        echo -e "   Please start Docker Desktop from Applications"
    fi
    
    echo
    echo -e "${CYAN}ℹ️  Note: Any 'Outdated Formulae' warnings above are normal${NC}"
    echo -e "   Your installation is complete and working. You can upgrade later with 'brew upgrade'"
    echo
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo -e "  1. ${YELLOW}Make sure Docker Desktop is running${NC}"
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
