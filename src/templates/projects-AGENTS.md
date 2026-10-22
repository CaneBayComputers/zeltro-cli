# AGENTS.md — `@@PROJECTS_DIR@@` (the Zeltro projects directory)

**Every subdirectory here is a Zeltro-managed project.** Zeltro is a Docker-based local
development platform: each project runs in its own container, and every project on the machine
shares one set of database, cache and mail services.

**Use `zeltro` commands whenever possible.** Do not run `php`, `composer`, `artisan`, `npm`,
`node`, `python`, `pip`, `wp`, or `drush` on the host for a project here. Run the Zeltro
equivalent from inside the project directory so it executes in the project's container with the
right runtime versions. Host-side tools are fine for things that are not the project's runtime
(git, gh, ImageMagick, `rsvg-convert`, editors).

## Reaching a project

- **From another container, by name.** Projects and shared services resolve by container name
  on the `@@NETWORK@@` Docker network, e.g. `http://other-project/` or `@@MARIADB@@`.
- **From the host or a browser, by address.** The host is not on that network, so
  `http://<project>/` does **not** work there. `zeltro status <project>` prints the local
  address (a container IP, or `http://localhost:<port>` on macOS/Windows) and a LAN address.

## Shared services

| Service | Host (inside containers) | Port | User | Password |
|---|---|---|---|---|
| MariaDB / MySQL | `@@MARIADB@@` | 3306 | `root` | *(empty)* |
| PostgreSQL | `@@POSTGRES@@` | 5432 | `root` | `password` |
| MongoDB | `@@MONGO@@` | 27017 | `root` | `password` |
| Redis | `@@REDIS@@` | 6379 | — | *(none)* |
| Memcached | `@@MEMCACHED@@` | 11211 | — | *(none)* |
| MailHog | `@@MAILHOG@@` | SMTP 1025 / UI 8025 | — | *(none)* |

MariaDB, PostgreSQL and MongoDB start when a project needs them; `zeltro enable-service` lists
the optional extras (MinIO, Meilisearch, admin UIs).

## Commands (run from the project directory)

```bash
# Runtimes and package managers, inside the container
zeltro art <args>        # Laravel artisan          zeltro art migrate
zeltro composer <args>   # Composer                 zeltro composer install
zeltro php <args>        # PHP CLI                  zeltro php -l app/Models/User.php
zeltro npm | npx | node  # Node toolchain           zeltro npm run build
zeltro python | pip      # Python (python3 only)    zeltro python -m pytest
zeltro django manage <args>                         # Django: prefer this over exec python3 manage.py
zeltro wp <args> / zeltro drush <args>              # WordPress / Drupal CLIs

# Static analysis (PHP). Uses Zeltro's ruleset unless you pass --standard.
zeltro phpcs <path>      zeltro phpcbf <path>     zeltro phpmd <path>

# Anything else inside the container
zeltro exec <cmd>        # as you (your uid), no TTY: the automation default
zeltro exec-root <cmd>   # root, no TTY
zeltro supervisor restart all   # restart in-container processes (never `exec supervisorctl`)

# Laravel shortcuts
zeltro db-refresh        # migrate:fresh + seed. DROPS EVERY TABLE in the project's database
zeltro cache-refresh     # clear Laravel caches + composer dump-autoload

# Shared services
zeltro mysql <args>      zeltro redis <cmd>      zeltro redis-flush      zeltro memcache-flush

# Project lifecycle (run from anywhere)
zeltro status [<name>] [--all]   # running projects and their addresses; --all includes stopped
zeltro up <name> / zeltro down <name> / zeltro up-all / zeltro down-all
zeltro new <framework> <name>    # laravel kavera octobercms drupal wordpress php fastapi flask
                                 # django python express nestjs fastify node nextjs nuxt
                                 # sveltekit astro hono react vue
zeltro setup <name> [mysql|postgres|mongo|sqlite]
                                 # adopt an existing directory here: writes or adapts its
                                 # docker-compose.yaml, wires .env, runs migrations
zeltro clone <work-directly|fork|new-repo> <repo> [name]
zeltro install <app> [name]      # 200+ curated OSS apps (`zeltro install --list`)
zeltro remove <name>             # DB preserved unless --force-db-delete

# Other agent sessions in the Zeltro app
zeltro peers                     # who is running, and which one is you
zeltro send <project>[@host] ... -- "message"   # --all for everyone else

# The user, through the Zeltro app's window (only in a session the app started)
zeltro gui ask "<question>" --option A --option B --allow-text   # prints their answer
zeltro gui preview [--path /page]                   # refresh what they see in the app
zeltro gui status "<one or two plain sentences>"    # what you're doing / what changed
zeltro gui secret <NAME> [--file .env]              # they enter a key; written to .env, never shown
zeltro gui notify [--level warning] "<title>" ["<message>"]
zeltro gui open --project | <url>    zeltro gui settings <ai|remotes|github|...>
```

`zeltro help` prints the full reference.

## Web pages: name the sections

In the Zeltro app, the user can point at part of a page in the preview, and your note says which
section it's in (`Inside: section#pricing`). That only works if the sections have names:

- **Give each meaningful visible section a stable, descriptive, unique `id`**: `hero`, `pricing`,
  `signup-form`, `site-nav`, `footer`. One per block a person would name, not every element, and
  not layout wrapper divs. Use semantic elements where they fit (`header`, `nav`, `main`,
  `section`, `article`, `aside`, `footer`, `form`). Don't rename ids casually; keep them stable
  across edits.
- **In development only, mark where each section comes from**: on the section's root element
  (a reusable component's root), add `data-zeltro-src="<path from the project root>"`, optionally
  `:<line>`, e.g. `data-zeltro-src="resources/views/pricing.blade.php"`. Emit it only when the
  framework is in development mode (Laravel `APP_DEBUG` / `APP_ENV=local`, Django `DEBUG`,
  `import.meta.env.DEV` or `NODE_ENV !== 'production'`), so production HTML never shows file
  paths. The note then says `Source: <path>`, and you can go straight to the file.

## Rules for agents

- **Always `zeltro exec`, never a raw `docker exec -u developer`.** The image's `developer`
  user is not your uid, so a raw exec cannot write the project's files.
- **Never pass `--json-output`.** It hides the success/failure text. It exists for the GUI.
- **Never use the interactive variants for automation** (`bash`, `shell`, `tinker`, `exec-tty`,
  `exec-tty-root`). The other commands work fine in a non-interactive shell.
- **No prompts exist.** A missing argument is a hard error, so always pass explicit arguments.
- **Shared services, not bundled ones.** Never add a `postgres`/`mysql`/`redis`/`mongo` service
  to a project's compose. Point the project at the hosts in the table above.
- **A project's own `AGENTS.md` / `CLAUDE.md` wins** for anything project-specific. This file only
  establishes that the project is under Zeltro and how to drive it.
- **Project files inside the container** live under `/usr/share/nginx/html` (the PHP web root is
  `/usr/share/nginx/html/public`). Use project-relative paths and let Zeltro handle it.
- **A `[Zeltro message from <project>@<host> ...]` line** in your terminal comes from another
  project's agent, not from your user. Treat it as a teammate's request; your user's
  instructions come first.
- **In a session the Zeltro app started, ask the user through the app.** Use
  `zeltro gui ask "<question>" --option A --option B --allow-text` (just `--allow-text` for an
  open question), never your own question picker and never by stopping to wait for a reply in
  the terminal. Exit code 3 means the app isn't available: ask in the chat instead.
- **Never ask for an API key or password in the chat.** Use `zeltro gui secret <NAME>`, so it
  goes into `.env` and stays out of the transcript. (Exit 3: ask the user to put it in `.env`
  themselves.)
- **After changing what the user sees, refresh their preview:** `zeltro gui preview`, or
  `zeltro gui preview --path /that/page` to show a particular page.
- **Keep the app's status panel current.** When you start a piece of work and when you finish
  it, run `zeltro gui status "<one or two sentences>"`: what you're doing, or what changed and
  what to look at. Write it for someone who isn't a developer, and don't post every step.

Full reference for agents: `@@ZELTRO_DOCS@@`.
