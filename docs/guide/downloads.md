---
title: Downloads
nav_order: 3
---

# Downloads

Zeltro is two pieces. The **CLI** does the work; the **GUI** is an optional
desktop front end for it. Neither ships as a package — both install from source
with one command, so the checkout you install from is the one that runs, and
updating is a `git pull`.

---

## Zeltro CLI

**Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-ubuntu.sh | bash
```

Swap the script for your distro: `install-fedora.sh` or `install-arch.sh`.

**macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-mac.sh | bash
```

Installs the Xcode command line tools, Homebrew and Docker Desktop if any are
missing.

**Windows**

Zeltro is a Linux tool; on Windows it runs inside WSL2. Right-click PowerShell
and choose **Run as administrator**, then:

```powershell
irm https://raw.githubusercontent.com/CaneBayComputers/zeltro-cli/master/install-windows.ps1 | iex
```

Requires Windows 10 version 2004 (build 19041) or newer — the installer checks
the build before it changes anything, rather than failing after the reboot.

Then run `zeltro configure` once. Full details in **[Installation](../installation/)**.

---

## Zeltro GUI

Installed the same way as the CLI — one command, which clones the repo for you.
On Linux and macOS it installs the CLI first if `zeltro` is missing, so this is
the only thing you need to run:

**Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/CaneBayComputers/zeltro-gui/master/install-ubuntu.sh | bash
```

Swap the script for your distro: `install-fedora.sh` or `install-arch.sh`.

**macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/CaneBayComputers/zeltro-gui/master/install-mac.sh | bash
```

To install a checkout you already have rather than a fresh clone, run the script
from inside it — it detects the local repository and builds that instead:

```bash
git clone https://github.com/CaneBayComputers/zeltro-gui.git
cd zeltro-gui && ./install-ubuntu.sh
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/CaneBayComputers/zeltro-gui/master/scripts/install-windows.ps1 | iex
```

The installer pulls the npm dependencies, compiles the TypeScript, rebuilds the
native terminal module against Electron, and drops a launcher and a desktop
entry. It takes a few minutes, mostly `npm install`. Re-running it is safe.

### What's in it

Create with AI, the full app library, new project and clone, start/stop of the
shared services, embedded tabbed terminals for AI sessions, and a Settings panel
with AI agent configuration and a theme picker. Five themes ship — Retro (the
default), Dark, Light, Matrix and Zeltro — each with its own 16-colour terminal
palette so output stays readable, including on Light.

### Windows works differently

On Linux and macOS the GUI drives a Zeltro on the same machine. On Windows there
is no local Zeltro and the installer does not try to add one — the GUI drives
Zeltro on *other* machines over SSH: a Linux box, a Mac, a Raspberry Pi, an EC2
instance. Add them under **Settings → SSH Hosts**; each needs Zeltro already
installed and configured. Projects, containers and files live on the host that
runs them.

Remote hosts work from Linux and macOS too. Windows simply has no local option
to fall back on.

---

## Why no packages?

There used to be `.deb`, `.rpm`, `.pkg.tar.zst` and `.dmg` builds of the GUI.
They are gone, and the download links that pointed at them are gone with them.

Packaging an Electron app per distro meant maintaining five build paths and a
release cycle for a project whose install is otherwise a `git pull`, and it made
the CLI and GUI behave differently for no benefit to anyone using them. Building
from source removes the whole category — no signing, no per-distro dependency
declarations, no stale release assets, and no version skew between what you
downloaded and what is in the repository.

It also removes the macOS Gatekeeper problem. The `.dmg` builds were unsigned,
so first launch was blocked with an "unidentified developer" warning that took a
`xattr -dr com.apple.quarantine` to clear. A source build does not carry the
quarantine attribute, so there is nothing to work around.

---

## Versions

`zeltro --version` reports the CLI version. The GUI's About panel shows both.

**The two version independently and are not expected to match.** Compatibility is
handled by feature detection, not by comparing version numbers — the GUI asks the
installed CLI what it can do and hides anything it cannot, so an older CLI loses
individual features rather than failing outright. Upgrade either one on its own
whenever you like.

---

## Source

- [CaneBayComputers/zeltro-cli](https://github.com/CaneBayComputers/zeltro-cli) — MIT
- [CaneBayComputers/zeltro-gui](https://github.com/CaneBayComputers/zeltro-gui) — MIT

## Support

Zeltro is open source with no paid tier — both parts are MIT. If it saves you time and
you want to chip in:

- [GitHub Sponsors](https://github.com/sponsors/shrimpwagon) — GitHub covers the fees
- [Ko-fi](https://ko-fi.com/canebaycomputers) — quickest, no account needed
- [Patreon](https://patreon.com/canebaycomputers) — monthly
- [Credit card](https://donate.zeltro.build) — direct, via Cane Bay Computers' processor
