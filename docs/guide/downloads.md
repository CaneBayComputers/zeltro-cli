---
title: Downloads
nav_order: 3
---

# Downloads

Zeltro comes in two pieces. The **CLI** does the work, and the **GUI** is an
optional desktop app that runs on top of it. On Linux and macOS, both install
from source with one command. The checkout you install from is the one that
runs, and updating is a `git pull`.

Packaged builds of the desktop app are on the [releases page](https://github.com/CaneBayComputers/zeltro-gui/releases/latest) since
v1.0.0-beta.2 (September 2026): a Windows Setup `.exe`, `.deb`, `.rpm`, a pacman
package, and `.dmg` for Intel and Apple silicon. On Linux and macOS the one-line
installers below are still the recommended route, because they also install the
CLI and Docker.

Run the commands below as your normal user, not as root.

---

## Zeltro GUI (and the CLI with it)

This is the only command you need. It installs the CLI first if `zeltro` is
missing, then the GUI.

**Linux**

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/ubuntu | bash
```

For Fedora or Arch, replace `ubuntu` at the end of the link with `fedora` or
`arch`.

**macOS**

Install [Homebrew](https://brew.sh) first, because the GUI installer stops if
it is missing. Then run:

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/mac | bash
```

The installer pulls the npm dependencies, compiles the TypeScript, rebuilds the
native terminal module against Electron, and adds a `zeltro-gui` launcher. On
Linux it also adds a **Zeltro** entry to your applications menu. On macOS you
start it with `zeltro-gui` from a terminal, because there is no `.app` bundle.
The install takes a few minutes, mostly `npm install`, and you can safely run
it again.

To install a checkout you already have instead of a fresh clone, run the script
from inside it. It detects the local repository and builds that:

```bash
git clone https://github.com/CaneBayComputers/zeltro-gui.git
cd zeltro-gui && ./install-ubuntu.sh
```

**Windows**

Download the installer from
[zeltro.build/download/windows](https://zeltro.build/download/windows). It is a
normal Setup `.exe` (about 128 MB, beta) that installs for your account only, so
it needs no admin rights, and it updates itself from new releases. It is not
code-signed yet, so Windows may say it "protected your PC": choose
**More info → Run anyway**. See [Windows](#windows) below for how to run your
projects once it is installed.

### After installing

- **Linux:** log out and back in (or reboot) so your user can use Docker.
- **macOS:** the CLI installer puts in Docker Desktop. Open it once and accept
  its licence. It has to be running whenever you use Zeltro.
- **Everywhere:** on first launch the GUI shows a short setup form and runs
  `zeltro configure` for you. Running `zeltro configure` in a terminal works
  too.

### What's in it

Create with AI, the full app library, new project and clone, start/stop of the
shared services, embedded tabbed terminals for AI sessions, and a Settings panel
with AI agent configuration and a theme picker. Five themes ship: Retro (the
default), Dark, Light, Matrix and Zeltro. Each has its own 16-colour terminal
palette, so output stays readable, including on Light.

### Windows

On Linux and macOS the GUI drives a Zeltro on the same machine. On Windows,
Zeltro itself has to run in Linux, and there are two ways to do that:

- **Another machine over SSH. This works today.** The GUI drives Zeltro on a
  Linux box, a Mac, a Raspberry Pi or an EC2 instance. Add them under
  **Settings → Remotes → Hosts**. Each host needs Zeltro already installed
  and configured. Projects, containers and files live on the host that runs
  them.
- **This PC, through WSL2. In preview.** The GUI's own setup for running
  Zeltro in WSL2 on the same PC is still in testing.

Developers can set the GUI up on Windows from source today. The script checks
out the development branch into `C:\zeltro-gui` (the WSL2 setup is part of
that branch), builds it, and adds a desktop shortcut:

```powershell
irm https://raw.githubusercontent.com/CaneBayComputers/zeltro-gui/master/scripts/install-windows.ps1 | iex
```

Remote hosts work from Linux and macOS too.

---

## Zeltro CLI only

If you don't want the GUI:

**Linux**

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/ubuntu | bash
```

For Fedora or Arch, replace `ubuntu` at the end of the link with `fedora` or
`arch`.

**macOS**

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/mac | bash
```

This installs the Xcode Command Line Tools, Homebrew and Docker Desktop if any
of them are missing.

**Windows**

See [Installation → Windows](../installation/#windows).

Then run `zeltro configure` once. For supported distro versions and the other
details, see **[Installation](../installation/)**.

The short links redirect to the `install-<os>.sh` scripts in each repository
on GitHub.

---

## Packages or the install script?

On Linux and macOS, the install script is still the recommended route: it
installs the CLI and Docker along with the app, and updating is a `git pull`.
The `.deb`, `.rpm`, pacman and `.dmg` packages on the
[releases page](https://github.com/CaneBayComputers/zeltro-gui/releases/latest) install the desktop app only.

A source install also avoids the macOS Gatekeeper problem. Unsigned `.dmg`
builds get blocked on first launch with an "unidentified developer" warning,
and clearing it takes `xattr -dr com.apple.quarantine`. A source build doesn't
carry the quarantine attribute, so there is nothing to work around.

Windows is the exception. It will get a Setup `.exe`.

---

## Versions

`zeltro --version` reports the CLI version. The GUI's About panel shows both.

**The CLI and GUI have separate version numbers, and they aren't expected to
match.** The GUI checks what the installed CLI can do instead of comparing
versions, and it hides any feature the CLI can't support. An older CLI loses
individual features rather than failing outright. You can upgrade either one
on its own.

---

## Source and licensing

The command line tool is open source under the MIT licence:
[CaneBayComputers/zeltro-cli](https://github.com/CaneBayComputers/zeltro-cli).

The desktop app is proprietary. It's free for personal use. A business using it,
including for paid client work, needs a
[lifetime commercial license](https://zeltro.build/commercial): US$99.99, paid once,
covering everyone in the business and every future version. There's no account to
create either way, and you bring and pay for your own AI agent. The app sends
anonymous usage counts and scrubbed error reports; see
[what it collects](https://zeltro.build/privacy).
