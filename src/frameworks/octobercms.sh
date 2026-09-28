#!/bin/bash
# October CMS framework hooks
#
# October CMS is a Laravel-based CMS you BUILD sites in — themes, plugins and
# page templates live in the project's source tree, so it belongs with the
# frameworks rather than the ready-to-run app installers.
#
# It shipped as an installer previously, but the only image upstream publishes
# bundles its own MariaDB internally and ignores external DB env, so a project
# could never use Zeltro's shared services. Installing from source fixes that.
#
# Laravel underneath, so everything except the scaffold and migrations is
# inherited.

# shellcheck source=/dev/null
source "$DEV_DIR/frameworks/laravel.sh"

OCTOBER_VERSION="${OCTOBER_VERSION:-v4.4.8}"

framework_scaffold() {
    echo-return; echo-cyan "October CMS project selected!"
    echo-white "Laravel-based CMS — themes and plugins live in this project's source tree."
    echo-return
    echo-cyan "Downloading October CMS ${OCTOBER_VERSION} ..."

    local url="https://github.com/octobercms/october/archive/refs/tags/${OCTOBER_VERSION}.tar.gz"
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        if ! curl -sL "$url" | tar -xz --strip-components=1 > /dev/null 2>&1; then
            echo "{\"action\":\"new_project\",\"project_name\":\"$PROJECT_NAME\",\"framework\":\"octobercms\",\"status\":\"error\",\"error\":\"download_failed\",\"details\":\"Failed to download October CMS ${OCTOBER_VERSION}\"}"
            exit 1
        fi
    else
        curl -L "$url" | tar -xz --strip-components=1
    fi

    echo-green "October CMS project structure created!"
    echo-white "Note: October CMS is free for local development; production use requires a"
    echo-white "license from octobercms.com."
}

framework_run_migrations() {
    [ ! -f "artisan" ] && return

    # October wraps Laravel's migrator with october:migrate, which also installs
    # plugin tables. Fall back to plain migrate if the command isn't registered
    # (older releases, or a partially installed tree).
    echo-cyan 'Running October CMS migrations ...'; echo-white
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        art-docker october:migrate > /dev/null 2>&1 || art-docker migrate --force > /dev/null 2>&1 || true
    else
        art-docker october:migrate || art-docker migrate --force || true
    fi

    # october:migrate does NOT create Tailor blueprint tables. The stock demo
    # theme defines blueprints (Blog\Post, Page\Article, ...), each stored in a
    # hash-named xc_* table, so without this the homepage throws
    # "Base table or view not found: xc_<hash>" and the site is a 500 even though
    # every migration reports as applied.
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        art-docker tailor:migrate > /dev/null 2>&1 || true
    else
        art-docker tailor:migrate || true
    fi
    echo-green 'Migrations complete.'; echo-white
    # Zeltro does not write /etc/hosts, so http://<project>/ does not resolve
    # from the host. Print the address that does.
    local site_url
    site_url="$(zeltro_project_url "$PROJECT_NAME")"
    [ -n "$site_url" ] || site_url="<address from 'zeltro status $PROJECT_NAME'>"
    # The backend path is BACKEND_URI (October ships /admin); /backend is a 404.
    local backend_uri
    backend_uri="$(grep -E '^BACKEND_URI=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d "\"' ")"
    backend_uri="/${backend_uri#/}"
    [ "$backend_uri" = "/" ] && backend_uri="/admin"
    echo-white "Backend is at $site_url$backend_uri — create the admin user with:"
    echo-white "  zeltro art october:passwd <email> <password>"
}
