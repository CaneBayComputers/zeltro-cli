---
title: Cheap and local models
nav_order: 8
---

# Cheap and local models

Zeltro doesn't sell you AI. It runs whichever agent you point it at, against
whichever model you want, including models running on your own machine.

The default agents bill at frontier-model prices. For a lot of Zeltro work
(scaffolding, wiring config, routine edits) a much cheaper model is fine, and the
difference is large:

| Model | Input / Output per 1M tokens |
|---|---|
| Claude Sonnet 5 (Anthropic API) | $2 / $10 |
| Qwen3 Coder Next (OpenRouter) | **~$0.12 / ~$0.80** |
| Qwen3 Coder 30B A3B Instruct (OpenRouter) | **~$0.07 / ~$0.28** |
| Any model on local Ollama | **nothing per token** (your hardware and power) |

Prices as of September 2026; OpenRouter prices move, so check the model's page
before you rely on them. In a test in August 2026, Qwen Code with
`qwen/qwen3-coder-30b-a3b-instruct` built a working Django app end to end for
**$0.87**.

Zeltro already saves tokens before the model is involved: the environment,
networking, database and container plumbing are pre-built, so the agent spends
its context on your app instead of deriving Docker setup. Switching models
compounds that saving rather than replacing it.

---

## How it works

```bash
zeltro ai-set --agent <agent> --model <model> --api-base <url> --api-key <key>
```

`--api-base` is the important one. Zeltro hands it to the agent through whichever
setting that CLI reads:

| Agent | Endpoint passed as | Key passed as | Endpoint it expects |
|---|---|---|---|
| `qwen` | `OPENAI_BASE_URL` | `OPENAI_API_KEY` | OpenAI-compatible |
| `aider` | `--openai-api-base` | `--api-key <provider>=<key>` | OpenAI-compatible |
| `claude` | `ANTHROPIC_BASE_URL` | `ANTHROPIC_API_KEY`, only if it starts with `sk-ant-` | **Anthropic-compatible** |
| `codex` | `OPENAI_BASE_URL`, which current Codex ignores (see below) | `OPENAI_API_KEY`, only if it starts with `sk-` | OpenAI Responses API |
| `gemini` | nothing | nothing | Its own Google sign-in, or a `GEMINI_API_KEY` you export |

"OpenAI-compatible" covers OpenRouter, DeepInfra, Together, Fireworks, Ollama,
LM Studio and vLLM, so `qwen` and `aider` are the agents to use with cheap or local
models.

For one run with a different model, without touching the global setting, use the
[per-session overrides](../ai-workflow/#per-session-overrides) (`ZELTRO_AI_AGENT`,
`ZELTRO_AI_MODEL`, `ZELTRO_AI_API_BASE`, `ZELTRO_AI_API_KEY_FILE`). In the Zeltro app,
an AI profile does the same.

---

## OpenRouter (cheapest hosted)

```bash
zeltro ai-set --agent qwen \
  --model qwen/qwen3-coder-30b-a3b-instruct \
  --api-base https://openrouter.ai/api/v1 \
  --api-key sk-or-v1-...
```

Pay-as-you-go, no subscription. `qwen/qwen3-coder-next` is a newer, larger Qwen
coding model for two to three times the price. With Aider, use OpenRouter's own
prefix and no endpoint:
`--agent aider --model openrouter/qwen/qwen3-coder-30b-a3b-instruct --api-key sk-or-v1-...`.

## Ollama (local, private)

Install [Ollama](https://ollama.com), pull a coding model, point Zeltro at it:

```bash
ollama pull qwen3-coder:30b

zeltro ai-set --agent qwen \
  --model qwen3-coder:30b \
  --api-base http://localhost:11434/v1 \
  --api-key ollama
```

The key is a placeholder. Ollama ignores it, but the CLIs expect something.

Nothing leaves your machine, which matters for client work under NDA.

Raise Ollama's context length before you start. Its default depends on your VRAM
and is only 4k tokens under 24 GB, which is far too short for an agent. Ollama
recommends at least 64k for coding tools: start the server with
`OLLAMA_CONTEXT_LENGTH=64000 ollama serve`, or use the slider in the Ollama app's
settings. More context needs more VRAM.

**Model size matters more than you would like**, and this is measured rather
than assumed. Tested here against `qwen2.5-coder:1.5b`, `zeltro create
--classify-only` returned *valid, correctly shaped JSON* (the plumbing is fine)
but recommended a **budgeting app for a guitar pedal tracker**, with the reason
"Laravel is great for building budgeting apps". Coherent output, incoherent
thinking.

So small models fail in the worst way: they succeed mechanically and are wrong
on the substance. A ~30B model on 24 GB of VRAM is roughly the floor for agentic
work (`qwen3-coder:30b` is a 19 GB download); below that, expect plausible nonsense
rather than errors.

Qwen Code also requires **Node 22 or newer**. It installs and runs on Node 20
(npm warns `EBADENGINE` and it works anyway), but that is unsupported.

## LM Studio or vLLM

Both expose an OpenAI-compatible server, so the shape is identical. LM Studio
listens on port 1234; vLLM defaults to 8000:

```bash
zeltro ai-set --agent qwen --model <model> \
  --api-base http://localhost:1234/v1 --api-key local
```

## Codex against another endpoint

Current Codex CLI no longer reads `OPENAI_BASE_URL`, so `zeltro ai-set --agent codex
--api-base ...` has no effect: Codex still talks to OpenAI. Codex also only speaks
OpenAI's Responses API, which not every compatible server implements. To point it
elsewhere, configure Codex itself in `~/.codex/config.toml`: set `openai_base_url`,
or add a `[model_providers]` entry. For Ollama or LM Studio, Codex has its own
`--oss` mode (`oss_provider` in the same file). See
[Codex's advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).
For cheap or local models, `qwen` or `aider` is less work.

## Claude Code against a local model

Claude Code speaks Anthropic's API, not OpenAI's. Ollama 0.14 and later also speak
Anthropic's API, so Claude Code can use an Ollama model directly:

```bash
zeltro ai-set --agent claude --model qwen3-coder:30b \
  --api-base http://localhost:11434
```

Note the URL has no `/v1`. Leave `--api-key` empty: Ollama ignores the key, and
Zeltro only passes keys that start with `sk-ant-`. If Claude Code asks you to log
in, `export ANTHROPIC_AUTH_TOKEN=ollama` in your shell first, as
[Ollama's guide](https://docs.ollama.com/integrations/claude-code) does.

For a server that only speaks OpenAI's API, put a translating proxy such as
[LiteLLM](https://github.com/BerriAI/litellm) in front and pass its address as
`--api-base`.

Worth it only if you specifically want Claude Code's interface over a local
model. Otherwise `qwen` is less machinery.

---

## Going back

```bash
zeltro ai-set --agent claude --api-base none --api-key ""
```

`none` clears the endpoint; an empty `--api-key` clears a stored key. Switching
agents also clears the stored model, so this returns you to Claude Code's own
default model. Check where you stand with `zeltro ai-set --json-output`.

---

## Choosing honestly

Cheaper models are genuinely worse at long autonomous work. The realistic split:

- **Routine edits, scaffolding, config, boilerplate.** A cheap or local model is
  fine and the savings are real.
- **`zeltro create` building a whole app from a sentence, or debugging something
  subtle.** Frontier models still earn their price.

Nothing stops you switching per task. `zeltro ai-set` takes a second and changes the
global default; the `ZELTRO_AI_*` variables change it for a single run.
