---
title: AI workflow
nav_order: 7
---

# AI workflow

Zeltro's command surface is shaped around AI-driven development. The point is to give an agent a fixed environment to work inside, so it builds your app instead of inventing infrastructure.

Zeltro doesn't sell AI. It drives an agent CLI you install and sign in to, and you pay that provider directly (or nothing, with a local model).

---

## Choosing an agent

```bash
zeltro ai-set --agent claude --model claude-opus-5-5
zeltro ai-set --agent codex  --model gpt-6-sol
zeltro ai-set --agent gemini
zeltro ai-set --agent aider  --model anthropic/claude-sonnet-5 --api-key sk-ant-...
zeltro ai-set --agent qwen   --model qwen/qwen3-coder-30b-a3b-instruct --api-base https://openrouter.ai/api/v1 --api-key sk-or-...
zeltro ai-set --json-output          # inspect current settings (read-only)
```

A fresh install has no agent set, and the AI commands tell you to run `zeltro ai-set` first. If you're unsure, pick `claude` and leave the model blank so Claude Code uses its own default.

| Flag | Description |
|---|---|
| `--agent <name>` | `codex`, `claude`, `gemini`, `qwen`, or `aider`. Switching agents clears the stored model and endpoint. |
| `--model <name>` | Model name. Optional for Codex, Claude and Gemini; needed for Qwen Code and Aider |
| `--api-key <key>` | API key. Optional for Codex and Claude, which can use their own sign-in; needed for Aider and for a hosted Qwen Code model. `--api-key ""` clears a stored key |
| `--api-base <url>` | Custom endpoint. OpenAI-compatible for `qwen` and `aider`; Anthropic-compatible for `claude`. `none` clears it. See [Cheap and local models](../cheap-models/) for Codex |
| `--install-only` | With `--agent`: install that agent's CLI if it's missing, without making it the default |
| `--allow-unattended` / `--no-allow-unattended` | Turn the agent's approval prompts off or back on (see [Unattended mode](#unattended-mode)) |

When you pick an agent that isn't installed, `zeltro ai-set` installs it with:

```bash
curl -fsSL https://claude.ai/install.sh | bash     # Claude Code
npm install -g @openai/codex                       # Codex
npm install -g @google/gemini-cli                  # Gemini CLI
npm install -g @qwen-code/qwen-code                # Qwen Code
curl -LsSf https://aider.chat/install.sh | sh      # Aider
```

Zeltro passes a stored key only where it fits. Codex gets it as `OPENAI_API_KEY` only if it starts with `sk-`, and Claude gets it as `ANTHROPIC_API_KEY` only if it starts with `sk-ant-`. Anything else is ignored with a warning, and the CLI uses its own sign-in. Gemini never gets the key or the endpoint: it uses its own Google sign-in, or a `GEMINI_API_KEY` you export yourself.

`zeltro ai-set --json-output` on its own is read-only. It installs nothing and writes nothing, and reports the agent, model, endpoint, whether a key is stored, the unattended setting, and which agents are installed.

**Running cheaper or local models?** See
[Cheap and local models](../cheap-models/). Qwen Coder on OpenRouter costs
roughly 30x less per token than Claude Sonnet 5, and a local Ollama model costs
nothing to run.

Settings live in `/etc/zeltro-cli/.env`. Always change them with `zeltro ai-set` rather than editing the file.

### Aider

Codex, Claude and Gemini each sign in with their own account. Aider doesn't. It
talks straight to a provider API, so it needs a model and a key before it will run:

```bash
# a hosted provider (the model prefix picks it)
zeltro ai-set --agent aider --model anthropic/claude-sonnet-5 --api-key sk-ant-...

# a local OpenAI-compatible server
zeltro ai-set --agent aider --model openai/qwen3-coder:30b \
  --api-key ollama --api-base http://localhost:11434/v1
```

Zeltro tags the key with the provider from the model prefix (`anthropic=sk-ant-...`),
or with `openai` when there is no prefix. `--api-base` is only for OpenAI-compatible
servers (Ollama, LM Studio, OpenRouter, vLLM); leave it blank to use a provider's own
hosted API. Aider normally commits each edit itself. Zeltro runs it with
`--no-auto-commits` so its changes sit in your working tree like every other agent's.

### Qwen Code

[Qwen Code](https://github.com/QwenLM/qwen-code) is an open-source terminal agent
that started as a fork of Gemini CLI and is built around the Qwen Coder models.
Zeltro installs it with `npm install -g @qwen-code/qwen-code`.

Zeltro runs it in OpenAI-compatible mode (`--auth-type openai`, with the key and
endpoint in `OPENAI_API_KEY` and `OPENAI_BASE_URL`), so it is the simplest route to a
cheap hosted model or a local one:

```bash
# hosted, pay-as-you-go
zeltro ai-set --agent qwen --model qwen/qwen3-coder-30b-a3b-instruct \
  --api-base https://openrouter.ai/api/v1 --api-key sk-or-...

# local Ollama
zeltro ai-set --agent qwen --model qwen3-coder:30b \
  --api-base http://localhost:11434/v1 --api-key ollama
```

Qwen's free OAuth sign-in was discontinued on 15 April 2026, so it needs an API key
or a local endpoint. There is no free hosted route through Qwen itself. It also wants
**Node 22+**; it runs on Node 20 with an `EBADENGINE` warning, but that is unsupported.

---

## Unattended mode

By default an agent asks before each file edit or command. That stalls
`zeltro create`, which hands the agent a task and expects it to finish on its own.

Zeltro does not turn those prompts off behind your back. The first time
`zeltro ai-set` sets up an agent in a terminal, it asks once, and if you say yes it
writes the setting into **the agent's own config file**, where you can see and undo it:

| Agent | File | Setting |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `"permissions": {"defaultMode": "bypassPermissions"}` |
| Codex | `~/.codex/config.toml` | `approval_policy = "never"`, `sandbox_mode = "danger-full-access"` |
| Gemini CLI | `~/.gemini/settings.json` | `"autoAccept": true` |
| Qwen Code | `~/.qwen/settings.json` | `"autoAccept": true` |
| Aider | `~/.aider.conf.yml` | `yes-always: true` |

```bash
zeltro ai-unattended                 # allow it for the current agent
zeltro ai-unattended codex --status  # report without changing anything
zeltro ai-unattended codex --revoke  # turn the prompts back on
```

`zeltro ai-set --allow-unattended` and `--no-allow-unattended` do the same thing as
part of a settings change. For throwaway containers and CI, `ZELTRO_AI_AUTO_APPROVE=1`
adds each agent's bypass flag to a single run instead.

{: .warning }
With unattended mode on, the agent can change anything your user account can. Only use `zeltro ai`, `zeltro create` and `zeltro resume` in directories you're comfortable letting an AI modify freely. All three follow this setting; `ZELTRO_AI_AUTO_APPROVE=1` overrides it for one run.

---

## Per-session overrides

`zeltro ai-set` is global. To use a different agent, model or key for one run without
changing it, set these in the environment. They are never written to the `.env`:

| Variable | Overrides |
|---|---|
| `ZELTRO_AI_AGENT` | The agent: `codex`, `claude`, `gemini`, `aider` or `qwen` |
| `ZELTRO_AI_MODEL` | The model |
| `ZELTRO_AI_API_BASE` | The endpoint |
| `ZELTRO_AI_API_KEY` | The key |
| `ZELTRO_AI_API_KEY_FILE` | The key, read from the first line of this file so it never shows in a process list. Wins over `ZELTRO_AI_API_KEY`. Keep the file until the session ends |
| `ZELTRO_AI_LANGUAGE` | The language the agent replies in, e.g. `Spanish`. Code and commands stay as they are, and Zeltro's own output stays English |

```bash
ZELTRO_AI_AGENT=qwen \
ZELTRO_AI_MODEL=qwen/qwen3-coder-30b-a3b-instruct \
ZELTRO_AI_API_BASE=https://openrouter.ai/api/v1 \
ZELTRO_AI_API_KEY_FILE="$HOME/.openrouter-key" \
  zeltro ai "Add a health-check endpoint at /ping"
```

Unset means "use the `ai-set` value"; set but empty means "clear it for this run".
An unknown agent, an unreadable key file, or an agent that isn't installed stops the
command before anything runs. Nothing is installed for you; use
`zeltro ai-set --install-only --agent <name>` to add an agent without making it the default.

The language instruction reaches Claude Code and Qwen Code through
`--append-system-prompt`, Codex through `-c developer_instructions=...`, and Aider
through `--chat-language`, so it also holds on `zeltro resume`. Gemini CLI has no way to
add to its system prompt, so `zeltro ai` puts the instruction at the top of the prompt
and a resumed Gemini session gets none.

In the Zeltro app, **AI profiles** (Settings → AI Profiles) are named agent, model,
endpoint and key setups you pick per session. Keys are stored encrypted, and a
profile reaches the CLI through these same variables. The built-in default profile
uses the host's `zeltro ai-set` configuration.

---

## `zeltro create`: idea to running project

```bash
zeltro create "A timeclock for employees in Django"
zeltro create "Set up n8n and configure a webhook that posts to Slack"
zeltro create "https://github.com/monicahq/monica"
```

`create` runs in three steps:

1. **Classify.** Your agent is asked only which stack fits, and answers in JSON: one framework to build it from scratch, any ready-made apps from Zeltro's catalogue that genuinely fit, a database, and a project name. In a terminal you pick from a menu. Scripts and `--one-off` take the top recommendation.
2. **Create.** Zeltro itself runs `zeltro new` or `zeltro install`. No AI is involved in this step.
3. **Build.** Zeltro writes the project's `AGENTS.md` and hands your original idea to the agent inside the project as a one-off `zeltro ai` run. The agent builds with framework-native conventions, updates the README, restarts the app and checks it responds before finishing.

If the idea only asks for an app to be installed ("set up Grafana"), step 3 is skipped: the installer has already checked the app responds and printed its URL and login.

### Input options

```bash
zeltro create "an idea"                  # argument
zeltro create -f spec.md                 # from a file
zeltro create < spec.md                  # stdin
cat spec.md | zeltro create              # pipe
zeltro create --one-off "..."            # no menus; take the top recommendation
zeltro create --classify-only "..."      # print the recommendation and stop; creates nothing
```

`--classify-only` never prompts. Add `--json-output` for a machine-readable result, which is what the Zeltro app uses.

---

## The `AGENTS.md` hand-off

When a project is created by `create`, `new`, `clone` or `install`, Zeltro writes an **`AGENTS.md`** into the project directory. For `new`, `clone` and `install` it then `cd`s into the project and hands your agent a prompt whose only job is to read that file. `--one-off`, `--json-output` or a non-terminal run skips that hand-off.

`AGENTS.md` records what an agent needs to pick the project up cold:

- Local URL, container name, project directory
- The resolved database, read from the project's `.env`
- Command patterns that work inside the container
- Shared-service hostnames and credentials
- Rules (never `--json-output`, `python3` not `python`, verify with curl before declaring done)

Because this context lives on disk rather than in a chat session, it survives closing your terminal, rebooting, and switching between agents.

The file is regenerated on each hand-off, but only between its markers. **Anything you write outside the generated block is preserved.**

---

## `zeltro ai`: a prompt in the current project

```bash
cd ~/zeltro-projects/my-app
zeltro ai "Add a health-check endpoint at /ping"
zeltro ai --interactive "Let's refactor the auth flow"
```

One-off is the default: the agent receives the prompt, does the work, and exits. Durable context lives in `AGENTS.md`, so each prompt stands alone.

| Flag | Description |
|---|---|
| `--interactive`, `-i` | Open a persistent session instead |
| `--one-off` | Accepted for compatibility (now the default) |

An unknown flag is an error rather than being added to the prompt.

## `zeltro resume`

```bash
zeltro resume my-project
```

Starts the project if it isn't running, then reopens the agent's most recent session in that project directory. If the agent can't resume, it starts a new session.

## Messaging other agent sessions

When the Zeltro app hosts agent sessions in several projects, on one host or several, they can message each other. Run these from inside your project directory:

```bash
zeltro peers                                   # live sessions, as project@host
zeltro send blog api@shop -- "API is on v2 now"
zeltro send --all -- "Shared Postgres restarting in 5 minutes"
cat notes.md | zeltro send blog -- -           # message from stdin
```

Every target must be live or nothing is sent. Messages are capped at 16 KB. An incoming message shows up in the terminal as `[Zeltro message from shop@shawn to blog, api] ...`. It comes from another agent, not from you.

In the Zeltro app, agents can also ask *you* things through the app's window instead of the chat: a multiple-choice question (`zeltro gui ask`), or an API key or password (`zeltro gui secret`), which goes straight into the project's `.env` so it never shows up in the conversation. See [the command reference](../commands/) for details.

---

## Notes for agents

If you *are* an agent working with Zeltro, read `/usr/local/share/zeltro-cli/AGENTS.md`. It's the condensed platform reference, kept deliberately short because every byte is paid for on each run.

The rules that matter most:

- **Never pass `--json-output`.** It suppresses all human-readable output including the success/failure distinction, so you can't tell whether a command worked. It exists only for external scripts and GUIs.
- **Always pass explicit arguments.** Nothing prompts; a missing required argument is a hard error with a usage hint.
- **Prefer `zeltro exec`** over the TTY variants (`zeltro bash`, `zeltro exec-tty*`). Those allocate a terminal and aren't automation-friendly.
- **`zeltro supervisor restart all`**, never `zeltro exec supervisorctl ...`.
- **`python3`, not `python`.** For Django, prefer `zeltro django manage <args>`.
