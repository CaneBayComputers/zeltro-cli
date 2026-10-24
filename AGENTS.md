# AGENTS.md

> Reference for agents *using* Zeltro to install, build, or deploy projects on this machine.
> If you're modifying Zeltro's source itself, see [DEVELOPMENT.md](DEVELOPMENT.md).

This is the boiled-down version of `README.md` — same facts, no marketing, optimized for fast agent context loading. Read this and run `zeltro --help` and you have everything you need to use Zeltro effectively.

---

## Design Context: What Zeltro Optimizes For

Zeltro is infrastructure for **multi-project local dev** and **AI-driven workflows**, not a single-app framework. Lean into these properties when working with it:

- **Shared services over bundled.** One `zeltro-postgres` / `zeltro-mariadb` / `zeltro-redis` / `zeltro-mongo` / `zeltro-memcached` serves N projects instead of N projects each spinning up their own. Cuts RAM from ~700MB of redundant DB containers down to ~100MB and eliminates port collisions.
- **Names inside the network, addresses outside it.** Docker's embedded DNS resolves `zeltro-postgres`/`zeltro-redis`/sibling-project names from inside containers. The host is not on that network, so browsers and host tools use the address `zeltro status <project>` prints. Zeltro does **not** write `/etc/hosts`.
- **Stable platform for AI agents.** Each "yo install <app>" session that has to rediscover networking, ports, secret generation, and shared services from scratch burns tokens reinventing what Zeltro already encodes. Reach for `zeltro install <app>` first; only hand-roll a compose if no installer exists.

**Where Zeltro does not add value**: single-project devs. Upstream `docker compose up` works fine for them.

---

## Commands You'll Use Most

| Command | Purpose |
|---|---|
| `zeltro install <app> [name]` | Install a curated OSS app (`--list` to see all). Always check this first before hand-rolling anything. Optional `name` sets the project dir/hostname (defaults to the app slug). Override the image with `--image <ref>`. |
| `zeltro new <framework> <name>` | Greenfield project. Framework + name are required positionals (`laravel`, `kavera`, `octobercms`, `drupal`, `wordpress`, `php`, `fastapi`, `flask`, `django`, `python`, `express`, `nestjs`, `fastify`, `node`, `nextjs`, `nuxt`, `sveltekit`, `astro`, `hono`, `react`, `vue`). DB auto-selected per framework; override with `--database` (`mysql`, `postgres`, `mongo`, `sqlite`); version via `--version`. |
| `zeltro clone <mode> <repo> [name]` | Clone a Git repo and adapt its compose to use Zeltro shared services. Mode (required, git-remote style): `work-directly` (keep original as upstream), `fork`, or `new-repo`. |
| `zeltro up <name>` / `zeltro up-all` | Start one project, or every project. Shared services always start. |
| `zeltro down <name>` / `zeltro down-all` | Stop one project, or every project. Shared services keep running — use `zeltro stop-services` for those. |
| `zeltro setup <name>` | Adapt a project directory in `~/zeltro-projects/`. |
| `zeltro remove <name>` | Tear down a project. DB is **preserved** by default — pass `--force-db-delete` to drop its databases, the database users its installer created, and its volumes (anything another project also uses is kept). |
| `zeltro rename <name> <new-name>` | Rename a project: its folder, container, volumes and Claude Code history follow. `--github` renames the GitHub repo too. See "Renaming a project" below. |
| `zeltro status [name] [--all]` | Show running state. Lists only active (running) projects by default; `--all` includes stopped projects. |
| `zeltro exec <cmd>` | Run a command inside the project container, no TTY (automation-friendly). Run from the project directory. |
| `zeltro uninstall` | Remove every Zeltro service and project container, Zeltro's networks and the CLI. Never prompts. Keeps images, the `zeltro-cli_*` data volumes, `/etc/zeltro-cli`, the app's settings and the projects folder (never edited). `--delete-images` and `--delete-data` (all shared databases) remove those too; `--purge` removes everything Zeltro put on the machine except the projects folder: both of those, the Zeltro app (its package or `/Applications/Zeltro.app`), the CLI's package, `/etc/zeltro-cli`, the apt/dnf repository, key and cached lists, bash completion, `~/.zeltro`, `~/.cache/zeltro`, the app's settings and its update downloads; Docker, Node and git stay. Only images Zeltro used are removed (never a prune); one a non-Zeltro container uses is kept and reported. Anything it couldn't remove (e.g. a network another container still uses) is listed, with exit 1. |

**No interactive prompts.** Every command fails with a clear "required argument" error rather than prompting — so nothing ever blocks an agent. Always pass explicit arguments. (`zeltro create` prompts a human only at a terminal; under `--one-off`, `--json-output` or a non-TTY stdin it takes the top recommendation instead. `zeltro configure` prompts unless you pass `--non-interactive` (`-y`), so an agent must always pass it.)

`zeltro create`, `zeltro new`, `zeltro clone`, and `zeltro install` write an `AGENTS.md` handoff file into the new project, then `cd` into it and send the AI agent a one-off prompt telling it to read that file. Pass `--one-off` (or run with `--json-output` / non-TTY / no AI agent configured) to skip the agent session; the `AGENTS.md` is still written, for an agent started later (the GUI does this). Its Zeltro block goes first and overrides a framework's own advice to install PHP, Node and the like on the host.

`zeltro ai "<prompt>"` is a one-off prompt by default — durable project context lives in the project's `AGENTS.md`, not in a long-lived session. Pass `--interactive` for a persistent session. `zeltro ai` (run inside a project) and `zeltro resume` refresh that context before the agent starts (`ZELTRO.md` instead in a repo that tracks its own `AGENTS.md`), and tell agents that don't read `AGENTS.md` themselves to read it first: Claude Code and Qwen through `--append-system-prompt`, aider through `--read`, Codex/OpenCode/Hermes only when it's `ZELTRO.md`, Gemini and agy on the prompt (`zeltro ai` only). The file is rewritten only when its Zeltro block changes.

**Always go through `zeltro exec`, never a raw `docker exec -u developer …`.** The image's `developer` user is uid 1001 but the bind-mounted project files belong to the host user (usually 1000), so a raw exec fails with errors like `./composer.json is not writable`. The CLI passes `--user "$(id -u):$(id -g)"` for you.

For automation, prefer `zeltro exec` / `zeltro exec-root` over interactive variants (`zeltro bash`, `zeltro tinker`, `zeltro exec-tty*`) — those allocate a TTY and aren't agent-friendly. `zeltro exec` accepts either separate arguments (`zeltro exec python3 manage.py migrate`) or a single quoted string (`zeltro exec "python3 manage.py migrate"`).

**Never pass `--json-output`.** It suppresses all human-readable output including the success/failure distinction, so you can't tell whether a command worked. It exists only for external scripts/GUIs. Always run commands plain and read the text output.

**Always pass explicit arguments.** There are no interactive prompts or pickers — a missing required argument is a hard error with a usage hint, never a prompt. Use `zeltro up-all` / `zeltro down-all` to act on every project.

For Django: prefer `zeltro django manage <args>` over `zeltro exec python3 manage.py <args>`. Python containers provide `python3`, not `python` — never `zeltro exec python …`.

To restart processes inside a running container use `zeltro supervisor restart all` (run from the project directory). Never use `zeltro exec supervisorctl …` — that runs as the developer user and gets permission denied on the supervisor socket.

Never pass `--json-output` to `zeltro new` from an automation context — it suppresses all output, so success and errors both look identical.

### Per-session AI overrides

`zeltro ai`, `resume`, `create` (including `--classify-only`), `clone`, `create-installer` and `update-installer` use the agent set by `zeltro ai-set`. To use a different one for a single run without changing that default, set these in the environment. They are never written to `/etc/zeltro-cli/.env`.

| Variable | Overrides |
|---|---|
| `ZELTRO_AI_AGENT` | `AI_AGENT` — `codex`, `claude`, `agy`, `aider`, `qwen`, `opencode`, `hermes` or `gemini` (deprecated) |
| `ZELTRO_AI_MODEL` | `AI_MODEL` |
| `ZELTRO_AI_API_BASE` | `AI_API_BASE` |
| `ZELTRO_AI_API_KEY` | `AI_API_KEY` |
| `ZELTRO_AI_API_KEY_FILE` | `AI_API_KEY`, read from the file's first line. Wins over `ZELTRO_AI_API_KEY` when non-empty. Keep the file until the session ends: nested `zeltro` calls re-read it. |
| `ZELTRO_AI_LANGUAGE` | *(no .env setting)* A plain-English language name, e.g. `Spanish` or `Simplified Chinese`. The agent is told to reply to the user in it and keep code, commands and identifiers as they are, and `create --classify-only` writes its `reason` text in it. Zeltro's own output stays English. How it reaches each agent: claude and qwen `--append-system-prompt`; codex `-c developer_instructions=…`; aider `--chat-language`. All of these also apply to `zeltro resume`. gemini, opencode and agy have no way to add to their system prompt, so `zeltro ai` puts the instruction at the top of the prompt, and a resumed session of theirs gets none. |

Unset means "use the `ai-set` value"; set but empty means "clear it for this run". An unknown agent name, an unreadable key file, or an override agent that isn't installed fails with a non-zero exit before anything runs, and nothing is installed. `zeltro ai-set --install-only --agent <name>` installs an agent without making it the default. `zeltro ai-set --json-output` never prompts or installs, and reports `"session_overrides": true`, `"ai_language": true` and `"installed_agents": [...]`.

**Default agent when none is set.** A fresh install leaves `AI_AGENT` blank. Then every command uses the first installed agent in the order claude, codex, agy, qwen, aider, opencode, hermes, gemini. `zeltro configure` and `zeltro ai-set` save that choice. `ai-set --json-output` saves it only if it can without a password prompt, and reports `"agent_auto": true` when it picked the agent this way. An agent counts as installed when its binary is on `PATH`. Zeltro adds the usual per-user bin directories (`~/.local/bin`, the npm global prefix's `bin`, `~/.npm-global/bin`, `~/.bun/bin`, `~/.opencode/bin`, the nvm default Node's `bin`, from `$NVM_DIR` or `~/.nvm`) when they aren't already on `PATH`, so a non-login ssh shell finds the same agents a login shell does. Inside WSL, Windows' `PATH` entries (`/mnt/c/...`) are moved after all of these, and a binary under `/mnt/<drive>/` never counts as an installed agent, or as the npm to install with.

### Agent sign-in, install and profiles

An AI profile runs its agent one of three ways: its **subscription** sign-in, the provider's own **API key** (`ZELTRO_AI_API_KEY`), or a **custom endpoint** (`ZELTRO_AI_API_BASE` + key + model). Which agent supports which, and the format its endpoint must speak, is in `zeltro ai-set --json-output` under `agent_auth`: `{"agents": {"<agent>": {"subscription", "api_key", "endpoint"}}, "login_supported": [...]}`. The endpoint formats:
- `openai`: chat completions (qwen, aider, opencode, hermes);
- `openai-responses`: OpenAI's Responses API (codex). Codex 0.128 dropped chat completions. OpenRouter, Ollama and LM Studio offer Responses; anything else needs a gateway such as LiteLLM;
- `anthropic`: the Messages API (claude). OpenRouter's `https://openrouter.ai/api`, DeepSeek, Kimi, GLM and LiteLLM offer it;
- `gemini` (gemini).

agy has no endpoint (`null`): it takes a Gemini API key or its own Google sign-in.

Subscription sign-in: claude, codex, opencode (ChatGPT only; a Claude Pro/Max sign-in must never be used outside Claude Code itself), hermes and agy (a Google account, signed in inside `agy` itself; `ai-login` doesn't run it). Gemini CLI, Qwen Code and aider take keys only.

**Gemini CLI is deprecated.** Google stopped serving it to personal accounts (free, AI Pro, AI Ultra) on 2026-06-18; only paid Gemini API keys and Code Assist licences still work. Its replacement is the **Antigravity CLI (`agy`)**. A configured `gemini` keeps working, but it comes last in the default order, `ai-set` prints a note when it's chosen, and `agent_auth.agents.gemini` carries `"deprecated"` (the reason) and `"replaced_by": "agy"`. The app should offer `agy` instead.

How a profile reaches each agent:
- **claude.** With an endpoint: `ANTHROPIC_BASE_URL`, with the key as `ANTHROPIC_AUTH_TOKEN` and the model also as `ANTHROPIC_MODEL` and the background (Haiku) model. Without one: `ANTHROPIC_API_KEY` (`sk-ant-` keys only).
- **codex.** With an endpoint: a model provider of its own, passed with `-c` (`model_providers.zeltro`, `wire_api = "responses"`, key in `ZELTRO_CODEX_ENDPOINT_KEY`), so `~/.codex/config.toml` is never written. With only a key: the managed `CODEX_HOME` below.
- **qwen.** `OPENAI_API_KEY` / `OPENAI_BASE_URL`.
- **gemini.** `GEMINI_API_KEY` / `GOOGLE_GEMINI_BASE_URL`.
- **agy.** `GEMINI_API_KEY`, which agy 1.4.6 only uses with `"modelProvider": "gemini"` in `~/.gemini/antigravity-cli/settings.json`. Zeltro sets that while a run has a key and removes it again (only if Zeltro set it) once runs have none, so a Google sign-in works. A custom endpoint is refused. Installed with Google's script into `~/.local/bin/agy`; it updates itself.
- **aider.** `--openai-api-base`, with the model as `openai/<model>` (except `ollama/` and `ollama_chat/` routes) and the key as `openai=<key>`.
- **opencode, hermes.** See their notes in `functions.sh`.

**First-run screens are pre-answered** (`scripts/agent_firstrun.py`, run before every session, after `ai-install` and after `ai-login`), so the app's first session goes straight to work. Each answer goes where the agent itself stores it, only when the user hasn't answered, and an unparseable file is never touched:
- **claude:** `hasCompletedOnboarding` (+ `lastOnboardingVersion`) in `~/.claude.json` (`$CLAUDE_CONFIG_DIR/.claude.json` when set), only once it's signed in or runs on a key, since the wizard is how a subscription user signs in. A profile's `ANTHROPIC_API_KEY` is pre-approved (its last 20 characters in `customApiKeyResponses.approved`) unless the user rejected it. Unattended mode also writes `skipDangerousModePermissionPrompt` (settings) and `hasSeenAutoDefaultNudge` (global): without them Claude Code 2.1 shows the "Bypass Permissions mode" disclaimer, ignores bypass in background runs, and offers "Make auto mode your default?". `ai-unattended` reads Claude as on only with that consent recorded.
- **codex:** `check_for_update_on_startup = false` ("Update available! … Update now").
- **gemini:** `security.auth.selectedType = "gemini-api-key"` ("How would you like to authenticate?").
- **aider:** `gitignore`, `show-release-notes`, `show-model-warnings`, `check-update` off and `analytics-disable` in `~/.aider.conf.yml`; `.aider*` goes in the project's `.git/info/exclude` instead.
- **hermes:** `telemetry.shared_metrics.offer_version: 2` through `hermes config set` ("Help improve Hermes?"; sharing stays off, its default). Hermes is only started when its `config.yaml` exists and lacks the marker.
- **qwen, opencode:** nothing blocks when Zeltro passes the key.
- **agy:** nothing is pre-answered. Its first interactive start asks for a color scheme, then shows "Terms of Service & Data Use" with Google's data-sharing box ticked by default. That's the user's consent to give, so the screen is left to them. Headless runs (`-p`, used by `create`) skip it.
- **Folder trust** ("Is this a project you created or one you trust?", "Do you trust the files in this folder?", Codex's "Trust this folder?") is answered for projects Zeltro itself creates (`new`, `install`, `create`): Claude's `projects[DIR].hasTrustDialogAccepted`, Gemini's `trustedFolders.json`, agy's `trustedWorkspaces` and Codex's `trust_level = "trusted"`. A clone keeps the question, since a cloned repo can carry hooks and MCP servers.
- `ZELTRO_NO_AGENT_FIRSTRUN=1` skips all of it.

The commands:
- **`zeltro ai-status --agent <a> --json-output`** (or `--json`). Local and fast. Gives `{"installed", "version", "auth", "signed_in", "account", "subscription", "api_key", "endpoint", "login_supported", "unattended"}`. `unattended` is `"true"`, `"false"` or `"unknown"`, read from the agent's own config as `ai-set` and `ai-unattended` read it.
  - `auth` is `subscription`, `api_key`, `endpoint`, `none`, or `unknown` (a key-only agent with no key).
  - A run's own key or endpoint (`ZELTRO_AI_*`, else the `.env`) counts as signed in for that agent.
  - Claude uses `claude auth status`, Codex `codex login status`, OpenCode its `auth.json`, Hermes `hermes auth status`. These see stored credentials, not whether the server still accepts them.
- **`zeltro ai-install --agent <a> [--json-output]`** is the same as `ai-set --install-only`. It never prompts. npm-installed agents go to npm's global folder when writable, else through passwordless sudo (npm by absolute path, with Zeltro's `PATH`), else into `~/.npm-global`. Only a Linux npm is used. With none for this user (Zeltro installed by someone else, or WSL showing only Windows' npm), it first installs Node LTS for the user through nvm, as the installers do (no sudo; `$NVM_DIR` or `~/.nvm`), and fails with a message only if that fails too.
- **`zeltro ai-unattended --agent <a> on|off|status [--json-output]`** turns the agent's own approval setting on or off (in its own config file: Claude's `permissions.defaultMode`, Codex's `approval_policy`, and so on; `--help` lists each file) and changes nothing else: not the `.env`, not the default agent, and it never installs. It reads the setting back afterwards. JSON: `{"action": "ai_unattended", "status": "success", "agent", "unattended": "true"|"false"|"unknown", "config_file"}`. Errors carry `"error"`: `not_installed` (install first with `ai-install`), `unknown_agent`, `no_agent`, `write_failed` or `not_applied` (the setting doesn't read as asked after the write). `status` works for an agent that isn't installed. It doesn't need Docker. The older form `ai-unattended <a> [--revoke|--status]` still works.
- **`zeltro ai-login --agent <a> --json-output [--local-browser] [--force]`** runs the agent's sign-in, printing JSON lines:
  - `{"event":"open","url","code"?}`: show the link. A `code` means a device-code flow (codex): the user types it on that page.
  - `{"event":"need_code","retry"?,"message"?}`: write the code the sign-in page shows, plus a newline, to stdin. `retry` means the last one was rejected.
  - `{"event":"done","signed_in":true,"account","auth","already"?}` or `{"event":"error","message"}`.

  Notes on `ai-login`:
  - Claude uses the paste flow by default, which works wherever the browser is. `--local-browser` gives the link that redirects to the waiting process on `localhost` instead: no code to paste, but the browser has to be on the same machine.
  - It's already signed in with a subscription: `done` at once with `"already": true`, unless `--force`.
  - Killing the process ends the sign-in it started.
  - Supported for claude and codex. Others give `{"event":"error","message":"not supported yet"}`.

### Classify and create errors

When `create --classify-only --json-output` (or `create --json-output`) fails, it gives `{"action":"classify"|"create","status":"error","error":<code>,"message"}`. The codes:

- **`agent_failed`**: the AI agent itself failed, for example a wrong key, a model the account can't use, no credit left, or not signed in. `message` is the agent's own last error line, prefixed with its name, e.g. `Codex: unexpected status 401 Unauthorized: Incorrect API key provided: ...`. A run that shows a 400, 401, 403 or 404 is stopped at once rather than after the agent's own retries. It is not retried.
- **`no_stack`**: the agent answered, but not with a usable recommendation. Retried once.
- **`ai_not_signed_in`**: claude or codex has no key or endpoint in the profile and isn't signed in on this machine. This is checked before the agent runs, and also reported when it fails with a 401. The message names the agent and host and suggests `zeltro ai-login --agent <a>`. The JSON also carries `"agent"`.

**Codex with an API key (no endpoint):** Codex ignores `OPENAI_API_KEY`, so Zeltro signs it in with `codex login --with-api-key` in a managed `CODEX_HOME`, `~/.zeltro/codex/<hash of the key>`. That home is stable per key, so `codex resume --last` finds the profile's earlier sessions. The user's `config.toml` and `AGENTS.md` are symlinked into it, and the user's own `~/.codex` (and any ChatGPT sign-in in it) is never written to. This applies to `ai`, `resume`, `create`, `create-installer` and `update-installer`.

### Folder projects

A folder project is a folder plus an AI session: no container, framework, database or address. Use it for scripts, scrapers, documents, data clean-ups, CLI tools and bots. AI sessions, the saved idea, profiles and overrides, the agent bus and `zeltro gui` all work as they do for other projects.

- **Create.** `zeltro new folder <name> [--one-off] [--json-output]` makes `<projects>/<name>` with an `AGENTS.md`, a `.gitignore` (for `.env`) and a git repo, then hands off to the agent unless `--one-off`.
  - JSON: `{"action":"new_project","project_name","kind":"folder","origin":"created","path","status":"success"}`.
  - The name is cleaned like `zeltro new`: lowercase, spaces become dashes, only `[a-z0-9-_]` kept.
  - Errors: `{"status":"error","error":<code>,"message"}` with code `missing_name`, `bad_name` or `name_taken`.
- **Add.** `zeltro add <path> [--name N] [--json-output]` uses a folder that already exists on that host, without moving or copying it. The project is a symlink, `<projects>/<name>`, pointing at the folder.
  - Nothing is written inside the folder, not even an `AGENTS.md`.
  - The name defaults to the folder's name, with `-2`, `-3`... added if it's taken. An explicit `--name` that's taken is an error instead.
  - JSON: `{"action":"add_folder","project_name","kind":"folder","origin":"added","path":<real path>,"status":"success"}`.
  - Errors: `missing_path`, `not_found`, `not_a_folder`, `path_not_allowed` (`/`, home, system folders, or a folder that contains the projects folder), `inside_projects_dir` (also gives `project_name`), `already_added` (gives `project_name`), `name_taken`, `registry_failed`.
- **Record.** What makes a project a folder project is its record in `<projects>/.zeltro/folders/<name>.json`. The record holds `origin` (`created` or `added`), the real `path`, and the metadata. Everything without a record is a Docker project.
- **Status.** `zeltro status --all --json-output` gives every project a `kind` field: `"folder"` or `"docker"`.
  - A folder project's entry is fixed apart from `name`, `origin` (`created` or `added`), `path`, `missing` and `metadata`. The rest is always: `folder_exists` (= not missing), `docker_running:false`, `port_mapped:false`, `external_port/project_ip/resolved_ip/local_url/lan_url:null`, `ping_status/http_status:"not_applicable"`.
  - `missing:true` means an added folder has been moved or deleted. It's still listed, and `zeltro remove` forgets it.
  - Folder projects never count as running, so plain `zeltro status` (running only) leaves them out; use `--all`.
- **Metadata.** `set-metadata` and `get-metadata` work the same as for other projects (emoji, name, description, idea, `--idea`), stored in the record. `last_on` is updated on `resume`.
- **Skipped.** `up`, `down`, `enable` and `disable` exit 0 with `{"status":"skipped","reason":"folder_project","kind":"folder",...}`. `up-all`, `down-all` and `uninstall` pass over folder projects. `setup` refuses one.
- **Remove.** `zeltro remove <name> --json-output` gives `{"action":"remove_project","project_name","kind":"folder","origin","files_deleted":bool,"trashed":bool,"database_deleted":false,"status":"success"}`.
  - An **added** folder is only forgotten: the symlink and record go, and `files_deleted` is always `false`.
  - A folder Zeltro **created** goes to the trash like any project directory. If trash-cli is missing, the folder is left in place with error `trash_unavailable` and nothing changes.
  - Docker projects' remove JSON now carries `"kind":"docker"`.
- **AI sessions.** `ai`, `ai --interactive` and `resume` run the agent in the folder, which for an added folder is the real path. No container is started and no address is shown. The agent bus maps a working directory inside an added folder back to its project, so `zeltro gui ...` works there.
- **Create with AI.** `create --classify-only --json-output` can return a candidate `{"kind":"folder","slug":"folder","display":"Just a folder","reason"}` with no database field, and `"recommended":"folder"`.
  - The folder candidate is first when it's recommended, otherwise last.
  - It appears only when the idea isn't something served on the web.
  - Choosing it creates the folder project, saves the idea, and opens the agent seeded with a folder-specific build prompt. The JSON result has `"kind":"folder"`.
- **Remote hosts.** Everything above works over SSH and WSL like any other command; for `add`, the path is on that host.

### Renaming a project

`zeltro rename <project> <new-name> [--github] [--dry-run] [--force] [--json-output]`. The new name is cleaned like `zeltro new` does (`"My App"` -> `my-app`), and `project_name` in the result is the name it got.

- **Docker project.** The folder moves, and the web service's `container_name` (the one equal to the project name, which `x-metadata` hangs off) changes; other `container_name`s are the app's own and stay. Named volumes (`<old>_<volume>`, found by their compose labels) are copied to `<new>_<volume>`, verified file by file, and the old ones removed. Locally built images (`<old>-<service>`) are retagged, so nothing rebuilds. A running project is stopped first and started again; the IP, port, database, `.env` and disabled state don't change.
- **Folder project.** Created: the folder moves, and its record and AGENTS.md follow. Added: only the link and the record are renamed; the user's folder isn't touched.
- **AI history.** Claude Code's conversations for the folder (`~/.claude/projects/<encoded path>`) and its `~/.claude.json` entry move to the new path, so `zeltro resume` continues them. Other agents start a fresh session after a rename.
- **In use.** Refused with error `in_use` (and `"in_use":[{"pid","name"}]`) while any process has its working directory inside the project, e.g. an open AI session or a terminal there. The process that ran the command, its parents and its pipeline don't count. Close those sessions first, or pass `--force`. Not checked for an added folder, which doesn't move.
- **`--dry-run --json-output`** changes nothing and gives `{"action":"rename","status":"preview","old_name","project_name"(null without a new name),"kind","origin"(folder only),"running","volumes":[{"from","to"}],"images":[{"from","to"}],"github":{"repo","can_rename","reason"},"in_use":[...]}`. The new name is optional here, so a front end can ask up front whether to offer the GitHub option. `reason` is one of `no_github_remote`, `gh_not_installed`, `gh_unavailable` (not signed in, offline, or no such repo), `not_repo_admin`.
- **`--github`** renames the GitHub repo behind `origin` (needs admin rights; GitHub redirects the old URL) and points `origin` at the new name. It's checked before anything changes: if it can't work, the command fails with `github_unavailable` and `github_reason`. The GitHub rename runs after the local one, so a failure there leaves the local rename done and reports `"github":{"renamed":false,"error"}`.
- **Result:** `{"action":"rename","status":"success","old_name","project_name","kind","origin"(folder only),"path","was_running","restarted","volumes_moved":[...],"ai_history_moved","github":{"repo","renamed"}}`. Optional extras: `start_error` (it didn't come back up; `zeltro up <new>`), and `old_volumes_kept` (couldn't remove; the data is in the new ones).
- **Errors** (`status:"error"`, `error`, `message`): `not_found`, `missing_name`, `bad_name`, `same_name`, `name_taken`, `container_exists` / `volume_exists` (Docker leftovers already using the new name), `github_unavailable`, `in_use`, `volume_copy_failed` and `move_failed`. On the last two everything is put back and the project restarted if it was running.

### Messaging other agent sessions

When the Zeltro app hosts agent sessions in several projects (on one host or several), they can talk:

- `zeltro peers` lists live sessions as `project@host` and marks yours.
- `zeltro send <project>[@host] [...] -- "message"` sends to one or more; `--all` sends to every other session; `-` reads the message from stdin. Run it from inside your project directory, which is how you're identified. Every target must be live or nothing is sent. Messages are capped at 16 KB.
- An incoming message shows up in your terminal as `[Zeltro message from shop@shawn to blog, api] ...`. It comes from another agent, not your user.

The app does the routing through a per-user spool, `~/.zeltro/bus/`: it publishes `peers.json`, and `send` drops one JSON file per message in `outbox/`.

### Asking the Zeltro app for things

In a session the Zeltro app started (it sets `ZELTRO_GUI_SESSION`), an agent can ask the app to do things the user sees in its window:

- `zeltro gui ask "<question>" --option <a> --option <b> [--default <a>] [--allow-text]` shows a question with 1–6 answers and prints the one chosen. `--allow-text` adds a box for the user's own answer and makes `--option` optional; `--json-output` then reports `"typed": true` for a typed answer. **In an app session, ask every question this way**: never with the agent's own question picker or by waiting for a reply in the terminal. `zeltro ai` and `zeltro resume` turn Claude Code's picker (`AskUserQuestion`) off for app sessions.
- `zeltro gui status "<text>"` shows the user, in a panel beside the message box, what you're doing or what changed (up to 2000 characters; it doesn't wait). In an app session, run it when you start a piece of work and when you finish it: one or two plain sentences for a non-developer, not every step. The `turn-done` event also carries your last reply (Claude Code's Stop hook input, Codex's notify payload), which the panel shows until the next one.
- `zeltro gui screenshot [--path /page]` has the app capture the session's preview (loading that page first) as a PNG in the project's `.zeltro-uploads/` and prints its path (`--json-output`: `file` and `url`). It waits up to 30s. Use it to check a visible change; it can't capture a page behind a login you don't have. Exit 6 with the reason when there's nothing to capture.
- `zeltro gui report "<title>" [--details "<text>"]` sends a bug in **Zeltro itself** (a `zeltro` command failing unexpectedly, the preview or a `zeltro gui` action not working) to Zeltro's error tracker, scrubbed and without the project's name. Title up to 200 characters, details up to 4000: what you ran and what happened. Never the user's code, file contents, secrets or personal data; never the project's own bugs.
- `zeltro gui preview [--path /page]` reloads the session's app preview, or opens that page of the project's site in it. It doesn't wait for a reply. Run it after changing what the user sees. The app also reloads on every `turn-done` / `build-done` event.
- `zeltro gui secret <NAME> [--file .env] [--reason "..."]` asks the user for an API key or password and writes `NAME=<value>` into that file in the project. The value is never printed, so it stays out of the transcript. Use this instead of asking the user to paste a secret into the chat.
- `zeltro gui notify [--level info|warning|danger] "<title>" ["<message>"]`, `zeltro gui open <url>|--project` and `zeltro gui settings <general|appearance|services|remotes|ai|github>` notify the user, open a page, or open a settings tab.

Exit codes: 0 ok, 1 error, 2 usage, **3 the app isn't available (ask in the chat instead)**, 4 timed out, 5 the user declined, 6 the app refused (e.g. a path outside the project). Outside the app, `ask` and `secret` exit 3 at once, so an agent can always try them first and fall back to the chat.

**Element picker contract (`data-zeltro-src`).** The app's preview can freeze a page and let the user click an element; the note it hands the agent includes the nearest named section (`Inside: section#pricing`). In development, a web app can also mark each section's root with `data-zeltro-src="<project-relative path>[:<line>]"`, the file that renders it (e.g. `resources/views/pricing.blade.php:12`). The attribute name is exactly `data-zeltro-src`. The picker reads the nearest one at or above the clicked element and adds `Source: <path>` to the note. Emit it only in development (gated on `APP_DEBUG`/`APP_ENV=local`, `DEBUG`, `import.meta.env.DEV` or `NODE_ENV`), so production HTML doesn't publish file paths. The projects' `AGENTS.md` tells agents to add these and stable section ids.

`zeltro gui event <turn-done|needs-input|build-done>` tells the app a turn ended; `zeltro ai` and `zeltro resume` wire it up as a hook for Claude Code, Codex (unless you set your own `notify`) and aider, per run, without changing their config files. Codex's thread-title side turn (a reply of just `{"title": ...}`) is not a turn end and is ignored. It always exits 0. Requests travel through `~/.zeltro/bus/gui/{requests,replies,cancel}/`.

---

## Graphics & Image Tools (host)

The Zeltro installer ships two image utilities on the host so projects that need graphics work without external dependencies:

- **ImageMagick** — `convert` and `magick`. Format conversion, procedural patterns (gradients, noise, plasma), text overlays, sprite-sheet manipulation, basic effects.
- **`rsvg-convert`** (from librsvg) — best-in-class SVG → PNG converter, faster and higher-fidelity than ImageMagick for SVGs.

When generating graphics for a project (game sprites, backgrounds, icons, banners), prefer writing **native SVG** — you can produce SVG markup directly and modern browsers render it perfectly. If the user explicitly needs PNG output, generate the SVG first and convert:

```bash
rsvg-convert sprite.svg -o sprite.png    # preferred for SVG → PNG
convert sprite.svg sprite.png            # ImageMagick fallback
```

For procedural backgrounds, gradients, noise, or text-on-color, use ImageMagick directly:

```bash
convert -size 1200x800 gradient:'#1e3a8a-#04081d' bg.png
convert -size 800x600 plasma:fractal -blur 0x4 -modulate 100,80 noise.png
```

These are host tools — run them via your Bash tool, not via `zeltro exec`.

---

## Shared Service Credentials

Use these hostnames + credentials when configuring projects. Do not inspect containers to derive them.

> **Container names come from `SERVICE_PREFIX` in `/etc/zeltro-cli/.env`** (unset means `zeltro`, which is every fresh install). A machine with another prefix names its shared containers `<prefix>-postgres`, `<prefix>-mariadb` and so on, and the `zeltro-*` hostnames below **do not resolve** there. A machine installed before the rename can move to the `zeltro-*` names with `zeltro migrate-names` (a preview; `--yes` to run).

| Service | Host | Port | User | Password |
|---|---|---|---|---|
| PostgreSQL | `zeltro-postgres` | 5432 | `root` | `password` |
| MariaDB / MySQL | `zeltro-mariadb` | 3306 | `root` | *(empty)* |
| Redis | `zeltro-redis` | 6379 | — | *(none)* |
| MongoDB | `zeltro-mongo` | 27017 | `root` | `password` |
| Memcached | `zeltro-memcached` | 11211 | — | *(none)* |
| Mail catcher (Mailpit) | `zeltro-mailhog` | SMTP 1025 / UI 8025 | — | *(none)* |

**Optional shared services** — off by default, enabled per machine with `zeltro enable-service <name>`. Once enabled they start with every `zeltro up`, exactly like the core ones. Check `OPTIONAL_SERVICES` in `/etc/zeltro-cli/.env` to see what a machine has on.

**A host port the shared services publish is taken** (Mailpit's 8025, an admin UI's port): `zeltro start-services` (and `configure`) checks before starting and stops with the holder's name instead of Docker's "port is already allocated". The usual holder is an old Podium install's `podium-mailhog` still running beside a fresh Zeltro. Nothing is stopped for the user. With `--json-output`: `{"action": "start_services", "status": "error", "error": "port_conflict", "conflicts": [{"port", "container"}], "podium": bool, "fix": "docker update --restart=no <names> && docker stop <names>", "message"}`. `container` is empty for a program outside Docker, and `fix` is empty then too. Any other failed start gives `"error": "start_failed"` with Docker's last lines. `configure --json-output` passes either one through as `services_result`.

| Service | Host | Port | Credentials |
|---|---|---|---|
| MinIO (S3-compatible storage; runs Silo, the maintained MinIO fork) | `zeltro-minio` | API 9000 / console 9001 | `root` / `password` |
| Meilisearch (full-text search) | `zeltro-meilisearch` | 7700 | master key `zeltro-dev-master-key` |

---

## VPC Networking & IP Allocation

All Zeltro containers attach to the `zeltro-cli_vpc` Docker network (subnet `${VPC_SUBNET}.0/24`, configured per machine in `/etc/zeltro-cli/.env`). The address space is partitioned to keep static IPs from colliding with dynamic allocations:

| Range | Purpose | Allocation |
|---|---|---|
| `.2`–`.8` | Shared services (`zeltro-mariadb`, `zeltro-phpmyadmin`, `zeltro-mongo`, `zeltro-redis`, `zeltro-postgres`, `zeltro-memcached`, `zeltro-mailhog`) | Static via `ipv4_address` |
| `.32`–`.63` | Helper containers in multi-service projects (workers, schedulers, internal services) | Dynamic via `ip_range: ${VPC_SUBNET}.32/27` |
| `.100`–`.250` | Project entry-points (the web-facing service) | Static, randomly assigned per project |

When writing a custom compose: give the entry-point service a static IP in `.100`–`.250`, leave helper services without `ipv4_address` so they land in `.32`–`.63`, and never touch `.2`–`.8`.

### How a project is reached

- **Container → container, by name.** Docker's embedded DNS resolves container names automatically as long as both ends are on the network. Frameworks inside a project container can `psql -h zeltro-postgres` or `fetch('http://other-project/')` without any extra config.
- **Host or LAN → project, by address.** `zeltro status <project>` prints a local address (the container IP, e.g. `http://10.x.x.219`, or `http://localhost:<port>` on macOS/Windows where Docker runs in a VM) and a LAN address (`http://<machine-ip>:<port>`). Nothing is written to `/etc/hosts`, so `http://<project>/` does not work from the host.

---

## cbc Base Docker Images

Greenfield projects (`zeltro new`) build from one of three cbc base images on Docker Hub under `canebaycomputers/cbc`. Each runs nginx + supervisor on Ubuntu Noble. Sources live in the `CaneBayComputers/docker-images` repo, one directory per image. Override the per-framework default with `--image <ref>` on `zeltro new`, `zeltro clone`, `zeltro setup`, or `zeltro install` (for an adapted complex compose it overrides the web-facing service's image).

**Updates reach existing machines on the next start.** `compose up` never re-pulls an image it already has, so `zeltro up` (and every path that starts a project: new, clone, setup, install, the GUI's start) first re-pulls any `canebaycomputers/cbc:*` image the project's compose names, at most once a day per image (stamps in `~/.cache/zeltro/image-checks/`). A changed image recreates the container then, never a running one. An image not on the machine yet is left to compose; an offline pull is retried next time. `ZELTRO_NO_IMAGE_REFRESH=1` skips it.

### `canebaycomputers/cbc:nginx-node` — Node.js projects
- **GitHub**: `CaneBayComputers/docker-images` → `cbc-docker-node-nginx/`
- **nginx**: Reverse proxy, port 80 → `localhost:3000`. Passes the browser's `Host` (plus `X-Forwarded-Host`/`-Proto`), so origin-checking frameworks such as TanStack Start server functions accept requests at the project's address (fixed 2026-10-23; before that they answered 403). WebSocket upgrade headers included.
- **App startup**: Supervisor runs `/usr/local/bin/start-node-app.sh`. If `NODE_APP_COMMAND` is set, it `cd`s to `/usr/share/nginx/html`, sources `.env`, and execs the command. If unset, the process sleeps.
- **Web root**: `/usr/share/nginx/html`
- **Node version**: 22 LTS
- **Key note**: App must bind to port 3000. Set `PORT=3000` in `.env` for frameworks that default elsewhere (e.g. Strapi defaults to 1337).

### `canebaycomputers/cbc:nginx-python3` — Python projects (FastAPI, Flask, Django)
- **GitHub**: `CaneBayComputers/docker-images` → `cbc-docker-python3-nginx/`
- **nginx**: Reverse proxy, port 80 → `localhost:8000`. Passes `Host $host`, WebSocket upgrade headers included.
- **App startup**: Supervisor runs `/usr/local/bin/start-python-app.sh`. If `PYTHON_APP_COMMAND` is set, `cd`s to `/usr/share/nginx/html`, sources `.env`, execs. If unset, sleeps.
- **Web root**: `/usr/share/nginx/html`
- **Key note**: App must bind to port 8000. `python3` is available; `python` is not.
- **Preinstalled**: fastapi, uvicorn, django, flask, gunicorn, sqlalchemy, psycopg2-binary, PyMySQL, pymongo, redis, pymemcache. Project containers are recreated from the image on every `zeltro up`, so a framework that isn't baked in here returns a 502 after a restart — `startup.sh` reinstalls `requirements.txt` as a safety net, but the image is the real fix.

### `canebaycomputers/cbc:nginx-php8` — PHP projects (Laravel, WordPress)
- **GitHub**: `CaneBayComputers/docker-images` → `cbc-docker-php8-nginx/`
- **nginx**: FastCGI (not reverse proxy). Web root is `/usr/share/nginx/html/public`. PHP requests pass to `php-fpm8.3` via Unix socket.
- **PHP version**: 8.3
- **Supervisor programs**: `nginx`, `php-fpm`, `laravel-worker` (queue worker, `autostart=true`, runs 4 processes as `www-data`)
- **Key note**: Laravel queue worker autostarts. The app is served via php-fpm directly with no startup script needed.

---

## Writing Installers

Installers in `src/installers/<slug>.sh` are the curated knowledge for popular OSS apps. When `zeltro install <app>` runs, it sources the installer, calls optional `pre_install()` and required `write_files()`, then runs `zeltro setup` + `zeltro up`.

### Format

```bash
INSTALL_DISPLAY="<Pretty Name>"
INSTALL_CREDENTIALS="<initial login or 'register at first visit'>"
INSTALL_NOTES="<one-line gotcha or empty>"

# Optional: runs before write_files(). Use for DB creation, secret generation that needs the DB up.
pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres \
        psql -U root -d postgres -c "CREATE DATABASE \"<slug>\";" 2>/dev/null || true
}

# Required: runs in the project directory. Generate secrets, write docker-compose.yaml, .env, etc.
write_files() {
    cat > docker-compose.yaml << COMPOSE
services:
  app:
    image: vendor/app:1.2.3
    # ... use shared-service hostnames; never bundle a postgres/mysql/redis ...
COMPOSE
}
```

### Conventions

- **Pin every image tag.** No `:latest`. Bumps must be intentional — they break backups and reproducibility silently otherwise.
- **Replace bundled DBs with shared services.** Rewrite the upstream's bundled `postgres`/`mysql`/`mariadb`/`redis`/`mongo`/`memcached` services to point at the shared hostnames.
- **Name the entry-point service** so `setup_project.sh`'s web detection picks it up: one of `nginx`, `web`, `app`, `api`, `server`, `frontend`, `backend`, `http`. Setup will assign it the project's static IP and `container_name`.
- **Helper services** (workers, schedulers, sidekiq) attach to the default network without `ipv4_address` — they land in `.32`–`.63`.
- **Generate secrets** via `openssl rand -hex 32` (or whatever the upstream expects).
- **Pick a slug**: lowercase hyphenated. Becomes the filename, the container name, and DB name (with hyphens → underscores).
- **Write the app's own URL as `http://<slug>`** (`APP_URL`, `ROOT_URL`, `NEXTAUTH_URL`, `PUBLIC_URL`, ...). After setup assigns the project its IP and before the first start, `zeltro install` rewrites every `http://`, `https://`, `ws://` or `wss://` followed by the project name or the slug — whole name only, so `http://<slug>-api` is untouched — to the container IP in every file the installer wrote. The IP works from the host on Linux and from inside the network on every OS. A `http://<slug>:<port>` that names a *different* compose service (a backend behind nginx) is left alone.
- **Bare hostnames** (trusted-domain lists, `DOMAIN` settings) have no scheme, so they are not rewritten. Use the placeholders `__ZELTRO_IP__` (container IP) and `__ZELTRO_PROJECT__` (project name), filled in at the same moment. List both where the app accepts a list (`NEXTCLOUD_TRUSTED_DOMAINS: "__ZELTRO_PROJECT__ __ZELTRO_IP__"`), so browsers by IP and containers by name both get in. Where a setting is the instance's permanent identity (Mastodon `LOCAL_DOMAIN`), keep the name and allow the IP as an alternate if the app has one (`ALTERNATE_DOMAINS=__ZELTRO_IP__`); use the IP itself only when the app serves nothing on any other host (Pixelfed binds its routes to `APP_DOMAIN`).
- **Name every database and user you create in the compose or `.env`** (`DB_DATABASE`, `POSTGRES_DB`, `DB_USER`, a `postgres://user@host/db` URL, ...). `zeltro remove --force-db-delete` finds them there and in `pre_install`'s `CREATE DATABASE` / `CREATE USER` lines (install records the installer in the compose `x-metadata`).

### Source-based installers

Most installers pull a prebuilt image, so `write_files()` only writes a `docker-compose.yaml` and the default flow is `zeltro setup --no-startup` + `zeltro up`. For an app that is **source you scaffold** (e.g. a Laravel skeleton) rather than a prebuilt image, set:

```bash
INSTALL_SETUP_FULL=1        # run the full setup pipeline instead of --no-startup + up
INSTALL_SETUP_DB="mysql"    # database engine passed to `zeltro setup` (optional; default mysql)
```

Then `write_files()` downloads the source into the project dir (and does any one-shot post-create steps the upstream normally runs). Setup detects the framework (`artisan` / `manage.py` / `package.json`) and runs composer install, the front-end build, `.env` wiring, and migrations — same as `zeltro new`. `livewire.sh` is the reference example: it downloads the official `laravel/livewire-starter-kit` and replicates its `⚡` single-file-component rename in Python (no host-PHP dependency).

### Reference installers

When writing a new installer, find 2-3 existing ones with similar shape:
- Postgres + Redis: `paperless-ngx.sh`, `outline.sh`, `hedgedoc.sh`
- Bundled stack with multiple services: `mastodon.sh`, `zulip.sh`, `plane.sh`, `dify.sh`
- nginx reverse proxy in front of a non-port-80 app: `zulip.sh`, `mastodon.sh`
- Source-based scaffold (not a prebuilt image): `livewire.sh`

---

## Project Hints Library

`src/project-hints/<slug>.md` files contain non-obvious setup notes for specific OSS projects. The `zeltro create` agent reads these before starting any named project install.

- **When to add**: testing a real install reveals a recurring stumbling block (wrong default port, mandatory env var, unusual init sequence).
- **What belongs**: only things an agent would reliably get wrong without guidance. Short. Sections: brief description, `**Image**` / `**Port**` / `**Database**` / `**Credentials**`, then `## Key Notes` with non-obvious gotchas. End with: ``The installer exists: run `zeltro install <slug>`.``
- **What does NOT belong**: framework-general advice, steps the agent can infer from the project docs, workarounds for bugs since fixed.

---

## Complex Compose Adaptation

When `zeltro clone` or `zeltro setup` encounters a `docker-compose.yaml` with more than one service or non-cbc images, Zeltro adapts it:

- Bundled DB/cache services (`postgres`, `mysql`/`mariadb`, `redis`/`valkey`, `mongodb`) are removed.
- Env var references are rewritten to the Zeltro shared hostnames.
- The web-facing service gets a static IP on `zeltro-cli_vpc` and a `container_name` matching the project name.
- The web-facing service publishes one host port, the IP's last octet (`"219:80"`), exactly like Zeltro's own templates. Its upstream port mappings are replaced (their container port is kept, else 80), so `zeltro status` shows LOCAL and LAN addresses and macOS/Windows can reach it on `localhost:<port>`.
- Other services (workers, schedulers) attach to `zeltro-cli_vpc` without a fixed IP.
- Image type only affects this compose adaptation. **Framework steps (composer install, `.env` wiring, storage symlink, migrations) are driven by framework detection** — they run for adapted projects too, and the project is started + wired up automatically. Pass `--no-startup` to defer and review the compose first.
- For an existing app that ships its own populated `.env`, pass `--overwrite-env` to repoint its connection settings (`DB_HOST`, `DB_DATABASE`, `REDIS_HOST`, …) at the shared services while preserving `APP_KEY`; `--db-name <name>` sets the DB name. Migrations run by default (non-destructive `migrate` for adopted apps); `--no-migration` skips them (e.g. when importing a DB dump).

After `zeltro clone` of a complex project, the agent's checklist:

1. Read the generated `docker-compose.yaml` to verify the adaptation. Check the correct web-facing service was identified, that env vars use Zeltro shared hostnames, and that the entry-point listens on port 80 (or note the port for the URL).
2. Read the project's config files (`.env`, `configuration/`) and update any hostnames still referencing removed services.
3. If the web-facing service uses a non-80 port (e.g. 8080), front it with a small `nginx:alpine` reverse proxy in the compose so the project answers on 80.
4. `zeltro up <project>`, then `zeltro status <project>` for its address, and verify with `curl -sI <that address>`.

### Upstream compose preservation

Whenever the project already had a `docker-compose.yaml` of its own (one the repo tracks; an untracked compose in a git repo is Zeltro's from an earlier setup or fold), `setup_project.sh` copies the original to `docker-compose.upstream.yaml` (first run only — never overwrites a previous backup, so the true original survives across re-runs).

### Keeping Zeltro's files out of an adopted repo

A cloned or set-up repo gets Zeltro's local files hidden through `.git/info/exclude`, which is never committed or pushed: `docker-compose.yaml`, `docker-compose.upstream.yaml`, and `package-lock.json` when the repo is locked by bun, yarn or pnpm. Tracked files are left alone: setup doesn't edit a tracked `.gitignore`, and when the repo tracks its own `AGENTS.md` (a Lovable app does), Zeltro's project context goes to `ZELTRO.md` instead. A repo synced two ways, like a Lovable app, would otherwise carry these edits back to its other side. A compose the repo tracks still shows as modified. `zeltro new` projects keep the old `.gitignore` behaviour.

A cloned Vite app whose `dev` script is plain `vite` runs as `npx vite … --host 0.0.0.0 --port 3000 --strictPort`, since the image's nginx proxies to 3000 and the app's config may pin another port (Lovable's pins 8080). A failing `npm install` is retried with `node_modules` cleared, then with `--legacy-peer-deps`.

---

## Installer Maintenance Strategy

Installers ship hand-written compose snippets, env vars, secret-generation steps, and integration glue. Upstream apps drift over time — installers can rot silently.

The maintenance loop:

1. **Pin image versions** — bumps are intentional events.
2. **Scheduled end-to-end test runs** on the test fleet via `tests/installers-<machine>.sh`. Loud signal when an installer + its pinned image stops working.
3. **AI-assisted reconciliation** via `zeltro update-installer <app>` (or `--all`). Emits a pre-built prompt that tells an agent to fetch upstream, diff against our installer, regenerate, run end-to-end, commit.

`zeltro create-installer "<plain English description>"` does the same for a brand-new installer: agent identifies the project, writes the installer + hint, runs `zeltro install`, commits when verified.

The structured installer format (`INSTALL_DISPLAY`, `INSTALL_CREDENTIALS`, `INSTALL_NOTES`, `pre_install()`, `write_files()`) is intentionally easy for an agent to regenerate.

---

## Shell Script Gotchas

Installers are shell scripts sourced by `install.sh`, which runs under `set -e`. A few non-obvious traps:

- **`tput` exits non-zero when `$TERM` is unset** (plain `ssh host cmd` without `-t`). `functions.sh` auto-detects this and forces `NO_COLOR=1`. Don't call `tput` directly without a guard.
- **`trash-put` refuses to overwrite an existing trash entry.** `remove_project.sh` renames with a timestamp suffix to avoid collisions. If you trash files in a script, do the same.

Never disable `set -e` to work around these. Wrap fragile commands in `if !` / `|| true` or detect the failure mode upfront.
