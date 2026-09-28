---
title: Quick start
nav_order: 4
---

# Quick start

---

## Let an AI build it

```bash
zeltro create "A timeclock for employees in Django"
```

Describe what you want in plain English. Zeltro wraps your idea in platform instructions and hands it to your configured AI CLI.

From there the work is split, and the split is the point:

- **Zeltro** creates the project, creates and wires the database, installs the framework or app, generates the `.env`, assigns the hostname, starts the container, and hands back a working URL.
- **The AI** only customizes what's on top — models, routes, templates, business logic — then updates the project README with the URL and any credentials.

The agent never has to work out how to wire nginx, pick a port, or provision a database. It calls one Zeltro command and gets a running project back, which is where the prompt and token savings come from.

```bash
zeltro create "A customer check-in system in Laravel"
zeltro create "An inventory tracker in Express"
zeltro create "New Grafana"
zeltro create "https://github.com/monicahq/monica"
```

Run it bare and it asks what you want to build:

```bash
zeltro create
```

Long prompts can come from a file or stdin:

```bash
zeltro create -f spec.md
zeltro create < spec.md
cat spec.md | zeltro create
```

Set your agent first with [`zeltro ai-set`](../ai-workflow/#choosing-an-agent). See [AI workflow](../ai-workflow/) for the full picture.

---

## Or scaffold it yourself

Framework first, then name:

```bash
zeltro new laravel my-shop
zeltro new django survey-app
zeltro new flask my-api
zeltro new express my-service
```

The database is auto-selected per framework (PHP/Node → MySQL, Python → PostgreSQL). Override it:

```bash
zeltro new flask notes --database sqlite
zeltro new express api --database postgres
```

Full list of frameworks and options: [Frameworks](../frameworks/).

---

## Or install something ready-made

```bash
zeltro install grafana
zeltro install gitea
zeltro install n8n
```

Fully configured and reachable at the address `zeltro status` prints, in under two minutes. Browse all 200+: [App library](../app-library/).

**`new` vs `install`:** `new` scaffolds an empty project *you write*. `install` deploys a finished app *someone else wrote*. If you guess wrong, Zeltro tells you the right command.

---

## Or bring an existing project

```bash
# clone a repo and adapt it
zeltro clone work-directly https://github.com/user/my-app
zeltro clone fork https://github.com/user/my-app
zeltro clone new-repo https://github.com/user/my-app my-app

# already have the folder in ~/zeltro-projects/
zeltro setup my-project
zeltro up my-project
```

Zeltro adapts a project's existing `docker-compose.yaml` automatically — bundled databases are removed and repointed at the shared services, and the original is preserved as `docker-compose.upstream.yaml`. See [Architecture → Compose adaptation](../architecture/#compose-adaptation).

---

## Daily driving

```bash
zeltro up my-project      # start one project (shared services start too)
zeltro up-all             # start everything
zeltro down my-project    # stop one project
zeltro down-all           # stop everything (shared services keep running)
zeltro status             # what's running
zeltro stop-services      # stop the shared services too
```

Your project is at `http://my-project/` in any browser on the machine.
