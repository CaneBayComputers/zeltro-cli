#!/bin/bash
# Kavera framework hooks
#
# Kavera is a Laravel-native website framework: flat-file Blade pages plus
# service-driven dynamic content (Blogger, Eventbrite, Flickr, form webhooks)
# cached through Redis. It is Laravel underneath, so every hook except the
# scaffold is inherited rather than duplicated.

# shellcheck source=/dev/null
source "$DEV_DIR/frameworks/laravel.sh"

KAVERA_REPO_TARBALL="https://github.com/CaneBayComputers/kavera/archive/refs/heads/master.tar.gz"

framework_scaffold() {
    echo-return; echo-cyan "Kavera project selected!"
    echo-white "Laravel-native website framework — flat-file pages, service-driven content."
    echo-return
    echo-cyan "Downloading Kavera ..."

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        if ! curl -sL "$KAVERA_REPO_TARBALL" | tar -xz --strip-components=1 > /dev/null 2>&1; then
            echo "{\"action\":\"new_project\",\"project_name\":\"$PROJECT_NAME\",\"framework\":\"kavera\",\"status\":\"error\",\"error\":\"download_failed\",\"details\":\"Failed to download Kavera\"}"
            exit 1
        fi
    else
        curl -L "$KAVERA_REPO_TARBALL" | tar -xz --strip-components=1
    fi

    # Ships resources/views as a symlink into resources/examples so the sample
    # site renders out of the box. A real project wants its own tree, or every
    # edit would land in the examples.
    if [ -L "resources/views" ]; then
        rm -f resources/views
        mkdir -p resources/views
        if [ -d "resources/examples" ]; then
            cp -a resources/examples/. resources/views/ 2>/dev/null || true
        fi
        mkdir -p resources/views/content resources/views/templates resources/views/emails resources/views/jsonld
        echo-green "Replaced the examples symlink with your own resources/views tree."
    fi

    echo-green "Kavera project structure created!"
}

framework_run_migrations() {
    # Laravel migrations first, then refresh Kavera's content registry — routes
    # only resolve for pages listed in it, so a fresh checkout serves 404s
    # until this runs.
    [ ! -f "artisan" ] && return

    # Both paths used `migrate --force || true` and then announced "Kavera is
    # ready" whatever happened. Report a failure instead of hiding it.
    local _mig_ok=0
    if [ "${MIGRATE_SAFE:-0}" = "1" ]; then
        echo-cyan 'Applying pending migrations (artisan migrate) ...'; echo-white
    else
        echo-cyan 'Running migrations ...'; echo-white
    fi
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        art-docker migrate --force > /dev/null 2>&1 && _mig_ok=1
    else
        art-docker migrate --force && _mig_ok=1
    fi
    if [ "$_mig_ok" != "1" ]; then
        echo-red "Migrations FAILED -- see the output above. The project is up; fix the"
        echo-red "cause, then run: zeltro art migrate"
        echo-yellow "Common cause: the .env DB_HOST/DB_DATABASE do not match Zeltro's shared services"
        echo-yellow "(re-run setup with --overwrite-env to point them there)."; echo-white
    fi

    echo-cyan 'Building Kavera content registry ...'; echo-white
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        art-docker app:update-content-list > /dev/null 2>&1 || true
    else
        art-docker app:update-content-list || true
    fi
    if [ "$_mig_ok" = "1" ]; then
        echo-green 'Kavera is ready. Pages live in resources/views/content.'; echo-white
    else
        echo-yellow 'Kavera is running, but finish the migrations above before relying on it.'; echo-white
    fi
}
