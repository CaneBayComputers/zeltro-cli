---
title: Downloads
nav_order: 3
---

# Downloads

Zeltro comes in two pieces. The **CLI** does the work, and the **GUI** is an
optional desktop app that runs on top of it. On Linux and macOS, both install
from source with one command. The checkout you install from is the one that
runs, and updating is a `git pull`.

There is no packaged download yet: no `.exe`, `.deb`, `.rpm`, pacman package
or `.dmg`.

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

An installer is coming. A Windows Setup `.exe` has been built and tested but
isn't released yet. When it is, it will be at
[zeltro.build/download/windows](https://zeltro.build/download/windows). See
[Windows](#windows) below for what works today.

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

## Why no packages?

On Linux and macOS, installing from source gives you one path to maintain
instead of one build per distro. It also means there's no version skew
between what you downloaded and what's in the repository. The GUI repository
can still build `.deb`, `.rpm`, pacman and `.dmg` packages, but none are
published.

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

## Source

- [CaneBayComputers/zeltro-cli](https://github.com/CaneBayComputers/zeltro-cli) (MIT)
- [CaneBayComputers/zeltro-gui](https://github.com/CaneBayComputers/zeltro-gui) (MIT)

## Support

Zeltro is open source under the MIT licence, with no paid tier and no account
to create. You bring your own AI agent and pay for it yourself. If Zeltro saves you time and you want to chip in:

- [GitHub Sponsors](https://github.com/sponsors/shrimpwagon): GitHub covers the fees
- [Ko-fi](https://ko-fi.com/canebaycomputers): quickest, no account needed
- [Patreon](https://patreon.com/canebaycomputers): monthly
- [Credit card](https://donate.zeltro.build): direct, via Cane Bay Computers' processor
