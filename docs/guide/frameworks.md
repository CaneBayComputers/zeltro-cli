---
title: Frameworks
nav_order: 5
---

# Frameworks — `zeltro new`

`zeltro new <framework> <name>` scaffolds a greenfield project **you write**. Both arguments are required positionals.

```bash
zeltro new laravel my-shop
zeltro new flask my-api --database sqlite
zeltro new express my-service --database postgres --version latest
```

For ready-made third-party apps you *run* rather than write, see [App library](../app-library/) instead.

---

## Supported frameworks

| Framework | Runtime image | Default database |
|---|---|---|
| `laravel` | PHP 8.3 | MySQL |
| `kavera` | PHP 8.3 | MySQL |
| `octobercms` | PHP 8.3 | MySQL |
| `drupal` | PHP 8.3 | MySQL |
| `wordpress` | PHP 8.3 | MySQL |
| `php` | PHP 8.3 | MySQL |
| `fastapi` | Python 3.12 | PostgreSQL |
| `flask` | Python 3.12 | PostgreSQL |
| `django` | Python 3.12 | PostgreSQL |
| `python` | Python 3.12 | PostgreSQL |
| `express` | Node 22 | MySQL |
| `nestjs` | Node 22 | MySQL |
| `fastify` | Node 22 | MySQL |
| `node` | Node 22 | MySQL |
| `nextjs` | Node 22 | SQLite |
| `nuxt` | Node 22 | SQLite |
| `sveltekit` | Node 22 | SQLite |
| `astro` | Node 22 | SQLite |
| `hono` | Node 22 | SQLite |
| `react` | Node 22 | SQLite |
| `vue` | Node 22 | SQLite |

Each runtime is one of Zeltro's base images: `canebaycomputers/cbc:nginx-php8` (PHP 8.3 behind nginx and php-fpm), `canebaycomputers/cbc:nginx-python3` (Python 3.12; your app listens on port 8000 and nginx proxies it) or `canebaycomputers/cbc:nginx-node` (Node 22; your app listens on port 3000 and nginx proxies it). Every project answers on port 80.

If you ask for a database the framework can't use, Zeltro warns and switches to one it can. WordPress is MySQL only, and Laravel, Kavera, October CMS, Drupal and Django don't get MongoDB.

---

### Front-end frameworks

`nextjs`, `nuxt`, `sveltekit`, `astro`, `react` and `vue` are scaffolded as
running dev servers with hot reload, proxied through nginx on port 80. Edit a
file and the page updates — no build step, no port to remember.

They default to **SQLite**, unlike every other framework here, because a
front-end project should not start a database server it never queries. Ask for
one explicitly when you need it:

```bash
zeltro new nextjs my-app --database postgres
```

`react` and `vue` are plain single-page apps on Vite with no server rendering.
`hono` is an API framework rather than a UI one, and is grouped with them only
because it shares the same Node base image.

{: .note }
> Hot reload is wired for you. The dev server's own port is never published.
> The browser reaches the app on port 80 through nginx, so the Vite-based
> projects (`nuxt`, `sveltekit`, `astro`, `react`, `vue`) pin the HMR socket to
> port 80 in their config (`server.ws.clientPort`, which Vite 8.1 renamed from
> `server.hmr.clientPort`). Change that and hot reload stops connecting while
> the page still loads, which is a confusing failure. `nextjs` needs no port
> setting, because its dev server connects back through the same address as
> the page. Next.js 16 does refuse hot-reload connections from hosts it doesn't
> know, so the scaffold's `next.config.mjs` lists the private IPv4 ranges in
> `allowedDevOrigins`. Add any other hostname you browse the project by.

### Kavera

[Kavera](https://github.com/CaneBayComputers/kavera) is a Laravel-native **website** framework: flat-file Blade pages plus service-driven dynamic content (Blogger posts, Eventbrite events, Flickr galleries, form webhooks) cached through Redis. Forms ship with email, webhooks, spam controls and reCAPTCHA; pages carry SEO titles and optional JSON-LD.

It exists because an agent editing page *files* beats an agent driving a CMS admin UI. Reach for it over plain Laravel for marketing sites, brochure sites, portfolios and galleries — and for plain Laravel when you need a real application with custom models and business logic.

```bash
zeltro new kavera my-site
```

Pages live in `resources/views/content`. After adding or removing one, refresh the registry so routes resolve:

```bash
zeltro art app:update-content-list
```

### October CMS and Drupal

Both are CMSs with an admin UI, installed from source so they use Zeltro's shared databases.

- **October CMS** (`zeltro new octobercms my-site`) is Laravel-based. Themes and plugins live in the project, so an agent can edit them. The admin is at `/backend`; create the admin user with `zeltro art october:passwd <email> <password>`. It is free for local development, but production use needs a licence from [octobercms.com](https://octobercms.com/pricing).
- **Drupal** (`zeltro new drupal my-site`) installs Drupal 11 with Composer, then runs `drush site:install`. The docroot is `public/` instead of Drupal's usual `web/`. It is the slowest framework to create, so expect several minutes. Run Drush with `zeltro drush <args>`.

## Options

| Option | Description | Values |
|---|---|---|
| `--database <type>` | Database engine | `auto` (default: see the table above), `mysql`, `postgres`, `mongodb`, `sqlite` |
| `--db-name <name>` | Database name | Default: project name, dashes → underscores |
| `--version <ver>` | Framework version | Laravel and WordPress only: `latest` (default) or a version number. Other frameworks ignore it |
| `--image <ref>` | Override the Docker image | Default: the framework's base image |
| `--no-migration` | Skip migrations | Migrations run by default |
| `--one-off` | Skip the AI hand-off after creation | |
| `--github` | Create a GitHub repo in your account | Requires `gh` auth |
| `--github-org <org>` | Create the repo in an organization | |
| `--public` / `--private` | Repo visibility | Default private |
| `--no-storage-symlink` | Skip `public/storage` symlink | Laravel only |

---

## Databases

### SQLite

```bash
zeltro new flask notes --database sqlite
zeltro new django blog --database sqlite
zeltro new laravel shop --database sqlite
```

SQLite needs no shared service — it's a single file. Zeltro creates it, points the project's `.env` at it, and runs migrations normally.

The file always lives **inside the project directory**:

| Framework | Path |
|---|---|
| Django | `db.sqlite3` |
| Laravel, Kavera, October CMS | `database/database.sqlite` |
| Drupal | `public/sites/default/files/.ht.sqlite` |
| Everything else | `database.sqlite` |

That location is deliberate. The project directory is the only path bind-mounted into the container, so a database anywhere else would be destroyed every time the container is recreated on `zeltro up`. It is also gitignored by default.

Good for prototypes, single-user tools, and test fixtures. For anything concurrent, use Postgres or MySQL.

### Shared server databases

`mysql`, `postgres` and `mongodb` connect to the shared service containers. Zeltro creates the database and writes the connection settings into the project's `.env` — you never configure credentials by hand. See [Architecture → Shared services](../architecture/#shared-services) for hostnames and credentials.

---

## Working inside a project

Run these **from the project directory**. They execute inside the container, with the correct runtime.

### PHP

```bash
zeltro composer install
zeltro art migrate
zeltro wp plugin list --status=active
zeltro drush status
zeltro php script.php
zeltro tinker
```

### Python

```bash
zeltro python -c "import sys; print(sys.version)"
zeltro pip install httpx
zeltro django manage migrate
zeltro django manage createsuperuser
zeltro shell
```

Python containers provide `python3`, not `python`.

### Node

```bash
zeltro npm install
zeltro npx tsc --init
zeltro node script.js
zeltro shell
```

### Any framework

```bash
zeltro exec <cmd>              # run a command, no TTY — good for scripts and CI
zeltro exec-root <cmd>         # as root
zeltro bash                    # interactive shell
zeltro shell                   # framework-aware REPL (tinker / django shell / node / python3; bash otherwise)
zeltro supervisor restart all  # restart in-container processes
zeltro supervisor-status
```

Use `zeltro supervisor`, never `zeltro exec supervisorctl` — the latter runs as the developer user and is denied on the supervisor socket.

### Laravel extras

```bash
zeltro db-refresh      # fresh migration + seed
zeltro cache-refresh   # clear all caches
zeltro phpcs app/      # static analysis
zeltro phpcbf app/     # auto-fix
zeltro phpmd app/File.php
zeltro php -l app/File.php
```

---

## Adopting an existing project

```bash
zeltro setup my-project                          # a folder already in ~/zeltro-projects/
zeltro setup my-project --framework django       # force detection
zeltro setup my-project --overwrite-env          # repoint an existing .env at shared services
zeltro setup my-project --no-startup             # register without starting, to review the compose
```

Framework detection reads the project's files: `artisan`, `manage.py`, `main.py`, `app.py`, `package.json`, `wp-config.php`, and a `composer.json` that requires `drupal/core`. A `main.py` or `app.py` that imports Flask is Flask; any other `main.py` is treated as FastAPI. For Node projects, the dependencies in `package.json` decide between Next.js, Nuxt, SvelteKit, Astro, Hono, Fastify, Express, NestJS, React, Vue and plain Node.
