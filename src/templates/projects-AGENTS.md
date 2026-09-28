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
zeltro gui ask "<question>" --option A --option B   # prints the answer they pick
zeltro gui secret <NAME> [--file .env]              # they enter a key; written to .env, never shown
zeltro gui notify [--level warning] "<title>" ["<message>"]
zeltro gui open --project | <url>    zeltro gui settings <ai|remotes|github|...>
```

`zeltro help` prints the full reference.

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
- **Never ask for an API key or password in the chat.** Use `zeltro gui secret <NAME>`, so it
  goes into `.env` and stays out of the transcript. For a choice between options, prefer
  `zeltro gui ask`. Exit code 3 means the app isn't available: ask in the chat instead (and for
  a secret, ask the user to put it in `.env` themselves).

Full reference for agents: `@@ZELTRO_DOCS@@`.
