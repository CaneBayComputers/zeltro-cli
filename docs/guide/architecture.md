---
title: Architecture
nav_order: 10
---

# Architecture

---

## Shared services

One set of service containers serves every project on the machine.

This is Zeltro's central design decision, and it is a **trade-off rather than a
free win** — worth understanding before you build a workflow on it.

**What you gain.** Most per-project Docker setups start a database container per
project. Twenty projects running means twenty database containers. Zeltro runs
one. On a developer workstation that is frequently the difference between
"I can have all my client sites up" and "I can have three." It is also why a
project's `.env` needs no per-project database plumbing: the hostnames below are
the same in every project, forever.

**What you give up.** These follow directly from the same decision:

- **One version of each engine, machine-wide.** A project needing MySQL 5.7 and
  another needing MySQL 8 cannot both run against the shared server. Pin the
  version per project and you are back to a container per project.
- **Shared lifecycle.** `zeltro down` stops the services for *every* project, not
  just the one you were working on.
- **Shared blast radius.** A corrupted data volume, a runaway migration, or a
  `DROP DATABASE` affects one server that everything else is also using. Project
  databases are isolated by name, not by process.
- **Shared credentials.** Every project connects as `root`. This is a local
  development tool and the services are not exposed outside the Docker network,
  but it is not a model to copy into production.

**When Zeltro is the wrong choice:** you need per-project database versions, or
you need your local environment to mirror production topology exactly. Tools that
run a full stack per project — DDEV, Lando, or plain Docker Compose — are a
better fit for both, at the cost of the resource usage described above.

**When it is the right one:** you run many small-to-medium projects on one
machine and would rather spend that memory on the projects than on twenty copies
of MariaDB.

| Service | Hostname | Port | User | Password |
|---|---|---|---|---|
| PostgreSQL | `zeltro-postgres` | 5432 | `root` | `password` |
| MariaDB / MySQL | `zeltro-mariadb` | 3306 | `root` | *(empty)* |
| Redis | `zeltro-redis` | 6379 | — | *(none)* |
| MongoDB | `zeltro-mongo` | 27017 | `root` | `password` |
| Memcached | `zeltro-memcached` | 11211 | — | *(none)* |
| MailHog | `zeltro-mailhog` | SMTP 1025 / UI 8025 | — | *(none)* |
| phpMyAdmin | `zeltro-phpmyadmin` | 80 | — | — |

### Optional shared services

Most projects need a database, which is what justifies the core services always running. Far fewer need object storage or a search engine, so those sit behind Docker Compose profiles and stay off until a machine asks for them — rather than every install paying that RAM to benefit a few.

```bash
zeltro enable-service minio
zeltro enable-service meilisearch
zeltro disable-service minio      # data volume is kept
```

Once enabled they start with every `zeltro up` and resolve by hostname from inside any project container, exactly like the core services. The enabled list persists in `OPTIONAL_SERVICES` in `/etc/zeltro-cli/.env`.

| Service | Host | Port | Credentials |
|---|---|---|---|
| MinIO | `zeltro-minio` | API 9000 / console 9001 | `root` / `password` |
| Meilisearch | `zeltro-meilisearch` | 7700 | master key `zeltro-dev-master-key` |

Use these hostnames and credentials directly when configuring a project — there's no need to inspect containers to discover them. Zeltro writes them into each project's `.env` automatically.

---

## How a project is reached

Two different mechanisms, and it is worth keeping them apart:

- **Container → container: by name.** Docker's embedded DNS resolves container names on the shared network. Code inside a project can `psql -h zeltro-postgres` or `fetch('http://other-project/')` with no extra configuration. This is how projects share databases and call each other.
- **Host or LAN → project: by address.** Your browser is not on the Docker network, so it uses an address. `zeltro status` prints two for every project:

| From | Address | Why |
|---|---|---|
| The machine running Zeltro | `http://10.x.x.219` | The container's own IP. No port — nothing else is on that address. |
| Another device on the LAN | `http://192.168.1.20:219` | This machine's IP plus the project's published port. |

On macOS and Windows, Docker runs containers inside a virtual machine and the container IP is not routable from the host, so the local address is `http://localhost:<port>` instead. `zeltro status` detects this and prints whichever one works.

{: .note }
> Zeltro does **not** write to `/etc/hosts`, and has not since the entries were removed. Nothing about running a project needs sudo. Earlier versions added a host entry so `http://my-api/` worked in the browser; that is gone, and the addresses above replace it.

---

## VPC and IP allocation

All Zeltro containers attach to the `zeltro-cli_vpc` Docker network (`${VPC_SUBNET}.0/24`, set per machine in `/etc/zeltro-cli/.env`). The address space is partitioned so static IPs never collide with dynamic ones:

| Range | Purpose | Allocation |
|---|---|---|
| `.2`–`.15` | Shared services (core `.2`–`.8`, optional `.9`–`.15`) | Static |
| `.32`–`.63` | Helper containers (workers, schedulers) | Dynamic |
| `.100`–`.250` | Project entry points | Static, assigned per project |

Writing a custom compose: give the web-facing service a static IP in `.100`–`.250`, leave helpers without `ipv4_address`, and never touch `.2`–`.8`.

---

## Base images

Greenfield projects build from one of three images on Docker Hub under `canebaycomputers/cbc`. Each runs nginx + supervisor on Ubuntu Noble. Sources live in [`CaneBayComputers/docker-images`](https://github.com/CaneBayComputers/docker-images), one directory per image.

Override the default with `--image <ref>` on `new`, `clone`, `setup` or `install`.

### `cbc:nginx-php8` — PHP projects

- nginx with FastCGI to `php-fpm8.3` over a Unix socket; web root `/usr/share/nginx/html/public`
- PHP 8.3 with `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `redis`, `mongodb`, `gd`, `intl`, `mbstring`, `imagick`, `zip`, `soap`, `xdebug`, plus `php-codesniffer` and `phpmd`
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

Runtime configuration lives in `/etc/zeltro-cli/.env`.
