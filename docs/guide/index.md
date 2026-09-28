---
title: Overview
nav_order: 1
---

# Zeltro CLI

Zeltro is a Docker-based local development environment manager for PHP, Python and Node projects — and a set of guardrails for AI coding agents working on your machine.

It does three things, and they reinforce each other.

---

## Shares one set of services across every project

One `zeltro-postgres`, one `zeltro-mariadb`, one `zeltro-redis`, one `zeltro-mongo`, one `zeltro-memcached` — used by every Zeltro project on the machine. Run ten projects, you still have one of each.

- **Projects talk to each other by name.** Every project joins one Docker network and resolves by name on it, so a container can `fetch('http://my-api/')` or `psql -h zeltro-postgres` with no networking configuration.
- **No port roulette.** You never choose a port. Each project is assigned its own address when it is created, and `zeltro status` prints it — no `localhost:3001` vs `:3002` vs `:3003`, no `host.docker.internal` hacks.
- **Resource consolidation.** Seven duplicate Postgres containers eating ~700MB becomes one eating ~100MB.
- **No conflicts.** Upstream compose files binding `5432:5432` or `80:80` get rewired to the shared services automatically.

## Runtimes that are already built

Three base images cover every supported stack — PHP 8.3, Python 3, Node 22 — each with nginx, supervisor, and every database driver already compiled in.

You never hunt down an image, compare tags, or write a Dockerfile. `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `redis`, `mongodb`, `gunicorn`, `uvicorn` — all present, on every project, from the first command.

See [Architecture](architecture/) for what each image ships.

## Built for AI agents to work inside

Left alone, an AI agent will scaffold a project however it likes — its own ports, its own bundled database, its own compose file — with no regard for the other twelve projects on your machine. Zeltro gives the agent a fixed environment to work in:

- **A stable platform.** Shared services, one network, assigned addresses, and known runtime images mean the agent builds your app instead of reinventing infrastructure.
- **Fewer tokens.** Framework scaffolding, networking, secret generation and 200+ app installs are pre-baked. The agent doesn't rediscover how to wire nginx + php-fpm every session.
- **Context that survives.** Every project gets an `AGENTS.md` describing its URL, database and commands, so a new agent session picks the project up cold.

---

## Where to go next

| | |
|---|---|
| [Installation](installation/) | Install Zeltro on Linux or macOS |
| [Quick start](quick-start/) | Your first project in one command |
| [Frameworks](frameworks/) | `zeltro new` — scaffold a project you write |
| [App library](app-library/) | `zeltro install` — 200+ ready-to-run apps |
| [AI workflow](ai-workflow/) | `zeltro create`, `ai`, `resume` |
| [Command reference](commands/) | Every command and flag |
| [Architecture](architecture/) | Services, networking, base images |
| [Automation & JSON](automation/) | Scripting, JSON output, debugging |

## Where Zeltro doesn't add much

If you run exactly one project and never touch another, plain `docker compose up` works fine. Zeltro earns its keep once you have several projects, or an AI agent, sharing one machine.
