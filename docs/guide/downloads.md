---
title: Downloads
nav_order: 3
---

# Downloads

Zeltro comes in two pieces. The **CLI** does the work, and the **app** is a
desktop front end that runs on top of it. The app is released as packages on
the [releases page](https://github.com/CaneBayComputers/zeltro-releases/releases):
a Windows Setup `.exe`, and `.deb`, `.rpm` and pacman packages for Linux
(x86_64). **A Mac app is coming soon**; until then a Mac can run your projects
through the CLI (below).

Run the commands below as your normal user, not as root.

---

## The Zeltro app (and the CLI with it)

**Linux**

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/ubuntu | bash
```

The same command works on Ubuntu/Debian, Fedora/RHEL and Arch (the `fedora` and
`arch` links go to the same installer). It installs the CLI first if `zeltro` is
missing, then adds Zeltro's signed package repository
([packages.zeltro.build](https://packages.zeltro.build)) and installs the app
from it with apt, dnf or pacman. The app then appears in your applications menu.
Afterwards, log out and back in once so your user can use Docker.

**Updates arrive with your system's own updates** (`apt upgrade`, `dnf upgrade`,
`pacman -Syu`), like any other package. To add the repository by hand instead,
see the [zeltro-releases README](https://github.com/CaneBayComputers/zeltro-releases#readme).
On Arch the installer runs `pacman -Syu`, which also upgrades the rest of the
system, because Arch doesn't support partial upgrades.

**Windows**

Download the installer from
[zeltro.build/download/windows](https://zeltro.build/download/windows). It is a
normal Setup `.exe` (beta) that installs for your account only, so it needs no
admin rights. It is not code-signed yet, so Windows may say it "protected your
PC": choose **More info → Run anyway**. See [Windows](#windows) below for how to
run your projects once it is installed.

**macOS**

The Mac app is coming soon: it needs Apple's code signing first. Meanwhile,
install the [CLI on the Mac](#zeltro-cli-only) and add the Mac under
**Settings → Remotes** in the app on a Linux or Windows computer.

### After installing

On first launch the app asks you to accept its [license
terms](https://zeltro.build/terms), shows a short setup form and runs
`zeltro configure` for you. Running `zeltro configure` in a terminal works too.

**Upgrading from 1.0.0-beta.4 or earlier:** those builds can't update
themselves to beta.5. Install beta.5 over the old one the same way; your
settings are kept.

### What's in it

Create with AI, the full app library, new project and clone, start/stop of the
shared services, embedded tabbed terminals for AI sessions, and a Settings panel
with AI agent configuration and a theme picker. Five themes ship: Retro (the
default), Dark, Light, Matrix and Zeltro. Each has its own 16-colour terminal
palette, so output stays readable, including on Light.

### Windows

On Linux the app drives a Zeltro on the same machine. On Windows, Zeltro itself
has to run in Linux, and there are two ways to do that:

- **Another machine over SSH. This works today.** The app drives Zeltro on a
  Linux box, a Mac, a Raspberry Pi or an EC2 instance. Add them under
  **Settings → Remotes → Hosts**. Each host needs Zeltro already installed
  and configured. Projects, containers and files live on the host that runs
  them.
- **This PC, through WSL2. In preview.** The app's own setup for running
  Zeltro in WSL2 on the same PC is still in testing.

Remote hosts work from Linux too.

---

## Zeltro CLI only

If you don't want the app, or for a Mac:

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

The CLI short links redirect to the `install-<os>.sh` scripts in the
[zeltro-cli](https://github.com/CaneBayComputers/zeltro-cli) repository; the app
links go to the installer in
[zeltro-releases](https://github.com/CaneBayComputers/zeltro-releases).

---

## Versions

`zeltro --version` reports the CLI version. The app's About panel shows both.

**The CLI and the app have separate version numbers, and they aren't expected to
match.** The app checks what the installed CLI can do instead of comparing
versions, and it hides any feature the CLI can't support. An older CLI loses
individual features rather than failing outright. You can upgrade either one
on its own.

---

## Source and licensing

The command line tool is open source under the MIT licence:
[CaneBayComputers/zeltro-cli](https://github.com/CaneBayComputers/zeltro-cli).

The desktop app is proprietary. It's free for personal use. A business using it,
including for paid client work, needs a
[lifetime commercial license](https://zeltro.build/commercial), paid once,
covering everyone in the business and every future version. There's no account to
create either way, and you bring and pay for your own AI agent. The app sends
anonymous usage counts and scrubbed error reports; see
[what it collects](https://zeltro.build/privacy).
