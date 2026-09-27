#!/bin/bash

set -e

CALLER_DIR=$(pwd)

cd "$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
cd ..

DEV_DIR=$(pwd)

# Run standard pre-checks (loads /etc/zeltro-cli/.env, validates projects dir, etc.)
source scripts/pre_check.sh

usage() {
    echo-white "Usage: zeltro create-installer \"<plain English description>\""
    echo-white ""
    echo-white "Launches the configured AI agent with a pre-built prompt that instructs"
    echo-white "it to identify the OSS project from your description, write a new"
    echo-white "installer at src/installers/<slug>.sh and a hint file at"
    echo-white "src/project-hints/<slug>.md, then verify the installer end-to-end."
    echo-white ""
    echo-white "Example:"
    echo-white "  zeltro create-installer \"Laravel October CMS\""
    echo-white "  zeltro create-installer \"the open source community forum Discourse\""
    echo-white ""
    echo-white "Options:"
    echo-white "  --one-off      Non-interactive single-shot run (no follow-up turns)"
    echo-white "  --print        Print the prompt to stdout and exit (don't invoke an agent)"
    echo-white "  -h, --help     Show this help"
}

ONE_OFF=0
PRINT_ONLY=0
DESCRIPTION_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --one-off)  ONE_OFF=1 ;;
        --print)    PRINT_ONLY=1 ;;
        -h|--help)  usage; exit 0 ;;
        --*)        echo-red "Unknown option: $1"; usage; exit 1 ;;
        *)          DESCRIPTION_ARGS+=("$1") ;;
    esac
    shift
done

DESCRIPTION="${DESCRIPTION_ARGS[*]}"

if [[ -z "$DESCRIPTION" ]]; then
    echo-red "Missing description."
    usage
    exit 1
fi

# Detect reachable remote test machines.
REMOTES=""
for host in cami cassie; do
    if ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
           "$host@$host" "true" >/dev/null 2>&1; then
        REMOTES="${REMOTES}${REMOTES:+, }$host"
    fi
done

INSTALL_DIR="/usr/local/share/zeltro-cli"

if [[ -n "$REMOTES" ]]; then
    REMOTES_LINE="Remote test machines reachable via SSH: $REMOTES. Connect as \`ssh <name>@<name>\`. Their zeltro-cli checkouts live at /usr/local/share/zeltro-cli (\`sudo git -C /usr/local/share/zeltro-cli pull\` to refresh). Use these for additional verification once you've validated locally."
else
    REMOTES_LINE="No remote test machines are reachable from this host right now. Verify on the local machine only."
fi

# `read -r -d ''` rather than `PROMPT=$(cat <<EOF ... EOF)`.
#
# bash 3.2 — what macOS ships — cannot parse a command substitution wrapping
# a heredoc when the heredoc contains backticks and parentheses: its parser
# scans for the closing paren and gets lost inside the text, failing the
# whole file with "syntax error near unexpected token `)'". bash 5 parses it
# fine, so `bash -n` on Linux reported nothing and this command was simply
# dead on every Mac.
#
# `read` takes the heredoc directly, with no substitution to parse. The
# `|| true` is required: read returns non-zero when it hits EOF without the
# delimiter, which is always here, and set -e would abort on it.
read -r -d '' PROMPT <<EOF || true
You are working on the zeltro-cli repository at $INSTALL_DIR.

# Goal
Create a brand-new Zeltro installer for the open-source project the user described as:

  "$DESCRIPTION"

You will need to (1) figure out exactly which OSS project this refers to, (2) write the installer + hint file, and (3) verify that \`zeltro install <slug>\` deploys it cleanly end-to-end.

# Required reading (do this first)
1. $INSTALL_DIR/AGENTS.md — read in full. The sections that govern this work:
   - "Installer Maintenance Strategy" (the lifecycle this installer becomes part of)
   - "Project Hints Library" (rules for what belongs in the hint file)
   - "Complex Compose Adaptation" + "Upstream compose preservation"
   - "VPC Networking & IP Allocation" (so your compose fits the .2-.8 / .32-.63 / .100-.250 partitioning)
   - "cbc Base Docker Images" (you will likely **not** use these — installers typically pull upstream images directly — but you should know they exist)
   - "Design Context: What Zeltro Optimizes For" (especially: shared services replace bundled ones)
2. Several existing installers in $INSTALL_DIR/src/installers/ as references. Pick 2-3 that are structurally similar to what you're about to write (e.g. if your target uses PostgreSQL + Redis, look at \`paperless-ngx.sh\`, \`outline.sh\`, \`hedgedoc.sh\`; if it ships its own bundled stack with multiple services, look at \`mastodon.sh\`, \`zulip.sh\`, \`plane.sh\`, \`dify.sh\`).
3. The matching hint files in $INSTALL_DIR/src/project-hints/ for those installers.

# Process
1. **Identify the project.** From the description "$DESCRIPTION", determine the canonical project name, official repository, official docker image(s), and current stable release. If genuinely ambiguous, pick the most likely candidate, state your reasoning, and proceed — don't stall asking for clarification.
2. **Pick a slug.** Lowercase hyphenated (e.g. \`october-cms\`, \`discourse\`). The slug becomes the filename, the project URL (\`http://<slug>/\`), and the database name (with hyphens converted to underscores).
3. **Read upstream's reference docker-compose / install docs.** Note: required services, env vars, secret-generation steps, ports, volumes, init/migration steps. Plan how to slot it into Zeltro:
   - Replace bundled \`postgres\`/\`mysql\`/\`mariadb\`/\`redis\`/\`mongo\`/\`memcached\` services with the shared Zeltro hostnames (\`zeltro-postgres\` / \`zeltro-mariadb\` / \`zeltro-redis\` / \`zeltro-mongo\` / \`zeltro-memcached\`). Credentials are documented in AGENTS.md "Shared Service Credentials".
   - Name the user-facing entry-point service so \`setup_project.sh\`'s web-service detection regex matches: one of \`nginx\`, \`web\`, \`app\`, \`api\`, \`server\`, \`frontend\`, \`backend\`, \`http\`. Setup will assign it the project's static IP and \`container_name\`.
   - If the upstream image's bundled HTTP listener can't be reconfigured to expose what we want on port 80, put a small \`nginx:alpine\` reverse proxy in front of it (see \`zulip.sh\`, \`mastodon.sh\` for reference patterns).
   - Helper services (workers, schedulers, sidekiq, etc.) get attached to the default network without static IPs — they'll land in .32-.63 dynamic range.
4. **Write the installer** at $INSTALL_DIR/src/installers/<slug>.sh with the standard format:
   \`\`\`bash
   INSTALL_DISPLAY="<Pretty Name>"
   INSTALL_CREDENTIALS="<initial login or 'register at first visit'>"
   INSTALL_NOTES="<one-line gotcha worth surfacing in the install output, or empty>"

   # Optional: pre_install() runs before write_files(). Use for DB creation,
   # secret generation that needs the DB up, etc. If you generate secrets via
   # \`openssl rand -hex\`, do that inside write_files() unless you specifically
   # need the DB available.
   pre_install() {
       # ... e.g. create a dedicated DB:
       # docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \\\\\"<slug>\\\\\";" 2>/dev/null || true
       :
   }

   # Required: write_files() runs in the project directory. Generate secrets,
   # write docker-compose.yaml, .env, nginx.conf, anything else needed.
   write_files() {
       cat > docker-compose.yaml << COMPOSE
   services:
     # ... your services here ...
   COMPOSE
   }
   \`\`\`
   - Pin every image to a specific recent tag (e.g. \`ghcr.io/foo/bar:v2.7.0\`, not \`:latest\`). Future bumps must be intentional events.
   - Generate any required secrets/keys via \`openssl rand -hex 32\` (or whatever the upstream expects).
5. **Write the hint file** at $INSTALL_DIR/src/project-hints/<slug>.md following the format used by neighboring hint files. Sections: brief description line(s), \`**Image**\` / \`**Port**\` / \`**Database**\` / \`**Credentials**\`, then \`## Key Notes\` with non-obvious gotchas only. End with the line: "The installer exists: run \`zeltro install <slug>\`." Keep it short — only things an agent would reliably get wrong without guidance.

# Verification (mandatory before commit)
1. \`zeltro install <slug>\` on this machine. Must succeed.
2. \`zeltro status <slug>\` must show RUNNING. \`curl -sI http://<slug>/\` (or the documented entry path) must return a sane status code (200/301/302/401/403 are all acceptable; 502/000 are failures).
3. If the upstream app needs first-run setup at a specific URL, confirm that URL responds (e.g. \`/install\`, \`/register\`, \`/setup\`).
4. $REMOTES_LINE
5. \`zeltro remove <slug> --force-db-delete\` afterwards on every machine you tested on, so the installer can be tested again from scratch.

# Constraints
- Don't commit \`:latest\` tags — pin everything.
- Don't commit an installer that hasn't completed end-to-end verification.
- If the project genuinely doesn't fit Zeltro (Kubernetes-only, requires kernel modules, demands a real domain + TLS to function at all), say so in your final message and **don't** commit a half-baked installer. Document why in the closing message so the user knows.
- Once verified, commit with a clear message naming the slug and key facts (e.g. \`Add octobercms installer (PHP 8.2, MariaDB, port 80)\`). Push to origin/master.
- Update the README.md install list if there's a curated list of supported apps there. Check first.
- If \`set -e\` aborts mid-run because of \`tput\` (no TTY) or \`trash-put\` (collision), see AGENTS.md "Shell Script Gotchas" for the established workarounds — don't disable \`set -e\`.

Begin by stating your interpretation of "$DESCRIPTION" (which project, why, what slug you'll use), then proceed.
EOF

if [[ "$PRINT_ONLY" == "1" ]]; then
    printf "%s\n" "$PROMPT"
    exit 0
fi

# Verify AI agent is configured.
AI_AGENT_CLI_NAME="$AI_AGENT"
if ! _ai_problem=$(zeltro_ai_agent_problem); then
    echo-red "$_ai_problem" >&2
    exit 1
fi

cd "$DEV_DIR"

case "$AI_AGENT_CLI_NAME" in
    codex)
        codex_args=()
        [[ -n "$AI_MODEL" ]] && codex_args+=("--model" "$AI_MODEL")
        _export_agent_key OPENAI_API_KEY "sk-"
        _export_agent_base OPENAI_BASE_URL
        codex_args+=(--dangerously-bypass-approvals-and-sandbox)
        if [[ "$ONE_OFF" == "1" ]]; then
            codex exec "${codex_args[@]}" "$PROMPT"
        else
            codex "${codex_args[@]}" "$PROMPT"
        fi
        ;;
    claude)
        claude_args=(--dangerously-skip-permissions)
        [[ "$ONE_OFF" == "1" ]] && claude_args+=(-p)
        [[ -n "$AI_MODEL" ]] && claude_args+=("--model" "$AI_MODEL")
        _export_agent_key ANTHROPIC_API_KEY "sk-ant-"
        _export_agent_base ANTHROPIC_BASE_URL
        claude_args+=("$PROMPT")
        claude "${claude_args[@]}"
        ;;
    qwen)
        _export_agent_key OPENAI_API_KEY ""
        _export_agent_base OPENAI_BASE_URL
        export QWEN_CODE_SUPPRESS_YOLO_WARNING=1
        qwen_args=(--yolo --auth-type openai)
        [[ -n "$AI_MODEL" ]] && qwen_args+=("--model" "$AI_MODEL")
        if [[ "$ONE_OFF" == "1" ]]; then
            qwen "${qwen_args[@]}" --prompt "$PROMPT"
        else
            qwen "${qwen_args[@]}" -i "$PROMPT"
        fi
        ;;
    gemini)
        gemini_args=(--yolo --skip-trust)
        [[ -n "$AI_MODEL" ]] && gemini_args+=("--model" "$AI_MODEL")
        gemini_args+=(--include-directories "$DEV_DIR")
        if [[ "$ONE_OFF" == "1" ]]; then
            gemini_args+=(--output-format text --prompt "$PROMPT")
        else
            gemini_args+=("-i" "$PROMPT")
        fi
        gemini "${gemini_args[@]}"
        ;;
    aider)
        build_aider_args
        if [[ "$ONE_OFF" == "1" ]]; then
            aider "${AIDER_ARGS[@]}" --message "$PROMPT"
        else
            write_aider_seed_file "$PROMPT"
            aider "${AIDER_ARGS[@]}" --load "$AIDER_SEED_FILE"
            rm -f "$AIDER_SEED_FILE"
        fi
        ;;
    *)
        echo-red "Unsupported AI agent: '$AI_AGENT_CLI_NAME'."
        echo-white "Supported agents: codex, claude, gemini, aider"
        exit 1
        ;;
esac

cd "$CALLER_DIR"
