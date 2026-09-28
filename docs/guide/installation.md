---
title: Installation
nav_order: 2
---

# Installation

Zeltro runs on Linux and macOS. Windows support is on its way: an installer is
coming, and the WSL2 route is in preview (see [Windows](#windows) below).

Run every installer as your normal user, not as root. It asks for your sudo
password when it needs it.

---

## One-line install

These lines install the CLI only. To get the desktop app as well, use the
lines under [The desktop app](#the-desktop-app) instead. They install the CLI
for you if it is missing.

| Platform | Command |
|---|---|
| Ubuntu 22.04 / 24.04 / 26.04, and Ubuntu-based distros (Linux Mint, Pop!_OS) | `curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/ubuntu \| bash` |
| Fedora 43 / 44 | `curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/fedora \| bash` |
| Arch Linux | `curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/arch \| bash` |
| macOS | `curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/mac \| bash` |

Each short link redirects to the matching `install-<os>.sh` in the
[zeltro-cli repository](https://github.com/CaneBayComputers/zeltro-cli).

Debian itself, RHEL, Rocky and Alma are not supported yet. The Ubuntu
installer uses Docker's Ubuntu package repository, and the Fedora installer
uses Docker's Fedora repository. Neither repository has packages for those
distros.

After the install, on Linux, log out and back in (see [All Linux](#all-linux)).
Then run this once:

```bash
zeltro configure
```

Each installer sets up Docker, Node.js (through nvm, if you don't already
have Node 16 or newer), Git, `jq`, a `trash` command, ImageMagick,
`rsvg-convert` and the GitHub CLI. It then clones Zeltro to
`/usr/local/share/zeltro-cli` and links the `zeltro` command into
`/usr/local/bin`. On macOS it also installs the Xcode Command Line Tools,
Homebrew and Docker Desktop if any of them are missing.

`zeltro configure` does the following:

- writes `/etc/zeltro-cli/.env`
- picks a private Docker subnet
- creates your projects directory (`~/zeltro-projects` by default)
- sets your Git name and email if they aren't set yet
- installs bash tab-completion
- starts the shared services

---

## Platform notes

### All Linux

The installer adds you to the `docker` group. Log out and back in (or reboot)
before you use Zeltro, or Docker calls will be denied. Over SSH, reconnecting
is enough.

### macOS

The installer puts in Docker Desktop. Open it once and accept its licence.
Docker Desktop is free for personal use, education and small businesses, and
larger companies need a paid Docker subscription
([Docker's terms](https://docs.docker.com/desktop/setup/install/mac-install/)).
Docker Desktop has to be running whenever you use Zeltro. It supports the
current macOS release and the two before it.

Docker Desktop keeps containers inside a VM, so the container IP can't be
reached from the Mac. `zeltro status` prints a `http://localhost:<port>`
address for each project instead.

### Arch

`pacman -Syu` runs a full system upgrade, which often replaces the running kernel. When that happens Docker can't start until you reboot. The installer detects this and prints a `REBOOT NOW` step. Reboot, then re-run the installer to finish.

### Fedora: SELinux

Fedora runs SELinux in enforcing mode, and Zeltro bind-mounts each project directory into its container.

Docker CE turns off SELinux confinement by default (containers run unconfined as `spc_t`), so a stock install isn't affected. Once Docker's SELinux support is turned on (`"selinux-enabled": true` in `/etc/docker/daemon.json`), an unlabeled project directory gives every container `Permission denied`.

`zeltro configure` labels your projects directory `container_file_t`, so Zeltro works either way. If you move your projects directory by hand, re-run `zeltro configure` to relabel it.

### Windows

Download the desktop app from
[zeltro.build/download/windows](https://zeltro.build/download/windows) (a beta
Setup `.exe`; see [Downloads](../downloads/)). It installs for your account with
no admin rights. Zeltro itself runs on Linux, so there are two ways to run your
projects from it:

- **Drive another machine.** The desktop app can manage Zeltro on a Linux box
  or a Mac over SSH. This works today. See [Downloads](../downloads/).
- **Zeltro in WSL2 (preview).** The desktop app's own "Zeltro on this PC" WSL2
  setup is still in testing.

There is also an older CLI script, `install-windows.ps1`. It has been lightly
tested, and it will be retired once the desktop app's WSL2 setup is verified.
It enables WSL2, installs Ubuntu 24.04, and installs and configures Zeltro
inside it. It needs a PowerShell started with **Run as administrator**:

```powershell
irm https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-windows.ps1 | iex
```

The script runs in two stages, because turning on the WSL Windows features
needs a reboot. It schedules itself to resume after you log back in. It needs
Windows 10 version 2004 (build 19041) or newer, or Windows 11, and it refuses
older builds before it changes anything. This matches the minimum that
[Microsoft gives for `wsl --install`](https://learn.microsoft.com/en-us/windows/wsl/install).

WSL2 needs hardware virtualization: VT-x/AMD-V turned on in BIOS/UEFI, plus
SLAT. If the hypervisor can't start, the Ubuntu download succeeds and then
registering it fails with `HCS_E_HYPERV_NOT_INSTALLED`. This also rules out
running it inside a VirtualBox VM, because VirtualBox doesn't pass SLAT
through to the guest.

Two things behave differently under WSL:

- **WSL shuts an idle distro down and stops its containers with it.** Keep a
  terminal open, or run `wsl -d Ubuntu-24.04 -u root -e sleep infinity`.
- **Browse projects with the LAN ACCESS address `zeltro status` prints.** It is
  the WSL VM's address, and it changes when WSL restarts, so read it from
  status each time rather than bookmarking it.

---

## Install from a local checkout

Use this if you want to work on Zeltro itself. When you run an installer from inside a checkout, it skips the `git clone` and symlinks `/usr/local/share/zeltro-cli` to your folder.

```bash
git clone https://github.com/CaneBayComputers/zeltro-cli.git
cd zeltro-cli
./install-ubuntu.sh      # or install-fedora.sh / install-arch.sh / install-mac.sh
```

---

## Configuration

It's safe to re-run `zeltro configure`. It keeps the existing values from `/etc/zeltro-cli/.env` as defaults.

| Option | Description |
|---|---|
| `--git-name <name>` | Git user name |
| `--git-email <email>` | Git user email |
| `--projects-dir <dir>` | Projects directory (default: existing, or `~/zeltro-projects`) |
| `--vpc-subnet <A.B.C>` | Docker VPC subnet (default: existing, or a random `10.x.x`) |
| `--non-interactive`, `-y` | Never prompt; accept defaults for anything not passed as a flag |

For a fully unattended setup, such as a script, CI, or provisioning a machine
for an agent:

```bash
zeltro configure --non-interactive \
  --git-name "Your Name" --git-email "you@example.com"
```

Zeltro does **not** ask for AWS credentials or GitHub authentication, and it
needs neither. Nothing in Zeltro uses AWS. You only need GitHub
authentication for the optional `--github` flags and for `clone fork` and
`clone new-repo`. If you use them without it, they tell you to run
`gh auth login` at that point.

Zeltro picks the Docker VPC subnet for you. It is a private `/24` in the
`10.x.x` range, never `10.0.x`, so it can't collide with the `10.0.0.0/24`
network that many home and office LANs use. Use `--vpc-subnet` if you need a
specific range.

Tab-completion covers commands, project names, framework names and installer names:

```
zeltro ins<TAB>            → install
zeltro install gr<TAB>     → grafana  gramps-web  graylog  grist  grocy
zeltro up <TAB>            → (your project names)
zeltro new <TAB>           → django  express  fastapi  flask  kavera  laravel  ...
```

---

## The desktop app

[Zeltro GUI](https://github.com/CaneBayComputers/zeltro-gui) is optional. On
Linux and macOS, one command installs it, and installs this CLI first if
`zeltro` is missing:

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/ubuntu | bash
```

For other platforms, replace `ubuntu` at the end of the link with `fedora`,
`arch` or `mac`. On macOS, install [Homebrew](https://brew.sh) first, because
the GUI installer stops if it is missing.

On first launch the GUI shows a short setup form and runs `zeltro configure`
for you. If you have already configured Zeltro in a terminal, it skips the
form.

Packaged builds (Windows `.exe`, `.deb`, `.rpm`, pacman, `.dmg`) are on the
[releases page](https://github.com/CaneBayComputers/zeltro-gui/releases/latest).
See [Downloads](../downloads/) for which to use.

---

## Updating

```bash
zeltro update           # git pull the CLI only — nothing else is touched
zeltro update --full    # also re-run the platform installer and re-pull Docker images
```

`--full` stops running projects.

---

## Uninstalling

```bash
zeltro uninstall                    # remove Zeltro's Docker containers, volumes and networks
zeltro uninstall --delete-images    # also remove the Docker images

sudo rm -f /usr/local/bin/zeltro
sudo rm -rf /usr/local/share/zeltro-cli
sudo rm -f /usr/share/bash-completion/completions/zeltro /etc/bash_completion.d/zeltro
sudo rm -rf /etc/zeltro-cli         # optional: also remove configuration
```

Without `--delete-images`, `zeltro uninstall` asks whether to remove the
images.

**Removed:** the shared service containers, project containers, and Zeltro's
volumes and networks. The volumes hold the shared databases, so **every
project's database is deleted**. Dump anything you want to keep first. Each
project's `docker-compose.yaml` is renamed to `docker-compose.yaml.backup`.

**Kept:** all your project source code, non-Zeltro containers and images, and Docker itself.
