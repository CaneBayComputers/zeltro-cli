# Bash completion for the Zeltro CLI.
# Installed to /etc/bash_completion.d/zeltro by `zeltro configure` (and the
# platform installers). Provides:
#   - subcommand (verb) completion
#   - project-name completion for up/down/status/remove/setup/resume
#   - installer-name completion for install / update-installer
#   - framework/database/agent value completion
#   - per-command flag completion
#
# No dependency on the bash-completion package — we read COMP_WORDS directly.

# Only meaningful in bash with the `complete` builtin.
[ -n "$BASH_VERSION" ] || return 0

# List project directories (reads PROJECTS_DIR from the env file directly so we
# don't pay the cost of invoking `zeltro` on every TAB).
_zeltro_projects() {
    local dir=""
    if [ -f /etc/zeltro-cli/.env ]; then
        dir=$(grep -E '^[[:space:]]*PROJECTS_DIR=' /etc/zeltro-cli/.env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' ')
        dir="${dir/#\~/$HOME}"
    fi
    [ -z "$dir" ] && dir="$HOME/zeltro-projects"
    [ -d "$dir" ] && find -L "$dir" -maxdepth 1 -mindepth 1 -type d ! -name '.*' -printf '%f\n' 2>/dev/null
}

# List available installer slugs.
_zeltro_installers() {
    local d="/usr/local/share/zeltro-cli/src/installers"
    [ -d "$d" ] || return 0
    local f
    for f in "$d"/*.sh; do
        [ -e "$f" ] || continue
        basename "$f" .sh
    done
}

_zeltro() {
    local cur prev verb cword
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD
    verb="${COMP_WORDS[1]}"

    local verbs="ai ai-set ai-unattended art artisan bash cache-refresh clone composer configure create \
create-installer db-refresh disable disable-service django down down-all drush enable \
enable-service exec exec-root exec-tty exec-tty-root gui help install memcache memcache-flush \
memcache-stats mysql new node npm npx peers php phpcbf phpcs phpmd pip pip3 projects-dir \
python python3 redis redis-flush remove resume send set-metadata setup shell start-services \
status stop-services supervisor supervisor-status tinker uninstall up up-all update \
update-installer version wp"

    local frameworks="laravel kavera octobercms drupal wordpress php fastapi flask django python express nestjs fastify node nextjs nuxt sveltekit astro hono react vue"

    # First token after `zeltro` → the verb.
    if [ "$cword" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$verbs" -- "$cur") )
        return 0
    fi

    # Value completion for flags that take an argument.
    case "$prev" in
        --framework)
            COMPREPLY=( $(compgen -W "$frameworks" -- "$cur") ); return 0 ;;
        --database)
            COMPREPLY=( $(compgen -W "auto mysql postgres mongodb sqlite" -- "$cur") ); return 0 ;;
        --agent)
            COMPREPLY=( $(compgen -W "claude codex gemini qwen aider" -- "$cur") ); return 0 ;;
        --db-name|--version|--github-org|--model|--api-key|--git-name|--git-email|--projects-dir|--vpc-subnet|-f|--file|--prompt-file)
            return 0 ;;  # freeform value — nothing sensible to suggest
    esac

    # Per-verb completion.
    case "$verb" in
        up|down)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--json-output --no-colors --debug" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_zeltro_projects)" -- "$cur") )
            fi ;;
        gui)
            [[ $cword -eq 2 ]] && COMPREPLY=( $(compgen -W "ask secret notify open settings" -- "$cur") ) ;;
        up-all|down-all)
            COMPREPLY=( $(compgen -W "--json-output --no-colors --debug" -- "$cur") ) ;;
        status)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--all --running --json-output --no-colors --debug" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_zeltro_projects)" -- "$cur") )
            fi ;;
        remove)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--force-db-delete --preserve-database --force --json-output" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_zeltro_projects)" -- "$cur") )
            fi ;;
        resume)
            COMPREPLY=( $(compgen -W "$(_zeltro_projects)" -- "$cur") ) ;;
        setup)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--framework --db-name --overwrite-env --no-migration --no-storage-symlink --no-startup --overwrite-docker-compose --json-output --no-colors --debug" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_zeltro_projects)" -- "$cur") )
            fi ;;
        install)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--list --one-off" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_zeltro_installers)" -- "$cur") )
            fi ;;
        update-installer)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--all --one-off --print" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_zeltro_installers)" -- "$cur") )
            fi ;;
        new)
            # First positional = framework.
            if [ "$cword" -eq 2 ] && [[ "$cur" != -* ]]; then
                COMPREPLY=( $(compgen -W "$frameworks" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "--version --database --db-name --no-migration --github --github-org --public --private --no-storage-symlink --one-off --json-output --no-colors --debug" -- "$cur") )
            fi ;;
        clone)
            # First positional = mode (git-remote style).
            if [ "$cword" -eq 2 ] && [[ "$cur" != -* ]]; then
                COMPREPLY=( $(compgen -W "work-directly fork new-repo" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "--framework --database --db-name --overwrite-env --no-migration --overwrite-docker-compose --no-startup --github-org --public --private --no-storage-symlink --one-off --json-output --no-colors --debug" -- "$cur") )
            fi ;;
        create)
            COMPREPLY=( $(compgen -W "--one-off --classify-only -f --file --json-output" -- "$cur") ) ;;
        create-installer)
            COMPREPLY=( $(compgen -W "--one-off --print" -- "$cur") ) ;;
        ai)
            COMPREPLY=( $(compgen -W "--one-off" -- "$cur") ) ;;
        ai-set)
            COMPREPLY=( $(compgen -W "--agent --model --api-key --json-output" -- "$cur") ) ;;
        configure)
            COMPREPLY=( $(compgen -W "--git-name --git-email --projects-dir --vpc-subnet --json-output" -- "$cur") ) ;;
        django)
            [ "$cword" -eq 2 ] && COMPREPLY=( $(compgen -W "manage shell" -- "$cur") ) ;;
        update)
            COMPREPLY=( $(compgen -W "--full" -- "$cur") ) ;;
        uninstall)
            COMPREPLY=( $(compgen -W "--delete-images --json-output" -- "$cur") ) ;;
        *)
            # Unknown / freeform verb — offer global flags only.
            [[ "$cur" == -* ]] && COMPREPLY=( $(compgen -W "--json-output --no-colors --debug --help" -- "$cur") ) ;;
    esac

    return 0
}

complete -F _zeltro zeltro
