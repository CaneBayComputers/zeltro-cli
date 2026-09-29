---
title: Command reference
nav_order: 9
---

# Command reference

Run `zeltro --help` for the same list in your terminal, or `zeltro <command> --help` for one command.

Commands marked *(project dir)* must be run from inside a project directory.

---

### 🛠️ Development Tools
*Run from project directory*

| Command | Description |
|---------|-------------|
| `zeltro composer <args>` | Run Composer commands inside container |
| `zeltro art <args>` | Run Laravel Artisan commands (alias: `zeltro artisan`) |
| `zeltro wp <args>` | Run WordPress CLI commands |
| `zeltro drush <args>` | Run Drush (Drupal) from the project's `vendor/bin` |
| `zeltro php <args>` | Run PHP inside container |
| `zeltro npm <args>` | Run npm commands inside container |
| `zeltro npx <args>` | Run npx commands inside container |
| `zeltro node <args>` | Run Node.js inside container |
| `zeltro python <args>` | Run `python3` inside container (alias: `zeltro python3`) |
| `zeltro pip <args>` | Run `pip3` inside container (alias: `zeltro pip3`); `pip install` adds `--break-system-packages` |
| `zeltro shell` | Open framework-aware interactive shell or REPL |

### ✅ Static Analysis & Linting
*Run from project directory; paths are relative to the project root (for example `app/Console/Commands/Foo.php`)*

| Command | Description |
|---------|-------------|
| `zeltro phpcs <relative-path>` | Run PHPCS with the default ruleset |
| `zeltro phpcbf <relative-path>` | Run PHPCBF with the default ruleset to auto-fix |
| `zeltro phpmd <relative-path>` | Run PHPMD against a file using the default rules |
| `zeltro php -l <relative-path>` | Run PHP lint against a file |

### 📦 Container Execution
*Run from project directory*

| Command | Description |
|---------|-------------|
| `zeltro exec <cmd>` | Execute command as developer user (no TTY, automation‑friendly) |
| `zeltro exec-root <cmd>` | Execute command as root user (no TTY) |
| `zeltro exec-tty <cmd>` | Execute command as developer user with TTY (interactive) |
| `zeltro exec-tty-root <cmd>` | Execute command as root user with TTY (interactive) |
| `zeltro bash [args]` | Open bash shell inside container with TTY |
| `zeltro tinker [args]` | Open Laravel tinker REPL inside container with TTY |

### ⚡ Enhanced Laravel Commands
*Run from project directory*

| Command | Description |
|---------|-------------|
| `zeltro db-refresh` | Fresh migration + seed |
| `zeltro cache-refresh` | Clear all Laravel caches |

### 🐍 Enhanced Django Commands
*Run from project directory*

| Command | Description |
|---------|-------------|
| `zeltro django manage <args>` | Run `manage.py` with arguments |
| `zeltro django shell` | Open Django interactive shell |

### 🔧 Service Management
*Run from anywhere*

| Command | Description |
|---------|-------------|
| `zeltro mysql <args>` | Run the MariaDB client as `root` inside the `zeltro-mariadb` container (the `mysql` service must be enabled) |
| `zeltro redis <cmd>` | Run Redis CLI commands (no arguments opens the REPL) |
| `zeltro redis-flush` | Flush all Redis data |
| `zeltro memcache <cmd>` | Send a raw command to Memcached (`stats`, `version`, `flush_all`, `get <key>`, `set <key> <value>`) |
| `zeltro memcache-flush` | Flush all Memcached data |
| `zeltro memcache-stats` | Show Memcached statistics |

### 🎛️ Process Management
*Run from project directory*

| Command | Description |
|---------|-------------|
| `zeltro supervisor <cmd>` | Run supervisorctl commands |
| `zeltro supervisor-status` | Show all supervised processes |

### 📁 Project Management

| Command | Description |
|---------|-------------|
| `zeltro up <project>` | Start a project (shared services start regardless) |
| `zeltro up-all` | Start every project (disabled projects are skipped) |
| `zeltro down <project>` | Stop a project (shared services stay up — use `zeltro stop-services`) |
| `zeltro down-all` | Stop every project (shared services stay up) |
| `zeltro status [project] [--all]` | Show running projects and each one's local and LAN address; `--all` includes stopped projects |
| `zeltro new <framework> <name> [options]` | Create a new project (framework + name required; DB auto-selected, override with `--database`) |
| `zeltro create "<idea>"` | Create a project from a plain-English idea, then hand off to your AI agent in the project dir |
| `zeltro resume <project>` | Resume the last AI session for a project |
| `zeltro install <app> [name] [--image <ref>]` | Install a popular OSS app in one command (`--list` to see all; `--one-off` skips the AI handoff) |
| `zeltro clone <mode> <repo> [name]` | Clone an existing repo (mode: `work-directly` / `fork` / `new-repo`) |
| `zeltro setup <project> [database] [options]` | Set up an existing project directory |
| `zeltro remove <project> [options]` | Remove a project (DB preserved unless `--force-db-delete`) |
| `zeltro set-metadata <project> [--emoji E] [--name N] [--description D] [--idea TEXT\|--idea-file F\|--idea -]` | Set a project's display emoji, name, description, or the Create with AI idea it came from (any text up to 200 KB; `--idea ""` removes it) |
| `zeltro get-metadata <project> [--idea] [--json-output]` | Show a project's metadata; `--idea` prints just the idea, byte for byte |
| `zeltro disable <project>` | Stop and park a project: skipped by `up-all`, refused by `up`, hidden in the GUI. Nothing is deleted |
| `zeltro enable <project>` | Re-enable a disabled project |

`zeltro status` prints addresses you can open from the host: `http://<container-ip>` locally (or `http://localhost:<port>` on macOS) and `http://<host-lan-ip>:<port>` from the LAN. `http://<project>/` does **not** work from the host — project names resolve only inside containers. There is no `zeltro ps`.

### ⚙️ System Management

| Command | Description |
|---------|-------------|
| `zeltro configure` | Configure the Zeltro environment |
| `zeltro ai [--interactive] "<prompt>"` | Send a prompt to your AI agent (one-off by default) *(project dir)* |
| `zeltro ai-set [options]` | Configure the AI agent, model and API key |
| `zeltro ai-unattended [agent] [--revoke\|--status]` | Let an agent run without approval prompts (written to the agent's own config) |
| `zeltro peers` | List agent sessions running in the Zeltro app, on every host |
| `zeltro send <project>[@host] ... -- <message>` | Message other agent sessions *(project dir)* |
| `zeltro gui <action>` | From an agent in the Zeltro app: ask the user a question, collect a secret into `.env`, notify, or open a URL *(project dir)* |
| `zeltro update [--full]` | Update the CLI with a `git pull` (`--full` also re-runs the platform installer and re-pulls images, stopping running projects) |
| `zeltro start-services` | Start the shared services |
| `zeltro stop-services` | Stop the shared services |
| `zeltro enable-service <name>` | Enable an optional shared service (see below) |
| `zeltro disable-service <name>` | Disable one (its data volume is kept) |
| `zeltro uninstall` | Remove Zeltro's Docker resources and CLI files |
| `zeltro projects-dir` | Print the projects directory path |
| `zeltro version` | Print the version and whether an update is available (also `--version`, `-v`) |
| `zeltro create-installer "<idea>"` | Generate a new app installer via AI (`--print` prints the prompt only) |
| `zeltro update-installer <app>\|--all` | Refresh installers against upstream via AI (`--print` prints the prompt only) |

#### Optional shared services

Only Redis, Memcached and MailHog always run. Everything else is off until enabled, and the enabled list is kept in `OPTIONAL_SERVICES` in `/etc/zeltro-cli/.env`. `zeltro new`, `zeltro setup` and `zeltro install` enable the database a project needs automatically.

| Name | Service | Address (from inside a container) |
|---|---|---|
| `mysql` | MariaDB 12 | `zeltro-mariadb:3306` |
| `postgres` | PostgreSQL 17 | `zeltro-postgres:5432` |
| `mongo` | MongoDB 8 | `zeltro-mongo:27017` |
| `phpmyadmin` | phpMyAdmin | `http://zeltro-phpmyadmin` |
| `adminer` | Adminer | `http://zeltro-adminer:8080` |
| `mongo-express` | mongo-express | `http://zeltro-mongo-express:8081` |
| `redisinsight` | RedisInsight | `http://zeltro-redisinsight:5540` |
| `minio` | S3 storage (Silo, the maintained MinIO fork) | `http://zeltro-minio:9000`, console `:9001` |
| `meilisearch` | Meilisearch | `http://zeltro-meilisearch:7700` |

```bash
zeltro enable-service minio
zeltro disable-service minio
zeltro enable-service --json-output     # no name: list every optional service and its state
```

A service is recorded as enabled only if it starts and stays running. Machines installed before the rename use `podium-*` names instead of `zeltro-*`.

#### Messaging other agent sessions

When the Zeltro app hosts agent sessions in several projects (on one host or several), they can message each other. The app does the routing through a per-user spool at `~/.zeltro/bus/`: it publishes `peers.json`, and `send` drops one JSON file per message in `outbox/`.

```bash
zeltro peers                                   # list live sessions as project@host; marks yours
zeltro peers --json-output
zeltro send blog -- "API schema changed"       # one target
zeltro send blog api@shop -- "Rebuild please"  # several targets
zeltro send --all -- "Heading out"             # every live session except you
git diff | zeltro send api -- -                # read the message from stdin
```

- Run `send` from inside your project directory; that is how you are identified.
- A bare `project` works when only one live session has that name; otherwise use `project@host`.
- Every target must be a live session, or nothing is sent. Messages are capped at 16 KB.
- With a single target the `--` is optional: `zeltro send blog "message"`.
- Exit 0 means queued. The message arrives in the target's terminal as `[Zeltro message from <you>@<host> to <targets>] ...`.

#### Asking the Zeltro app for things

An agent in a session the Zeltro app started can use the app's window to reach the user:

```bash
zeltro gui ask "Which database?" --option Postgres --option MariaDB   # prints the answer
zeltro gui secret STRIPE_KEY --reason "for checkout"   # writes it into .env; never printed
zeltro gui notify --level warning "Tests failing" "3 failures in api/"
zeltro gui open --project                               # or: zeltro gui open https://...
zeltro gui settings ai --reason "add an OpenRouter key"
```

Exit codes: 0 ok, 1 error, 2 usage, 3 the app isn't available (ask in the chat instead), 4 timed out, 5 the user declined, 6 the app refused. `secret` only writes to files inside the project.

`zeltro ai` and `zeltro resume` also tell the app when each turn ends, using `zeltro gui event` as a hook for Claude Code, Codex and aider. The hook flags last one run and don't change your config files, and Codex's is skipped if you've set your own `notify`.

#### `zeltro ai-set` options

`zeltro ai-set` manages the global AI agent CLI, model, and API key used by Zeltro.

```bash
zeltro ai-set --agent claude --model opus
zeltro ai-set --agent codex --model gpt-6-sol
zeltro ai-set --agent aider --model anthropic/claude-sonnet-5 --api-key sk-ant-...
zeltro ai-set --install-only --agent qwen
zeltro ai-set --json-output
```

Supported flags:

- `--agent <name>` – Set the AI agent CLI (`codex`, `claude`, `gemini`, `qwen`, or `aider`).
- `--model <name>` – Set the model name (optional for Codex, Claude and Gemini; required for Qwen and Aider).
- `--api-key <key>` – Set the AI API key (optional for Codex and Claude; not used by Gemini, which uses Google account auth; required for Aider). `--api-key ""` clears a stored key.
- `--api-base <url>` – Set a custom API endpoint: OpenAI-compatible for Codex, Qwen and Aider; an Anthropic-compatible proxy for Claude. `--api-base none` clears it.
- `--allow-unattended` / `--no-allow-unattended` – Let the agent run without approval prompts, or turn that off. Written to the agent's own config; omit both to leave it unchanged.
- `--install-only` – With `--agent`: install that agent's CLI if missing without making it the default. Writes nothing to Zeltro's configuration.
- `--json-output` – Return the result as JSON (non-interactive). On its own, `zeltro ai-set --json-output` is a read-only probe: it installs and writes nothing, and reports the current settings plus `"session_overrides": true`, `"ai_language": true` and `"installed_agents": [...]`.

Changing `--agent` without `--model` or `--api-base` clears the old model and endpoint.

Examples:

- Inspect current AI settings:
  - `zeltro ai-set --json-output`
- Configure Codex with a model:
  - `zeltro ai-set --agent codex --model gpt-6-sol`
- Configure Claude with a model:
  - `zeltro ai-set --agent claude --model opus`
- Configure Aider against OpenAI:
  - `zeltro ai-set --agent aider --model anthropic/claude-sonnet-5 --api-key sk-ant-...`
- Configure Aider against a local Ollama server:
  - `zeltro ai-set --agent aider --model openai/llama3.1 --api-key ollama --api-base http://localhost:11434/v1`

#### Per-session AI overrides

`zeltro ai`, `resume`, `create` (including `--classify-only`), `clone`, `create-installer` and `update-installer` use the agent set by `zeltro ai-set`. To use a different one for a single run, set these environment variables. They are never written to `/etc/zeltro-cli/.env`.

| Variable | Overrides |
|---|---|
| `ZELTRO_AI_AGENT` | `AI_AGENT` — `codex`, `claude`, `gemini`, `aider` or `qwen` |
| `ZELTRO_AI_MODEL` | `AI_MODEL` |
| `ZELTRO_AI_API_BASE` | `AI_API_BASE` |
| `ZELTRO_AI_API_KEY` | `AI_API_KEY` |
| `ZELTRO_AI_API_KEY_FILE` | `AI_API_KEY`, read from the file's first line; wins over `ZELTRO_AI_API_KEY` |
| `ZELTRO_AI_LANGUAGE` | Language the agent replies in, e.g. `Spanish`. Zeltro's own output stays English |

Unset means "use the `ai-set` value"; set but empty means "clear it for this run". An unknown agent, an unreadable key file, or an override agent that isn't installed is an error before anything runs, and nothing is installed — use `zeltro ai-set --install-only --agent <name>` first.

```bash
ZELTRO_AI_AGENT=qwen ZELTRO_AI_MODEL=qwen/qwen3-coder-30b-a3b-instruct \
  ZELTRO_AI_API_BASE=https://openrouter.ai/api/v1 ZELTRO_AI_API_KEY_FILE=~/.or-key \
  zeltro ai "Add a health-check endpoint at /ping"
```

#### Aider

Aider is the one supported agent with no login of its own — it always talks
directly to a provider's API, so it needs a model **and** a key.

- The model name selects the provider: `openai/gpt-6-sol`, `anthropic/claude-sonnet-5`,
  `gemini/gemini-2.5-pro`, `deepseek/deepseek-chat`. See
  [aider's model list](https://aider.chat/docs/llms.html).
- Aider tags keys by provider (`--api-key openai=sk-...`). Zeltro stores a bare key
  and tags it from the model prefix, so `--api-key sk-...` is all you need. A key
  that already contains `=` is passed through as-is.
- `--api-base` is only needed for an OpenAI-compatible server — Ollama, LM Studio,
  OpenRouter, vLLM. Prefix the model with `openai/` when you use one. Leave it blank
  for a provider's own hosted API.
- Zeltro runs Aider with `--no-auto-commits`, so its edits land in your working tree
  like every other agent's instead of being committed for you.

### 🤖 AI-assisted project creation

`zeltro create` collects your project idea, adds Zeltro-specific instructions, and hands the combined prompt to your configured AI CLI. Zeltro sets up the environment. The AI builds the app.

```bash
# asks what you want to build (interactive terminals only)
zeltro create

# Pass the idea directly
zeltro create "A timeclock for employees in Django"
zeltro create "A customer check-in system in Laravel"
zeltro create "An inventory tracker in Express"

# Read a long idea from a file or stdin
zeltro create -f big-prompt.md
cat big-prompt.md | zeltro create

# Point to an existing GitHub repo to clone and set it up
zeltro create "https://github.com/monicahq/monica"
```

Pass `--one-off` to stop after creation and skip the AI handoff.

What the AI agent does:

1. If the framework or stack is unclear, asks which one to use before continuing.
2. Runs `zeltro new` to create the project and start its containers.
3. Reads the generated `.env` file to understand database, cache, and mail configuration.
4. Builds the app using framework-native conventions: migrations, models, seeders, routes, controllers, templates.
5. Updates the project README with the local URL, useful commands, and default credentials if any.

If your idea matches a known app that has a Zeltro installer (Grafana, Gitea, n8n, Portainer, etc.), the agent runs `zeltro install <name>` first — getting it live in seconds — then applies any additional customization from your prompt. You never have to write a docker-compose file or know which port the app listens on.

The AI CLI can be cloud-based or local depending on your configuration. Use `zeltro ai-set` to choose which agent is used.

#### Classify only (for GUIs and other front ends)

```bash
zeltro create --classify-only "<idea>"                  # human-readable
zeltro create --classify-only --json-output "<idea>"    # machine-readable
```

Runs only the classify phase: works out the stack, prints the result, exits 0,
and **creates nothing**. It never prompts, so it is safe to call from a GUI,
a script or an agent.

This exists because the normal non-interactive path (`--one-off`,
`--json-output`) silently takes the top recommendation — fine for automation,
but it throws away the choice a person would have made at the menu. A front end
that wants to present those choices natively should classify first, show the
candidates, then call `zeltro install <app>` or `zeltro new <framework> <name>`
with whatever the user picked.

The JSON carries `project_name` (`null` when the idea implies no real subject,
so ask rather than prefill), `recommended`, `customization_requested`, a
suggested `database` with a reason, and `candidates` — apps first, framework
last, capped at 5. **Apps carry a single fixed `database`** set by the installer;
**frameworks carry a `databases` array** of the engines they allow. Never offer a
database choice for an app. On failure it emits
`{"action": "classify", "status": "error", "message": "..."}` and exits non-zero.

### 🤖 AI agent sessions

Once you have set your global AI agent with `zeltro ai-set`, you can send a prompt from any Zeltro project directory:

```bash
cd /path/to/project
zeltro ai "Build a unique homepage hero section."
```

By default `zeltro ai` sends a **one-off** prompt — the agent receives it, does the work, and exits. Durable project context lives in the project's `AGENTS.md` (Zeltro writes it on creation), so each prompt can stand alone. Add `--interactive` (`-i`) if you want a persistent session instead. `--one-off` is still accepted for compatibility.

```bash
zeltro ai --interactive "Add a health-check endpoint at /ping"
```

`zeltro ai`:

- Reads `AI_AGENT`, `AI_MODEL`, `AI_API_KEY` and `AI_API_BASE` from `/etc/zeltro-cli/.env`, unless a `ZELTRO_AI_*` override is set.
- Runs the agent with the prompt (`[...]` parts are added only when set):
  - Codex: `codex exec [--model "$AI_MODEL"] "<prompt>"` (one-off) / `codex [--model ...] "<prompt>"` (interactive). Key via `OPENAI_API_KEY`; the endpoint is passed as `-c openai_base_url="…"`, because current Codex ignores `OPENAI_BASE_URL`.
  - Claude: `claude -p [--model "$AI_MODEL"] "<prompt>"` (`-p` only for one-off). Key via `ANTHROPIC_API_KEY`, endpoint via `ANTHROPIC_BASE_URL`.
  - Codex and Claude both **removed their `--api-key` flags**; the key is passed through the environment instead. Zeltro checks the key looks like it belongs to that provider (`sk-` for Codex, `sk-ant-` for Claude) and, if it does not, ignores it with a warning and lets the CLI use its own sign-in — a key for the wrong provider would otherwise replace working auth with auth that cannot work.
  - Qwen: `qwen --auth-type openai [--model "$AI_MODEL"] --prompt "<prompt>"` (one-off) / `-i "<prompt>"` (interactive). Key and endpoint via `OPENAI_API_KEY` / `OPENAI_BASE_URL`.
  - Gemini: `gemini [--model "$AI_MODEL"] --include-directories <projects dir> --output-format text --prompt "<prompt>"` (one-off) / `-i "<prompt>"` (interactive).
  - Aider: `aider --no-check-update --no-pretty --no-auto-commits --subtree-only [--no-git] [--model "$AI_MODEL"] [--api-key <provider>="$AI_API_KEY"] [--openai-api-base "$AI_API_BASE"] --message "<prompt>"` (one-off). Aider's `--message` exits after the reply, so interactive runs seed the session with `--load` instead and hand it back to you. `--no-git` is added when the directory isn't already a git repository.
- **Does not pass approval-bypass flags.** Whether an agent runs without asking is recorded in the agent's own config (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json`, `~/.aider.conf.yml`), set with `zeltro ai-set --allow-unattended` or `zeltro ai-unattended`. For throwaway containers and CI, `ZELTRO_AI_AUTO_APPROVE=1` adds the flags for that run (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo`, `--yolo --skip-trust` for Gemini, `--yes-always` for Aider).

## 🎯 Command Options

### Global Options

| Option | Description |
|--------|-------------|
| `--json-output` | Clean JSON output (suppresses all text/colors). Stripped by the dispatcher, so every command sees it |
| `--no-colors` | Disable colored output (accepted by most commands) |
| `--debug` | Enable debug logging to `/tmp/zeltro-cli-debug.log` (accepted by `new`, `clone`, `setup`, `remove`, `status`, `up`, `down`, `start-services`, `stop-services`, `configure`, `uninstall`) |

### New Project Options

`zeltro new <framework> <name>` — framework and name are **required positional arguments**. Framework is one of: `laravel`, `kavera`, `octobercms`, `drupal`, `wordpress`, `php`, `fastapi`, `flask`, `django`, `python`, `express`, `nestjs`, `fastify`, `node`, `nextjs`, `nuxt`, `sveltekit`, `astro`, `hono`, `react`, `vue`.

| Option | Description | Values |
|--------|-------------|---------|
| `--database <type>` | Database type | `auto` (default): `postgres` for django/fastapi/flask/python, `sqlite` for nextjs/nuxt/sveltekit/astro/hono/react/vue, `mysql` otherwise. Or `mysql`, `postgres`, `mongo` (alias `mongodb`), `sqlite`. An engine the framework can't use is replaced with a supported one, with a warning |
| `--version <ver>` | Framework version | **Laravel:** `latest` (default) or a `laravel/laravel` release tag, e.g. `12.9.1`<br/>**WordPress:** `latest` (default) or a WordPress version. Ignored by other frameworks |
| `--db-name <name>` | Database name | Default: project name with dashes converted to underscores |
| `--image <ref>` | Override the project's Docker image | Default: the framework's cbc base image (`canebaycomputers/cbc:nginx-php8` / `nginx-python3` / `nginx-node`) |
| `--no-migration` | Skip database migrations | Migrations run by default |
| `--github` | Create GitHub repository in user account | Requires GitHub CLI authentication |
| `--github-org <org>` | Create GitHub repository in organization | Requires GitHub CLI authentication |
| `--public` | Make the new GitHub repository public | Default is private when `--github`/`--github-org` is used |
| `--private` | Make the new GitHub repository private | Default behavior when no visibility flag is set |
| `--no-storage-symlink` | Skip creating `public/storage` symlink | (Laravel only) |
| `--one-off` | Skip the AI handoff at the end | For automation |

### Clone Project Options

`zeltro clone <mode> <repo> [name]` — **mode** is a required first argument: `work-directly` (clone and keep the original as upstream), `fork` (fork to your GitHub account), or `new-repo` (create a new GitHub repo for it).

| Option | Description |
|--------|-------------|
| `--overwrite-docker-compose` | Overwrite existing docker-compose.yaml without prompting |
| `--database <type>` | Database type (`mysql`, `postgres`, `mongo`, `sqlite`) |
| `--db-name <name>` | Database name (default: project name with dashes converted to underscores) |
| `--overwrite-env` | Regenerate `.env` even if the cloned repo already includes one (default: keep the existing `.env`) |
| `--no-migration` | Skip database migrations (they run by default — non-destructive `migrate` for adopted apps) |
| `--framework <name>` | Force framework detection (`laravel`, `kavera`, `wordpress`, `octobercms`, `drupal`, `php`, `django`, `flask`, `fastapi`, `python`, `express`, `nestjs`, `fastify`, `node`, `nextjs`, `nuxt`, `sveltekit`, `astro`, `hono`, `react`, `vue`) |
| `--image <ref>` | Override the project's Docker image (for an adapted complex compose, overrides the web-facing service's image; default: the framework's cbc base image) |
| `--no-startup` | Register and adapt project without starting the container — use this to inspect the adapted docker-compose before running `zeltro up` |
| `--fold` / `--no-fold` | Force, or skip, the AI "fold" that adapts the repo for Zeltro. Default: fold when an AI agent is configured, otherwise use the built-in framework/compose heuristics |
| `--no-preflight` | Skip the compatibility check and set up the repo regardless |
| `--branch <name>` | Check out the given branch (passed to `git clone`) |
| `--single-branch` | Clone only that branch's history (passed to `git clone`) |
| `--github-org <org>` | For `new-repo` mode: create the repository in this organization |
| `--public` | Make the new GitHub repository public (default: private) |
| `--private` | Make the new GitHub repository private |
| `--no-storage-symlink` | Skip creating `public/storage` symlink (Laravel) |
| `--one-off` | Skip the AI handoff at the end |

> **Complex projects**: When cloning a project that ships its own multi-service docker-compose (bundled database, cache, workers), Zeltro automatically adapts it: bundled DB/cache services are removed and their env vars are repointed to Zeltro's shared containers (`zeltro-postgres`, `zeltro-mariadb`, `zeltro-redis`, `zeltro-mongo`). The web-facing service gets a static VPC IP. Image type only affects this compose adaptation — framework steps (composer install, `.env` wiring, migrations) are driven by framework detection and run for adapted projects too. Pass `--no-startup` to review the adapted compose before it boots, `--overwrite-env` to repoint an existing app's `.env` connection settings at the shared services (preserving `APP_KEY`), and `--no-migration` to skip migrations.

### Setup Project Options

`zeltro setup <project> [database]` — the optional second argument is the database engine (`mysql`, `postgres`, `mongo`, `sqlite`; default `mysql`).

| Option | Description |
|--------|-------------|
| `--overwrite-docker-compose` | Overwrite existing docker-compose.yaml without prompting |
| `--framework <type>` | Force framework detection (`laravel`, `kavera`, `octobercms`, `drupal`, `wordpress`, `php`, `fastapi`, `flask`, `django`, `python`, `express`, `nestjs`, `fastify`, `node`, `nextjs`, `nuxt`, `sveltekit`, `astro`, `hono`, `react`, `vue`) |
| `--db-name <name>` | Database name (default: project name with dashes converted to underscores) |
| `--image <ref>` | Override the project's Docker image (for an adapted complex compose, overrides the web-facing service's image; default: the framework's cbc base image) |
| `--overwrite-env` | Regenerate `.env` even if one already exists (default: keep the existing `.env`) |
| `--no-migration` | Skip database migrations (they run by default) |
| `--no-startup` | Register and adapt project without starting the container |
| `--no-storage-symlink` | Skip creating `public/storage` symlink (Laravel) |

### Status Options

| Option | Description |
|--------|-------------|
| `--all` | Include stopped projects (default: running projects only) |
| `--running` | Only running projects (the default) |

A named project (`zeltro status my-project`) is shown even when stopped.

### Remove Project Options

By default project files are moved to the trash and the database and the project's Docker volumes are kept.

| Option | Description |
|--------|-------------|
| `--force-db-delete` | Also drop the project's databases, the database users its installer created, and its named volumes. Names come from the project's compose/.env files and its installer; any that another project also uses are kept |
| `--preserve-database` | Skip database deletion entirely (wins over `--force-db-delete`) |

### Uninstall Options

| Option | Description |
|--------|-------------|
| `--delete-images` | Also remove Docker images (default: keep for faster reinstall) |
| `--json-output` | Output JSON responses for automation |

### Configure Options

| Option | Description |
|--------|-------------|
| `--git-name <name>` | Git user name |
| `--git-email <email>` | Git user email |
| `--projects-dir <dir>` | Projects directory (default: existing or `~/zeltro-projects`) |
| `--vpc-subnet <A.B.C>` | Custom Docker VPC subnet (default: existing or random `10.x.x`) |
| `--non-interactive`, `-y` | Never prompt; accept defaults for anything not passed as a flag |

Re-running `zeltro configure` is safe — values from `/etc/zeltro-cli/.env` are kept as defaults, and prompts let you change them. Zeltro does not write `/etc/hosts`.

## 💡 Usage Examples

### Cloning and Setting Up Projects

```bash
# Clone a Git repository and set it up automatically
zeltro clone work-directly https://github.com/user/my-laravel-app

# Clone with a custom local name
zeltro clone work-directly https://github.com/user/company-project my-local-name

# Manual Git clone into the projects directory, then setup
cd "$(zeltro projects-dir)"
git clone https://github.com/user/company-project
zeltro setup company-project
zeltro up company-project

# Downloaded ZIP file - extract to ~/zeltro-projects/company-project/
zeltro setup company-project
zeltro up company-project

# Copied project folder
cp -r existing-project ~/zeltro-projects/new-project
zeltro setup new-project --overwrite-docker-compose
```

### WordPress Development

```bash
# Create a WordPress project (MySQL is auto-selected)
zeltro new wordpress wp-site --version latest

# Install and activate plugins
cd ~/zeltro-projects/wp-site
zeltro wp plugin install woocommerce --activate
zeltro wp plugin list --status=active
```

### JSON Output for Automation

```bash
# Get project status as JSON for scripts/GUI
zeltro status --json-output

# Create project with JSON response
zeltro new fastapi my-api --database postgres --json-output

# Check if a shared service is running (keys are container names; status is lowercase)
if [ "$(zeltro status --json-output | jq -r '.shared_services["zeltro-mariadb"].status')" = "running" ]; then
    echo "Database is ready"
fi

# Batch project operations (--all so stopped projects are included)
for project in $(zeltro status --all --json-output | jq -r '.projects[].name'); do
    zeltro up $project --json-output
done
```

#### Reading the address fields

Each project in `zeltro status --json-output` carries several address fields.
They mean different things, and one of them is easy to misuse:

| Field | Meaning |
|---|---|
| `external_port` | The published port. **The only portable field** — a port is the same number no matter where you ask from. |
| `local_url` | The address that works on the machine running Zeltro: the container's IP (`http://10.x.x.219`), or `http://localhost:<port>` where Docker keeps containers in a VM, as on macOS and Windows. |
| `lan_url` | The host's own view of itself: its LAN address and the published port. |
| `metadata` | Display metadata from the project's `x-metadata` block; `{}` when it has none. |

{: .warning }
> **`lan_url` is only meaningful from the host's own network.** It is composed
> from the address the host sees for itself, so on a cloud VM it is the private
> address — `http://172.30.2.182:226` on an EC2 box — which is unroutable from
> anywhere else. It is not a mistake in the value; the field simply cannot know
> who is asking.
>
> If you are reaching a project from another machine, **build the URL from the
> address you used to connect to that host, plus `external_port`.** Do not
> render `lan_url` to a remote user.

{: .note }
> A listening port is not the same as a reachable one. Zeltro reports what the
> host can see about itself; whether your packets arrive is a property of the
> network between you and it — security groups, NAT, VPNs, or simply whether a
> laptop is awake. That question can only be answered from the machine doing the
> asking, so probe from there rather than inferring reachability from status
> output.

### Service Management

```bash

# Check Redis status and flush cache
zeltro redis ping
zeltro redis-flush

# Monitor supervised processes (from the project directory)
zeltro supervisor-status
zeltro supervisor restart all
```

### Advanced Usage

#### Containerized Development Commands

**PHP projects** — `zeltro composer`, `zeltro art`, `zeltro php`, `zeltro wp` and `zeltro drush` run inside your project's container with the correct PHP environment:

```bash
cd ~/zeltro-projects/my-laravel-app
zeltro composer install        # Uses container's PHP 8.3
zeltro art migrate             # Runs with container's Laravel setup
zeltro php script.php          # Executes with project's PHP configuration
```

**Node.js projects** — `zeltro npm`, `zeltro npx`, and `zeltro node` run inside your project's container with Node 22:

```bash
cd ~/zeltro-projects/my-express-app
zeltro npm install             # Installs packages inside container
zeltro npx tsc --init         # Run any npx command inside container
zeltro node script.js         # Execute a script with project's Node environment
```

**Python projects** (FastAPI, Django, plain Python) — `zeltro python` and `zeltro pip` run inside your project's container:

```bash
cd ~/zeltro-projects/my-fastapi-app
zeltro python -c "import sys; print(sys.version)"
zeltro pip install httpx              # Install a package inside the container
zeltro pip list                       # Show installed packages
```

**Django projects** — use the `zeltro django` wrappers for manage.py operations:

```bash
cd ~/zeltro-projects/my-django-app
zeltro django manage migrate          # Run migrations
zeltro django manage createsuperuser  # Create admin user
zeltro django manage collectstatic    # Collect static files
zeltro django manage makemigrations myapp
```

#### Interactive Shells & REPLs

`zeltro shell` opens the right interactive environment for the current project automatically:

```bash
# Laravel — opens php artisan tinker
cd ~/zeltro-projects/my-laravel-app && zeltro shell

# Django — opens python manage.py shell (Django ORM and apps loaded)
cd ~/zeltro-projects/my-django-app && zeltro shell

# FastAPI / plain Python / Python script — opens python3 REPL
cd ~/zeltro-projects/my-fastapi-app && zeltro shell

# Express / Fastify / plain Node.js — opens node REPL
cd ~/zeltro-projects/my-express-app && zeltro shell

# NestJS — opens node REPL; or the NestJS REPL if src/repl.ts exists
cd ~/zeltro-projects/my-nest-app && zeltro shell
```

Anything it can't detect gets a bash shell. `zeltro tinker` remains available as the explicit Laravel-only alias.

The NestJS REPL (`src/repl.ts`) is not scaffolded by default. Create it per the [NestJS REPL docs](https://docs.nestjs.com/recipes/repl), then `zeltro shell` will use it automatically.


## 🔌 JSON API Integration

Zeltro provides clean JSON output for programmatic integration, perfect for GUI applications and automation scripts:

```javascript
// Example: Create project via JSON API
const result = await exec('zeltro new laravel myapp --version 12.9.1 --json-output');
const data = JSON.parse(result.stdout);

// Result:
{
  "action": "new_project",
  "project_name": "myapp",
  "framework": "laravel",
  "database": "mysql",
  "setup_result": { ... },
  "status": "success"
}
```

### Available JSON Commands

✅ **JSON Support Available:**
- `zeltro status --json-output` - Project and service status
- `zeltro new --json-output` - Project creation confirmation
- `zeltro clone --json-output` - Project clone confirmation
- `zeltro setup --json-output` - Project setup confirmation
- `zeltro remove --json-output` - Project removal confirmation
- `zeltro up --json-output` - Project startup confirmation
- `zeltro down --json-output` - Project shutdown confirmation
- `zeltro start-services --json-output` - Service start confirmation
- `zeltro stop-services --json-output` - Service stop confirmation
- `zeltro enable-service` / `disable-service --json-output` - Service toggle result (no name: list optional services)
- `zeltro configure --json-output` - Configuration confirmation
- `zeltro uninstall --json-output` - Uninstall confirmation
- `zeltro ai-set --json-output` - Current AI settings (read-only when used alone)
- `zeltro create --classify-only --json-output` - Stack classification
- `zeltro peers --json-output` / `zeltro send --json-output` - Agent sessions / send result
- `zeltro get-metadata --json-output` - All x-metadata keys, including the full `idea` (`status` only reports `has_idea`)
- `zeltro set-metadata`, `zeltro disable`, `zeltro enable --json-output` - Result
- `zeltro projects-dir --json-output`, `zeltro version --json-output`

❌ **No JSON Support (Container Commands):**
- `zeltro composer` - Runs inside container
- `zeltro art` - Runs inside container
- `zeltro wp` - Runs inside container
- `zeltro drush` - Runs inside container
- `zeltro php` - Runs inside container
- `zeltro npm` - Runs inside container
- `zeltro npx` - Runs inside container
- `zeltro node` - Runs inside container
- `zeltro python` - Runs inside container
- `zeltro pip` - Runs inside container
- `zeltro shell` - Runs inside container
- `zeltro django` - Runs inside container
- `zeltro exec` - Runs inside container
- `zeltro exec-root` - Runs inside container
- `zeltro supervisor` - Runs inside container
- `zeltro redis` - Direct service connection
- `zeltro memcache` - Direct service connection

## 🏗️ Architecture

### Services Included

Always running:

- **Redis** (`zeltro-redis`) - Caching and session storage
- **Memcached** (`zeltro-memcached`) - Additional caching layer
- **MailHog** (`zeltro-mailhog`) - Email testing and debugging (captures outbound emails)

Optional — enabled automatically when a project needs one, or with `zeltro enable-service`:

- **MariaDB** (`zeltro-mariadb`), **PostgreSQL** (`zeltro-postgres`), **MongoDB** (`zeltro-mongo`)
- **phpMyAdmin**, **Adminer**, **mongo-express**, **RedisInsight** - Database admin UIs
- **MinIO** (S3-compatible storage, served by Silo, the maintained MinIO fork), **Meilisearch** (full-text search)

### Project Structure

```
~/zeltro-projects/
├── project1/
│   ├── docker-compose.yaml
│   ├── .env
│   └── [project files]
├── project2/
└── ...
```

### Network Configuration

Each project gets:
- Unique Docker IP address (10.x.x.x) on the `zeltro-cli_vpc` network
- A name that resolves on the shared network, from inside any container
- Mapped external port for LAN access
- Local URL: the container IP, e.g. `http://10.247.177.219`
- LAN URL: `http://your-ip:port`


## Uninstallation


### Platform-Specific Uninstall

#### 🐧 Linux and 🍎 macOS
```bash
# 1. Remove Zeltro's containers, volumes and networks, and the CLI itself
#    (/usr/local/bin/zeltro and /usr/local/share/zeltro-cli)
zeltro uninstall

# 2. Remove configuration directory (optional)
sudo rm -rf /etc/zeltro-cli
```

If you installed the `.deb` package, run `zeltro uninstall` and then `sudo apt remove zeltro-cli`.

### What Gets Removed

**`zeltro uninstall` removes:**
- ✅ All Zeltro service containers (mariadb, redis, postgres, etc.)
- ✅ All individual project containers
- ✅ Docker images (optional with `--delete-images`)
- ✅ Docker volumes and networks with the `zeltro-cli_` prefix — including the shared database data
- ✅ The Zeltro CLI binary and source files
- ✅ Backs up project docker-compose.yaml files as `docker-compose.yaml.backup`

**What's preserved:**
- ✅ Your project source code and files
- ✅ `/etc/zeltro-cli` configuration (a reinstall picks it up)
- ✅ Other non-Zeltro Docker containers and images
- ✅ Docker Desktop/Engine itself

See [Uninstall Options](#uninstall-options) for flags.

## 🔧 Configuration

### Initial Setup

```bash
# Run the configuration wizard
zeltro configure
```

`zeltro configure` also installs **bash tab-completion** (to `/usr/share/bash-completion/completions/zeltro` and `/etc/bash_completion.d/zeltro`, whichever exist). Open a new shell and tab through commands, project names, and installer names:

```
zeltro ins<TAB>            → install
zeltro install gr<TAB>     → grafana  gramps-web  graylog  grist  grocy
zeltro up <TAB>            → (your project names)
zeltro new <TAB>           → laravel  wordpress  fastapi  django  ...
zeltro clone <TAB>         → work-directly  fork  new-repo
```

### Environment Variables

- `JSON_OUTPUT=1` - Same as `--json-output`
- `NO_COLOR=1` - Same as `--no-colors`
- `DEBUG_LOG_PATH` - Where `--debug` writes (default `/tmp/zeltro-cli-debug.log`)
- `ZELTRO_AI_AGENT`, `ZELTRO_AI_MODEL`, `ZELTRO_AI_API_BASE`, `ZELTRO_AI_API_KEY`, `ZELTRO_AI_API_KEY_FILE`, `ZELTRO_AI_LANGUAGE` - per-session AI overrides (see "Per-session AI overrides" under [System Management](#system-management))
- `ZELTRO_AI_AUTO_APPROVE=1` - Pass each agent's approval-bypass flags for this run
- `ZELTRO_BUS_DIR` - Agent message spool (default `~/.zeltro/bus`)

The projects directory is not an environment variable: it is `PROJECTS_DIR` in `/etc/zeltro-cli/.env`, set with `zeltro configure --projects-dir`.

## 📝 Important Notes

- **Directory Requirements**: Project tools (`composer`, `art`, `wp`, `drush`, `php`, `npm`, `npx`, `node`, `python`, `pip`, `shell`, `django`, `exec`, `db-refresh`, `cache-refresh`, `supervisor`) and `ai` / `send` must be run from within a project directory
- **JSON Output**: Use `--json-output` for programmatic integration (GUI, scripts, automation)
- **Non-Interactive Mode**: Commands take explicit arguments and never show pickers. `configure` and `create` prompt only at a terminal; use `configure --non-interactive` or `create --one-off` in scripts
- **Database Creation**: Databases are automatically created and configured for each project, and the engine's shared service is enabled if it isn't already
- **Addressing**: Each project is assigned a container IP and a published port; nothing is written to `/etc/hosts`

## 🚦 Getting Help

```bash
# Show comprehensive help
zeltro help

# Show command-specific help
zeltro new --help
zeltro remove --help
```

## 🔍 Troubleshooting

### Common Issues

1. **Services not starting**: Check Docker is running and ports are available
2. **Permission errors**: Ensure user is in `docker` group
3. **Database connection**: Verify database service is running with `zeltro status`, and enable it with `zeltro enable-service <mysql|postgres|mongo>` if it isn't
4. **Port conflicts**: Each project gets a unique port automatically assigned

### Debug Commands

```bash
# Check service status
zeltro status

# View container logs
docker logs [container-name]

# Check that a shared service resolves from inside the project container
zeltro exec "getent hosts zeltro-redis"

# Enable debug logging
zeltro new laravel my-project --debug
zeltro setup my-project --debug
zeltro configure --debug

# View debug log
cat /tmp/zeltro-cli-debug.log
```

### Debug Mode

The main project and service commands accept a `--debug` flag (see [Global Options](#global-options)) that writes detailed logs to help troubleshoot issues:

- **Log Location**: `/tmp/zeltro-cli-debug.log`
- **Session Tracking**: Each new command creates a fresh debug session
- **Detailed Output**: Shows script flow, function calls, and exit codes
- **Cross-Script Tracking**: Debug flag is passed between scripts automatically

**Example:**
```bash
# Debug a project creation issue
zeltro new laravel test-project --debug

# Check what happened
tail -f /tmp/zeltro-cli-debug.log
```

---

See [Automation & JSON](../automation/) for which commands support JSON and how to script against them.
