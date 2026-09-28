# DEVELOPMENT.md

> For modifying Zeltro's source code itself.
> If you're using Zeltro to install/build/deploy projects, see [AGENTS.md](AGENTS.md).

## Initial Reading

Read these first to understand the codebase:

1. `src/scripts/functions.sh` — shared helpers used across all scripts (echo wrappers, JSON output, sudo helpers, color detection).
2. `src/scripts/configure.sh` — sets up Zeltro and the dev environment; reference for conventions.
3. `src/zeltro` — the Bash entrypoint that wires subcommands.

Each subcommand maps directly to `src/scripts/<command>.sh` (e.g. `zeltro clone` → `src/scripts/clone_project.sh`). Read the relevant script when working on a specific command.

## Project Structure & Module Organization

| Path | Purpose |
|---|---|
| `src/zeltro` | Bash entrypoint; dispatches subcommands. |
| `src/scripts/` | Per-subcommand logic. Group related workflows beside their support files. |
| `src/docker-stack/` | Compose templates and defaults for shared services. Update `env.example` when adding variables. |
| `src/installers/` | Curated installers for OSS apps. Format documented in [AGENTS.md → Writing Installers](AGENTS.md#writing-installers). |
| `src/project-hints/` | Per-project setup hints used by `zeltro create`. |
| `src/catalog/` | Stack catalogue driving `zeltro create`'s classifier. `frameworks.json` is hand-maintained (including each framework's supported databases); `apps.json` is **generated** — re-run `bash src/scripts/build_catalog.sh` after adding, removing or re-pointing an installer. |
| `install-ubuntu.sh` / `install-arch.sh` / `install-fedora.sh` / `install-mac.sh` | The only scripts that touch host package managers. Adding one means wiring its distro IDs into `update.sh`'s `--full` platform detection too. |
| `logs/` | Runtime logs land here, not the repo root. |
| `/etc/zeltro-cli/.env` | Resolved runtime configuration. Ship defaults via `env.example`, never commit secrets. |

## Build, Test, and Development Commands

- Run the CLI as `zeltro <command>`. Do **not** invoke `./src/zeltro` directly.
- Use `zeltro <command> --json-output` to exercise automation outputs (some commands lack this — check `--help` first).
- Regression coverage: `zeltro test-json-output [case]`. Tear down fixtures with `zeltro cleanup-test-environment`.
- Static analysis runs inside the project container (run from the project root, paths relative):
  - `zeltro phpcs <relative-path>` — PHPCS with the default ruleset.
  - `zeltro phpcbf <relative-path>` — PHPCBF auto-fix.
  - `zeltro phpmd <relative-path>` — PHPMD against a file.
  - `zeltro php -l <relative-path>` — PHP lint.
- `--debug` enables logging to `/tmp/zeltro-cli-debug.log`. Each new command starts a fresh session. Useful for diagnosing script-flow issues.

Use `zeltro` commands freely when testing or validating changes — spinning up a project, running exec commands, checking output — just as a user would.

## Coding Style & Naming Conventions

- Author scripts with `#!/bin/bash`, `set -e`, four-space indentation, snake_case helpers (`init_projects_dir`).
- Prefer extending shared utilities in `functions.sh` so color handling, JSON quiet mode, and logging stay consistent.
- New commands follow verb-first naming (`zeltro cleanup-test-environment`) and reuse the echo wrappers (`echo-cyan`, `echo-yellow`, etc.) instead of raw `echo`.

### `set -e` traps

`set -e` is mandatory but watch for non-obvious aborts:

- **`tput`** exits non-zero when `$TERM` is unset (plain `ssh host cmd` without `-t`). `functions.sh` auto-detects this and forces `NO_COLOR=1` at the top.
- **`trash-put`** refuses to overwrite an existing trash entry. `remove_project.sh` works around this by renaming with a timestamp suffix before trashing.

When using a command that can fail this way, wrap in `if !` / `|| true` or detect the failure mode upfront. Never disable `set -e`.

## Adding a New Subcommand

1. Create `src/scripts/<verb>.sh` with the standard preamble (`set -e`, source `functions.sh`).
2. Wire dispatch in `src/zeltro` — add a `case` arm matching the verb.
3. Update help text in `src/zeltro` (the `--help` block) and the README's "Commands Overview" table.
4. If the command exposes structured output, support `--json-output`.
5. If the command is agent-relevant, mention it in [AGENTS.md → Commands You'll Use Most](AGENTS.md#commands-youll-use-most).

## Adding or Modifying a Shared Service

Shared services live in `src/docker-stack/docker-compose.services.yaml`. Each service gets a static IP in `.2`–`.8`, a `container_name` of `zeltro-<service>`, and attaches to `zeltro-cli_vpc`.

When editing the file:

- Optional services go behind a compose `profiles: ["<name>"]` key and take a static IP in `.9`–`.15`. Add the name to `AVAILABLE_OPTIONAL_SERVICES` in `src/scripts/enable_service.sh`. They are enabled per machine via `zeltro enable-service`, which persists the list in `OPTIONAL_SERVICES` in `/etc/zeltro-cli/.env` — write that value **quoted**, since the file is `source`d by bash and a bare space-separated list would execute the second word as a command.
- Preserve the `ip_range: ${VPC_SUBNET}.32/27` block on the network. Without it, Docker hands out dynamic IPs starting at `.2` and helper containers in multi-service projects squat on shared-service IPs whenever those services are temporarily down — blocking them from coming back up.
- The deployed copy lives at `/etc/zeltro-cli/docker-compose.yaml`, copied once on first `zeltro configure`. It does **not** auto-resync on `zeltro update`. To pick up changes on existing installs:

  ```bash
  sudo cp src/docker-stack/docker-compose.services.yaml /etc/zeltro-cli/docker-compose.yaml
  docker network rm zeltro-cli_vpc
  zeltro start-services
  ```

## Updating cbc Base Docker Images

The three cbc images are documented in [AGENTS.md → cbc Base Docker Images](AGENTS.md#cbc-base-docker-images). All of them live in the single `CaneBayComputers/docker-images` repo, one directory per image (`cbc-docker-php8-nginx/`, `cbc-docker-python3-nginx/`, `cbc-docker-node-nginx/`, `cbc-docker-php8-nginx-vector/`).

**When adding a framework to `zeltro new`, check whether its runtime is in the image.** Project containers are recreated from the base image on every `zeltro up`, so anything pip/npm installed into a running container is lost. If the framework's package isn't baked into the Dockerfile, projects come back as a 502 after their first restart. `startup.sh` reinstalls `requirements.txt` as a safety net, but the image is the correct fix (this is exactly what Flask hit).

To rebuild and publish:

1. Edit the relevant file in `docker-images/<image-dir>/`.
2. Commit and push the repo.
3. From the repo directory: `sudo bash build_push.sh` — builds, tags, and pushes to Docker Hub.
4. Existing running containers will not pick up the new image automatically. They need `zeltro down <name> && zeltro up <name>`.

## Testing Guidelines

- Add new coverage by extending `src/scripts/test_json_output.sh`. Name scenarios after the command under test (`new_laravel_latest`).
- Keep Docker noise isolated by using the `zeltro_test_` container/network prefixes and call `cleanup-test-environment` from failure handlers.
- Capture debug data with the `--debug` flag and attach the relevant portion of `/tmp/zeltro-cli-debug.log` to reviews when issues arise.

## OSS Project Testing

Zeltro is validated against real OSS apps by deploying them end-to-end across multiple machines using AI agents.

### Workflow

1. Write a `tests/oss-<machine>.sh` harness — one `run_project()` call per app, all run in parallel via `&` + `wait`.
2. Each `run_project` call runs `zeltro create --one-off "<idea>"` and curls the result. Each idea includes a `SUMMARY_SUFFIX` instructing the agent to write `SETUP_SUMMARY.md` in the project dir.
3. After runs complete, read the master log (`/tmp/zeltro-tests/oss-master.log`) and `SETUP_SUMMARY.md` files to assess results.
4. For any app that failed or needed agent workarounds, create or update a `src/project-hints/<slug>.md` file so future runs succeed first-try.

### Test fleet

See `machines.local` in the repo root for the current machine list. Canonical setup:

| Machine | Agent | Test scripts |
|---------|-------|-------------|
| dingdong | claude | `tests/oss-dingdong.sh`, `tests/oss2-dingdong.sh`, `tests/custom-dingdong.sh`, `tests/installers-dingdong.sh`, `tests/installers2-dingdong.sh` |
| cami | codex | `tests/oss-cami.sh`, `tests/oss2-cami.sh`, `tests/custom-cami.sh`, `tests/installers-cami.sh`, `tests/installers2-cami.sh` |
| cassie | gemini/codex | `tests/oss-cassie.sh`, `tests/oss2-cassie.sh`, `tests/custom-cassie.sh`, `tests/installers-cassie.sh`, `tests/installers2-cassie.sh` |

SSH access: `ssh cami@cami`, `ssh cassie@cassie`. Pull repo on remotes: `ssh cami@cami "sudo git -C /usr/local/share/zeltro-cli pull"`.

### Adding more OSS apps to test

1. Add `run_project "<name>" "$IDEA_<NAME>"` entries to the relevant `tests/oss-<machine>.sh`.
2. Write the `IDEA_*` variable following the established pattern: exact project name, image, port, nginx-or-direct, DB requirements, step-by-step instructions, `$SUMMARY_SUFFIX`.
3. Always spell out `mkdir -p ~/zeltro-projects/<name>` in the steps to prevent agent renaming.
4. Run: `bash tests/oss-<machine>.sh`
5. After completion, check `/tmp/zeltro-tests/oss-master.log` and `SETUP_SUMMARY.md` files.
6. Create/update `src/project-hints/<slug>.md` for any app that needed workarounds.
7. Commit updated hints and test scripts.

### OSS apps with validated hints

The following have been deployed successfully and have `src/project-hints/` files validated by real test runs:

| App | Image | Notes |
|-----|-------|-------|
| FreshRSS | `freshrss/freshrss:latest` | Port 80 direct, SQLite |
| Memos | `neosmemo/memos:stable` | Port 5230 → nginx |
| Grocy | `lscr.io/linuxserver/grocy:latest` | Port 80 direct |
| Snipe-IT | `snipe/snipe-it:latest` | Needs generated APP_KEY, MariaDB |
| Kimai | `kimai/kimai2:apache` | Port 8001 → nginx, MariaDB |
| Redmine | `redmine:latest` | Port 3000 → nginx, MariaDB utf8mb4, wait 60s |
| Lychee | `lycheeorg/lychee:latest` | Port 8000 → nginx, needs APP_KEY + dedicated DB user |
| Wallabag | `wallabag/wallabag:latest` | Port 80 direct, MariaDB |
| Stirling PDF | `frooodle/s-pdf:latest` | Port 8080 → nginx, needs SECURITY_ENABLE_LOGIN=false |
| IT Tools | `corentinth/it-tools:latest` | Port 80 direct, no config |
| Changedetection | `ghcr.io/dgtlmoon/changedetection.io` | Port 5000 → nginx, WebSocket headers |
| Flame | `pawelmalak/flame:latest` | Port 5005 → nginx |
| Heimdall | `lscr.io/linuxserver/heimdall:latest` | Port 80 direct |
| Umami | `ghcr.io/umami-software/umami:postgresql-latest` | Port 3000 → nginx, **PostgreSQL only** |
| Dashy | `lissy93/dashy:latest` | Port 8080 → nginx |
| LimeSurvey | `martialblog/limesurvey:latest` | Port 8080 → nginx, needs dedicated DB user (empty password rejected) |
| Miniflux | `miniflux/miniflux:latest` | Port 8080 → nginx, **PostgreSQL only**, RUN_MIGRATIONS=1 |
| Grafana | `grafana/grafana:latest` | Port 3000 → nginx |
| Vikunja | `vikunja/vikunja:latest` | Port 3456 → nginx, MariaDB, needs JWTSECRET |
| Mealie | `ghcr.io/mealie-recipes/mealie:latest` | Port 9000 → nginx, SQLite |
| Portainer | `portainer/portainer-ce:latest` | Port 9000 → nginx, needs docker.sock mount |
| Netdata | `netdata/netdata:latest` | Port 19999 → nginx, needs cap_add + host bind mounts |
| Vaultwarden | `vaultwarden/server:latest` | Port 80 direct |
| Kanboard | `kanboard/kanboard:latest` | Port 80 direct |
| Gitea | `gitea/gitea:latest` | Port 3000 → nginx, MariaDB, GITEA__ env prefix |
| Wiki.js | `ghcr.io/requarks/wiki:2` | Port 3000 → nginx, PostgreSQL |
| Jellyfin | `jellyfin/jellyfin:latest` | Port 8096 → nginx, no DB |
| Paperless-ngx | `ghcr.io/paperless-ngx/paperless-ngx:latest` | Port 8000 → nginx, PostgreSQL + Redis |
| Uptime Kuma | `louislam/uptime-kuma:1` | Port 3001 → nginx, SQLite, WebSocket |
| Ghost | `ghost:latest` | Port 2368 → nginx, SQLite for dev |
| BookStack | `lscr.io/linuxserver/bookstack:latest` | Port 80 direct, MariaDB, needs APP_KEY |
| Homer | `b4bz/homer:latest` | Port 8080 → nginx, YAML config |
| Monica | `monica:latest` | Port 80 direct, MariaDB + Redis, needs APP_KEY |
| Listmonk | `listmonk/listmonk:latest` | Port 9000 → nginx, PostgreSQL, --install on start |
| HedgeDoc | `quay.io/hedgedoc/hedgedoc:latest` | Port 3000 → nginx, PostgreSQL, WebSocket |
| Linkwarden | `ghcr.io/linkwarden/linkwarden:latest` | Port 3000 → nginx, PostgreSQL, NEXTAUTH_URL path |
| Tandoor | `vabene1111/recipes:latest` | Port 8080 → nginx, PostgreSQL, static/media volumes |
| n8n | `n8nio/n8n:latest` | Port 5678 → nginx, SQLite, WebSocket |
| Actual Budget | `actualbudget/actual-server:latest` | Port 5006 → nginx, no DB |
| Nextcloud | `nextcloud:latest` | Port 80 direct, MariaDB + Redis |
| PhotoPrism | `photoprism/photoprism:latest` | Port 2342 → nginx, MariaDB, large client_max_body_size |
| Immich | `ghcr.io/immich-app/immich-server:release` | Port 2283 → nginx, dedicated pgvecto-rs DB + shared Redis |
| Trilium Notes (TriliumNext) | `ghcr.io/triliumnext/trilium:v0.104.1` | Port 8080 → nginx, SQLite |
| SearXNG | `searxng/searxng:latest` | Port 8080 → nginx, no DB |
| Glances | `nicolargo/glances:latest-full` | Port 61208 → nginx, pid:host + docker.sock |
| wger | `wger/server:latest` | Port 80 direct + celery workers, PostgreSQL + Redis, config/prod.env |
| Mattermost | `mattermost/mattermost-team-edition:latest` | Port 8065 → nginx, PostgreSQL, WebSocket |
| Outline | `outlinewiki/outline:latest` | Port 3000 → nginx, PostgreSQL + Redis, needs auth provider |

## Configuration & Security Notes

- Document new environment variables in `src/docker-stack/env.example` and keep defaults non-sensitive.
- Any credentials belong in `/etc/zeltro-cli/.env` or developer-specific overrides, never in tracked files or example data.

## Keeping Docs in Sync

Three doc surfaces, three audiences:

- **`README.md`** — humans deciding whether to use Zeltro and learning how. Update when adding/changing user-visible commands or capabilities.
- **`AGENTS.md`** — agents *using* Zeltro. Update when adding agent-relevant features (commands, shared services, installer conventions, networking rules).
- **`DEVELOPMENT.md`** (this file) — developers/agents *modifying* Zeltro. Update when changing internals (file layout, dispatch, testing infra).

Keep AGENTS.md tight. Every byte added there is paid for in tokens on every `zeltro create` / `zeltro update-installer` / `zeltro create-installer` run.
