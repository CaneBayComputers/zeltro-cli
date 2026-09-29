# Zeltro CLI

## DevOps in-a-box!

**Pre-plumbed PHP, Python and Node environments so your AI agent can skip the setup and get straight to building.**

| | AI without Zeltro | AI with Zeltro |
|---|---|---|
| **Standing up an OSS app** | Re-derives the image, compose and env vars | `zeltro install grafana` |
| ↳ prompts | Several rounds of fixes | One |
| ↳ tokens | ~10–15k, lands *almost* right | ~800 |
| ↳ time | An afternoon | Minutes |
| **Databases** | One bundled per project | One shared — ~700MB → ~100MB |
| **Addresses** | `localhost:3002`? `:3003`? | One per project, printed by `zeltro status` |
| **Project layout** | Reinvented every session | Fixed names, addresses, images, credentials |
| **Other machines** | "Worked on my laptop" | Identical |

📖 **[Full documentation →](https://zeltro.ai/guide/)**

---

## Why

- **It's a project manager.** Every project gets a name, its own address, and the same shared services. Ten projects, one Postgres.
- **It keeps AI in bounds.** Left alone, an agent invents its own ports, database and compose file, ignoring everything else on your machine. Zeltro hands it a fixed environment instead.
- **It saves tokens.** Networking, scaffolding, secrets and 200+ app installs are pre-baked. The agent builds your app, not the plumbing.
- **The containers are already built.** PHP 8.3 and Python 3 with their database drivers, and Node 22, each with nginx and supervisor. No image hunting, no Dockerfiles.
- **Configure once.** One `zeltro configure`, then no per-project YAML or env spelunking.

---

## Install

**Linux**

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/ubuntu | bash
```

Swap `ubuntu` for `fedora` or `arch`. Run it as your normal user, then log out
and back in so your user can use Docker.

**macOS**

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/cli/mac | bash
```

Installs the Xcode command line tools, Homebrew and Docker Desktop if they are
missing. Note that Docker Desktop keeps containers inside a VM, so on macOS you
reach a project by the port `zeltro status` prints rather than by container IP.

**Windows**

Zeltro is a Linux tool. On Windows, install the desktop app
([download](https://zeltro.ai/download/windows)) and point it at a Linux or
Mac machine over SSH, or let it set up Zeltro inside WSL2 on the same PC (in
preview). The older `install-windows.ps1` script, run from an administrator
PowerShell, also sets up WSL2 with Zeltro inside it; it is lightly tested and will
be retired once the desktop app's WSL2 setup is verified.

Then, once:

```bash
zeltro configure
```

Log out and back in so Docker group access takes effect. Details and platform notes: **[Installation](https://zeltro.ai/guide/installation/)**.

---

## Start here

```bash
zeltro create "A timeclock for employees in Django"
```

Describe what you want. **Zeltro** builds the project, database, environment and URL. The AI only customizes what sits on top — that's where the savings come from.

Name a framework if you have a preference — or don't, and let the agent choose:

```bash
zeltro create "A tool to track my guitar pedal collection"
```

Give it as much detail as you like:

```bash
zeltro create "A customer intake system for a small law firm. Clients submit a
form with their contact info, case type and a short description. Staff log in
to review submissions, assign each one to an attorney, and move it through new,
in progress and closed. Email the client whenever the status changes."
```

---

## Prefer to drive it yourself?

```bash
zeltro new flask my-api        # scaffold a project you write
zeltro install grafana         # deploy a ready-made app
zeltro clone work-directly <repo-url>
zeltro up my-api               # start it
```

Everything else — frameworks, the 200+ app library, the full command reference, architecture, and scripting — is in the **[docs](https://zeltro.ai/guide/)**.

---

## Prefer not to use a terminal?

The **Zeltro app** is an optional desktop front end: same projects, same shared
services, same addresses, just visible and clickable. On Linux it installs with
one command, which also installs this CLI if `zeltro` is missing:

```bash
curl -fsSL https://dist.canebaycomputers.com/zeltro/ubuntu | bash
```

It works on Ubuntu/Debian, Fedora/RHEL and Arch. On **Windows**,
[download the installer](https://zeltro.ai/download/windows) (beta). The app
drives Zeltro on machines you add under **Settings → Remotes → Hosts** (a Linux
box, a Mac, a Pi, an EC2 instance), or inside WSL2 on the same PC (in preview).
On a **Mac** (Apple Silicon or Intel), `curl -fsSL https://dist.canebaycomputers.com/zeltro/mac | bash`
installs it through Homebrew. Packages are on the
[releases page](https://github.com/CaneBayComputers/zeltro-releases/releases).

---

Runs on Linux and macOS, and on Windows through the desktop app. The CLI is open source (MIT); the desktop app is proprietary and free for personal use, with a [lifetime commercial license](https://zeltro.ai/commercial) for businesses.
