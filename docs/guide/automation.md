---
title: Automation & JSON
nav_order: 11
---

# Automation, JSON and troubleshooting

---

## No interactive prompts

A missing required argument is a hard error with a usage hint, never a prompt, and the command exits non-zero. Nothing blocks a script or an agent waiting for input.

A few commands do ask questions, but only when a person is at a terminal:

- `zeltro create` prompts only at a terminal. Under `--one-off`, `--json-output` or a non-terminal stdin it falls back to the hard error.
- `zeltro configure` asks for the projects directory (and your git name and email if git has none) unless you pass `--non-interactive` (`--yes`, `-y`) or `--json-output`. Pass `--projects-dir` to set the directory without a prompt.
- `zeltro ai-set` with no flags opens a menu at a terminal. With any flag, or without a terminal, it doesn't.
- `zeltro uninstall` asks whether to delete Docker images unless you pass `--delete-images` or `--json-output`.

Use `zeltro up-all` / `zeltro down-all` to act on every project rather than looping.

### Running commands in a project

Use `zeltro exec <cmd>` from the project directory. It runs without a TTY, runs as your own user so the bind-mounted files stay writable, and returns the command's exit code. `zeltro exec-root` does the same as root. Both take separate arguments or one quoted string:

```bash
zeltro exec python3 manage.py migrate
zeltro exec "php artisan migrate --force"
```

`zeltro bash`, `zeltro tinker` and `zeltro exec-tty` / `exec-tty-root` are for interactive use and allocate a TTY when there is one. Don't use a raw `docker exec -u developer …` either: the container's `developer` user doesn't own your project files.

### Per-session AI overrides

`zeltro ai`, `resume`, `create`, `clone`, `create-installer` and `update-installer` use the agent set by `zeltro ai-set`. To use a different one for a single run, set these in the environment. They are never written to the config.

| Variable | Overrides |
|---|---|
| `ZELTRO_AI_AGENT` | The agent: `codex`, `claude`, `gemini`, `aider` or `qwen` |
| `ZELTRO_AI_MODEL` | The model |
| `ZELTRO_AI_API_BASE` | The API endpoint |
| `ZELTRO_AI_API_KEY` | The API key |
| `ZELTRO_AI_API_KEY_FILE` | The API key, read from the file's first line. Wins over `ZELTRO_AI_API_KEY`. |
| `ZELTRO_AI_LANGUAGE` | The language the agent replies in, e.g. `Spanish`. Zeltro's own output stays English. |

Unset means "use the `ai-set` value"; set but empty clears it for this run. An unknown agent name, an unreadable key file, or an override agent that isn't installed exits non-zero before anything runs. `zeltro ai-set --install-only --agent <name>` installs an agent without making it the default.

### Messaging other agent sessions

When the Zeltro app runs agent sessions in several projects, they can message each other:

```bash
zeltro peers                                  # live sessions, as project@host
zeltro send blog api -- "schema changed"      # to one or more sessions
zeltro send --all -- "rebasing main"          # to every other session
echo "long message" | zeltro send blog -- -   # read the message from stdin
```

Run `send` from inside your project directory; that is how the recipient knows who sent it. Every target must be live or nothing is sent. Messages are capped at 16 KB. The app delivers them, so it has to be running.

---

## JSON output

`--json-output` produces clean machine-readable output for GUIs and scripts.

```bash
zeltro status --json-output
zeltro new laravel myapp --json-output
```

`new` prints one object, with the setup step's own result nested inside:

```json
{
  "action": "new_project",
  "project_name": "myapp",
  "framework": "laravel",
  "database": "mysql",
  "setup_result": { "action": "setup_project", "status": "success", "...": "..." },
  "status": "success"
}
```

When setup had to turn on a database server, `setup_result` also carries `services_enabled` (for example `["postgres"]`) and `admin_uis_suggested`.

`status` prints `shared_services`, keyed by container name, and `projects`:

```json
{
  "shared_services": {
    "zeltro-mariadb": { "name": "zeltro-mariadb", "status": "running", "port": "3306", "resolved_ip": "10.x.x.2", "ping_status": "ok" }
  },
  "projects": [
    {
      "name": "my-api",
      "project_ip": "10.x.x.219",
      "external_port": "219",
      "docker_running": true,
      "http_status": "ok",
      "local_url": "http://10.x.x.219",
      "lan_url": "http://192.168.1.20:219",
      "metadata": {}
    }
  ]
}
```

Service `status` is `running` or `stopped`. Without `--all`, `projects` lists only running projects.

Other shapes, all with `action` and `status`:

| Command | Output |
|---|---|
| `enable-service` (no name) | `action: "list_services"`, `always_on`, and `services[]` with `slug`, `group`, `description`, `address`, `state` (`running`, `disabled` or `enabled_not_running`) |
| `enable-service <name>` / `disable-service <name>` | `action: "enable_service"` / `"disable_service"`, `service`, `enabled` (the new space-separated list) |
| `ai-set` (only `--json-output`) | `action: "ai_set"`, `agent`, `model`, `api_base`, `has_api_key`, `unattended`, `installed_agents`. Read-only. |
| `peers` | `action: "peers"`, `this_host`, `me`, `app_running`, `updated_at`, `age_seconds`, `sessions[]` |
| `send` | `action: "send"`, `id`, `from`, `to`, `file`, `app_running` |
| `down` | `action: "shutdown"`, `target`, `project_name` |
| `remove` | `action: "remove_project"`, `project_name`, `database_deleted` |

Errors print `"status": "error"` with a `message` or `error` field and exit non-zero, so check the exit code as well as the JSON.

Scripting examples:

```bash
# is the shared MariaDB up?
if zeltro status --json-output | jq -e '.shared_services["zeltro-mariadb"].status == "running"' >/dev/null; then
    echo "Database is ready"
fi

# list stopped projects
zeltro status --all --json-output | jq -r '.projects[] | select(.docker_running == false) | .name'
```

### Which commands support it

**Supported:** `status`, `new`, `clone`, `setup`, `remove`, `up`, `down`, `down-all`, `start-services`, `stop-services`, `enable-service`, `disable-service`, `enable`, `disable`, `set-metadata`, `configure`, `create` (including `--classify-only`), `ai-set`, `peers`, `send`.

**Partly:** `install --json-output` prints the JSON from its `setup` and `up` steps but no summary object of its own. `uninstall --json-output` only skips the image prompt; it prints no JSON.

**Not supported** — anything that runs inside a container or connects straight to a service: `composer`, `art`, `wp`, `php`, `npm`, `npx`, `node`, `python`, `pip`, `shell`, `django`, `exec`, `supervisor`, `redis`, `memcache`.

{: .warning }
**If you are an AI agent, never use `--json-output`.** It suppresses all human-readable output including the success/failure distinction, so you cannot tell whether a command actually worked. It exists for external programs that parse Zeltro's output, not for agents driving the CLI.

---

## Debugging

```bash
zeltro new laravel test-project --debug
tail -f /tmp/zeltro-cli-debug.log
```

`--debug` works on `new`, `clone`, `setup`, `up`, `down`, `status`, `remove`, `configure`, `start-services`, `stop-services` and `uninstall`. Each invocation overwrites the log and records script flow across the scripts it calls. Set `DEBUG_LOG_PATH` to write it somewhere else.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Services won't start | Docker is running; you're in the `docker` group (log out and back in after install) |
| Permission errors | Same — `docker` group membership needs a fresh login |
| Can't reach a project in the browser | Use the address `zeltro status <project>` prints (`http://<project>/` doesn't resolve on the host); then `docker logs <project-name>` |
| Database connection refused | `zeltro status` — is the shared service running? If it shows `stopped`, `zeltro enable-service mysql` (or `postgres`, `mongo`) |
| Project 502s after a restart | A dependency isn't in the base image. See [Architecture → Base images](../architecture/#base-images) |
| Fedora: permission denied on project files | SELinux — re-run `zeltro configure` to relabel. See [Installation](../installation/#fedora--rhel--selinux) |
| Arch: Docker won't start after install | The system upgrade replaced the running kernel — reboot |

Useful probes:

```bash
zeltro status                               # shared services and running projects
zeltro status --all                         # include stopped projects
zeltro status <project>                     # one project, even if stopped
docker logs <project-name>
zeltro exec "getent hosts zeltro-mariadb"   # name resolution from inside the container
```

---

## Graphics tooling

The installers ship ImageMagick (`convert`, `magick`) and `rsvg-convert` on the host, so projects needing graphics have no extra dependencies.

Prefer generating **SVG** — browsers render it perfectly and it's text an agent can write directly. Convert only when a raster is genuinely required:

```bash
rsvg-convert sprite.svg -o sprite.png                        # best SVG → PNG fidelity
convert -size 1200x800 gradient:'#1e3a8a-#04081d' bg.png     # procedural backgrounds
```

These are host tools — run them directly, not through `zeltro exec`.
