---
title: Overview
nav_order: 1
---

# Zeltro CLI

Zeltro is a Docker-based local development environment manager for PHP, Python and Node projects — and a set of guardrails for AI coding agents working on your machine.

It does three things, and they reinforce each other.

---

## Shares one set of services across every project

One `zeltro-postgres`, one `zeltro-mariadb`, one `zeltro-redis`, one `zeltro-mongo` and one `zeltro-memcached`, shared by every Zeltro project on the machine. Run ten projects and you still have at most one of each.

- **Projects talk to each other by name.** Every project joins one Docker network and resolves by name on it, so a container can `fetch('http://my-api/')` or `psql -h zeltro-postgres` with no networking configuration.
- **No port roulette.** You never choose a port. Each project is assigned its own address when it is created, and `zeltro status` prints it — no `localhost:3001` vs `:3002` vs `:3003`, no `host.docker.internal` hacks.
- **Resource consolidation.** Seven duplicate Postgres containers eating ~700MB becomes one eating ~100MB.
- **No conflicts.** When a project's own compose file bundles a database or cache (Postgres on `5432`, MySQL on `3306`, Redis and so on), Zeltro removes that service and points the app at the shared one.

## Runtimes that are already built

Three base images cover every supported stack: PHP 8.3, Python 3 and Node 22. Each runs nginx under supervisor.

You never hunt down an image, compare tags, or write a Dockerfile. The PHP image has the MySQL, PostgreSQL, SQLite, Redis and MongoDB extensions compiled in. The Python image has the drivers for all five, plus Django, Flask, FastAPI, gunicorn and uvicorn. The Node image carries the build tools npm needs for native drivers.

See [Architecture](architecture/) for what each image ships.

## Built for AI agents to work inside

Left alone, an AI agent will scaffold a project however it likes — its own ports, its own bundled database, its own compose file — with no regard for the other twelve projects on your machine. Zeltro gives the agent a fixed environment to work in:

- **A stable platform.** Shared services, one network, assigned addresses, and known runtime images mean the agent builds your app instead of reinventing infrastructure.
- **Fewer tokens.** Framework scaffolding, networking, secret generation and 200+ app installs are pre-baked. The agent doesn't rediscover how to wire nginx + php-fpm every session.
- **Context that survives.** When Zeltro hands a project to your AI agent, it writes an `AGENTS.md` that describes the project's address, database and commands, so a new agent session can pick the project up cold.

---

## Where to go next

| | |
|---|---|
| [Installation](installation/) | Install Zeltro on Linux or macOS (Windows: installer coming, WSL2 route in preview) |
| [Downloads](downloads/) | The desktop app, and the CLI on its own |
| [Quick start](quick-start/) | Your first project in one command |
| [Frameworks](frameworks/) | `zeltro new` — scaffold a project you write |
| [App library](app-library/) | `zeltro install` — 200+ ready-to-run apps |
| [AI workflow](ai-workflow/) | `zeltro create`, `ai`, `resume` |
| [Command reference](commands/) | Every command and flag |
| [Architecture](architecture/) | Services, networking, base images |
| [Automation & JSON](automation/) | Scripting, JSON output, debugging |

## Where Zeltro doesn't add much

If you run exactly one project and never touch another, plain `docker compose up` works fine. Zeltro earns its keep once you have several projects, or an AI agent, sharing one machine.
