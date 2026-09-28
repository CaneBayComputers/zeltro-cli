---
title: Architecture
nav_order: 10
---

# Architecture

---

## Shared services

One set of service containers serves every project on the machine.

Redis, Memcached and the mail catcher always run. The database servers do not:
each one starts the first time a project on the machine needs it, and then stays
on. A machine with only Postgres projects never runs MariaDB or MongoDB.

This is Zeltro's central design decision, and it is a **trade-off rather than a
free win** — worth understanding before you build a workflow on it.

**What you gain.** Most per-project Docker setups start a database container per
project. Twenty projects running means twenty database containers. Zeltro runs
one. On a developer workstation that is frequently the difference between
"I can have all my client sites up" and "I can have three." It is also why a
project's `.env` needs no per-project database plumbing: the hostnames below are
the same in every project, forever.

**What you give up.** These follow directly from the same decision:

- **One version of each engine, machine-wide.** The shared servers run MariaDB 12,
  PostgreSQL 17 and MongoDB 8. A project that needs MySQL 5.7 or PostgreSQL 15
  cannot get it from them. Pin the version per project and you are back to a
  container per project.
- **Shared lifecycle.** `zeltro down <project>` stops only that project, but
  `zeltro stop-services` stops the services for *every* project, not just the one
  you were working on.
- **Shared blast radius.** A corrupted data volume, a runaway migration, or a
  `DROP DATABASE` affects one server that everything else is also using. Project
  databases are isolated by name, not by process.
- **Shared credentials.** Every project connects as `root`. This is a local
  development tool and the database servers publish no ports outside the Docker
  network (only the mail catcher's web UI, port 8025, is published on the host),
  but it is not a model to copy into production.

**When Zeltro is the wrong choice:** you need per-project database versions, or
you need your local environment to mirror production topology exactly. Tools that
run a full stack per project — DDEV, Lando, or plain Docker Compose — are a
better fit for both, at the cost of the resource usage described above.

**When it is the right one:** you run many small-to-medium projects on one
machine and would rather spend that memory on the projects than on twenty copies
of MariaDB.

**Always on:**

| Service | Hostname | Port | User | Password |
|---|---|---|---|---|
| Redis 8 | `zeltro-redis` | 6379 | — | *(none)* |
| Memcached 1.6 | `zeltro-memcached` | 11211 | — | *(none)* |
| Mail catcher ([Mailpit](https://mailpit.axllent.org/)) | `zeltro-mailhog` | SMTP 1025 / UI 8025 | — | *(none)* |

The mail catcher is Mailpit, a MailHog replacement. It keeps the `zeltro-mailhog`
hostname so existing projects don't need changing. Its web UI is also published
on the host at `http://localhost:8025`.

**Databases, started when a project needs one:**

| Service | Hostname | Port | User | Password |
|---|---|---|---|---|
| MariaDB 12 (MySQL-compatible) | `zeltro-mariadb` | 3306 | `root` | *(empty)* |
| PostgreSQL 17 | `zeltro-postgres` | 5432 | `root` | `password` |
| MongoDB 8 | `zeltro-mongo` | 27017 | `root` | `password` |

`zeltro new`, `clone`, `setup`, `install` and `up` work out which database a
project uses and enable that server if it isn't running yet. You don't have to
do anything. To turn one on by hand, use `zeltro enable-service mysql`,
`postgres` or `mongo`.

Use these hostnames and credentials directly when configuring a project — there's no need to inspect containers to discover them. Zeltro writes them into each project's `.env` automatically.

### Optional shared services

Everything except Redis, Memcached and the mail catcher is optional: the three databases above, plus object storage, a search engine and web admin UIs. They sit behind Docker Compose profiles and stay off until a machine asks for them, so a machine doesn't pay the RAM for services none of its projects use.

```bash
zeltro enable-service minio
zeltro enable-service adminer
zeltro disable-service minio      # data volume is kept
zeltro enable-service --help      # list every optional service
```

Once enabled they start with every `zeltro up` and resolve by hostname from inside any project container, exactly like the always-on services. The enabled list persists in `OPTIONAL_SERVICES` in `/etc/zeltro-cli/.env`.

| Service | Slug | Host | Port | Credentials |
|---|---|---|---|---|
| MinIO-compatible S3 storage ([Silo](https://github.com/pgsty/silo), the maintained MinIO fork) | `minio` | `zeltro-minio` | API 9000 / console 9001 | `root` / `password` |
| Meilisearch (full-text search) | `meilisearch` | `zeltro-meilisearch` | 7700 | master key `zeltro-dev-master-key` |
| phpMyAdmin (MariaDB) | `phpmyadmin` | `zeltro-phpmyadmin` | 80 | `root`, no password |
| Adminer (MariaDB, PostgreSQL, SQLite, MongoDB) | `adminer` | `zeltro-adminer` | 8080 | `root` and that database's password |
| Mongo Express | `mongo-express` | `zeltro-mongo-express` | 8081 | none |
| RedisInsight | `redisinsight` | `zeltro-redisinsight` | 5540 | none |

The admin UIs come already connected to the shared servers. RedisInsight shows the shared Redis only after you accept its first-run terms screen.

---

## How a project is reached

Two different mechanisms, and it is worth keeping them apart:

- **Container → container: by name.** Docker's embedded DNS resolves container names on the shared network. Code inside a project can `psql -h zeltro-postgres` or `fetch('http://other-project/')` with no extra configuration. This is how projects share databases and call each other.
- **Host or LAN → project: by address.** Your browser is not on the Docker network, so it uses an address. `zeltro status` prints two for every project:

| From | Address | Why |
|---|---|---|
| The machine running Zeltro | `http://10.x.x.219` | The container's own IP. No port — nothing else is on that address. |
| Another device on the LAN | `http://192.168.1.20:219` | This machine's IP plus the project's published port, which is the last number of its container IP. |

On macOS, Docker Desktop runs containers inside a virtual machine and cannot route traffic to container IPs from the host, so `zeltro status` prints `http://localhost:<port>` as the local address instead.

On Windows, Zeltro runs inside WSL2. The local address works from inside WSL. From a Windows browser, use the LAN address, which is the WSL VM's IP and changes when WSL restarts.

{: .note }
> Zeltro does **not** write to `/etc/hosts`, so `http://my-api/` does not work in a browser on the host. Use the addresses `zeltro status` prints. Earlier versions added a host entry for every project; that is gone, and creating or starting a project no longer needs sudo for it.

---

## VPC and IP allocation

All Zeltro containers attach to the `zeltro-cli_vpc` Docker network (`${VPC_SUBNET}.0/24`, set per machine in `/etc/zeltro-cli/.env`). The address space is partitioned so static IPs never collide with dynamic ones:

| Range | Purpose | Allocation |
|---|---|---|
| `.2`–`.8` | Always-on services, databases and phpMyAdmin | Static |
| `.32`–`.63` | Helper containers (workers, schedulers) | Dynamic |
| `.100`–`.239` | Project entry points | Static, picked at random per project |
| `.250`–`.254` | MinIO, Meilisearch, Adminer, Mongo Express, RedisInsight | Static |

`.240`–`.249` is left free as headroom. Each project's web port is published on the host under its last octet, so a project at `.219` answers on port 219.

Writing a custom compose: give the web-facing service a static IP in `.100`–`.239`, leave helpers without `ipv4_address`, and never touch `.2`–`.8` or `.250`–`.254`.

---

## Base images

Greenfield projects build from one of three images on Docker Hub under `canebaycomputers/cbc`. Each runs nginx + supervisor on Ubuntu Noble. Sources live in [`CaneBayComputers/docker-images`](https://github.com/CaneBayComputers/docker-images), one directory per image.

Override the default with `--image <ref>` on `new`, `clone`, `setup` or `install`.

### `cbc:nginx-php8` — PHP projects

- nginx with FastCGI to `php-fpm8.3` over a Unix socket; web root `/usr/share/nginx/html/public`
- PHP 8.3 with `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `redis`, `mongodb`, `gd`, `intl`, `mbstring`, `imagick`, `zip`, `soap`, `xdebug`, plus `php-codesniffer` and `phpmd`
- Composer, WP-CLI and Node 22 (for Vite/npm builds) are included
- Supervisor runs nginx, php-fpm and a Laravel queue worker (4 processes, autostart)

### `cbc:nginx-python3` — Python projects

- nginx reverse proxy, port 80 → `localhost:8000`, with WebSocket upgrade headers
- Preinstalled: `fastapi`, `uvicorn`, `django`, `flask`, `gunicorn`, `python-dotenv`, `sqlalchemy`, `psycopg2-binary`, `PyMySQL`, `pymongo`, `redis`, `pymemcache`
- Supervisor runs `PYTHON_APP_COMMAND`; the app must bind port 8000
- `python3` is available; `python` is not

### `cbc:nginx-node` — Node projects

- nginx reverse proxy, port 80 → `localhost:3000`, with WebSocket upgrade headers
- Node 22 LTS
- Supervisor runs `NODE_APP_COMMAND`; the app must bind port 3000. Set `PORT=3000` in `.env` for frameworks that default elsewhere.

{: .note }
Project containers are **recreated from the base image on every `zeltro up`**. Anything installed into a running container's filesystem is lost — only the bind-mounted project directory survives. That's why every framework's runtime is baked into the image, and why a SQLite database must live in the project directory.

---

## Compose adaptation

When `zeltro clone` or `zeltro setup` meets a `docker-compose.yaml` with more than one service or a non-cbc image, Zeltro adapts it:

- Bundled `postgres` / `mysql` / `mariadb` / `redis` / `valkey` / `mongodb` services are removed, and env vars referencing them are repointed at the shared hostnames
- The web-facing service gets a static VPC IP and a `container_name` matching the project
- Other services attach to the network without a fixed IP
- The original is preserved as `docker-compose.upstream.yaml` (first run only, so the true original survives re-runs)
- `docker-compose.yaml` is added to `.gitignore`, so the Zeltro-managed file isn't committed back to a shared repo

Image type only affects this adaptation. **Framework steps — dependency install, `.env` wiring, storage symlink, migrations — are driven by framework detection** and run for adapted projects too.

Useful flags: `--no-startup` to review the adapted compose before it boots, `--overwrite-env` to repoint an existing app's `.env` at the shared services while preserving `APP_KEY`, `--db-name <name>` to pick the database, `--no-migration` to skip migrations.

---

## Project layout

```
~/zeltro-projects/
├── my-api/
│   ├── docker-compose.yaml          # Zeltro-managed (gitignored)
│   ├── docker-compose.upstream.yaml # the original, if there was one
│   ├── AGENTS.md                    # hand-off context for AI agents
│   ├── .env
│   └── [your project files]
└── my-shop/
```

`~/zeltro-projects` is the default. `zeltro projects-dir` prints the one this machine uses. The projects directory also gets its own `AGENTS.md` with this machine's service names.

Runtime configuration lives in `/etc/zeltro-cli/.env`. On a machine installed before the rename from Podium, containers and the network use `podium-*` names (`podium-cli_vpc`) instead of `zeltro-*`.
