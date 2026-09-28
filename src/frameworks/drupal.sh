#!/bin/bash
# Drupal framework hooks
#
# Drupal ships as a Composer project (drupal/recommended-project), so the
# scaffold only writes composer.json — `composer install` runs later, inside the
# container, via setup_project's dependency step. Same shape as Laravel.
#
# THE DOCROOT. Drupal's convention is `web/`, and Zeltro's nginx always serves
# /usr/share/nginx/html/public: a project with a public/ dir is mounted at html
# (so project/public lands on the docroot), one without is mounted straight into
# html/public. `web/` fits neither.
#
# Rather than add a third mount case to setup_project, this relocates Drupal's
# docroot to public/ at scaffold time. That is a supported, first-class Composer
# setting — every path below is the stock recommended-project layout with web/
# swapped for public/ — and it makes Drupal indistinguishable from Laravel as far
# as the rest of Zeltro is concerned. Nothing in the container or compose
# templates needs to know Drupal exists.

FRAMEWORK_IS_PYTHON=0
FRAMEWORK_DOCKER_TEMPLATE="project"

DRUPAL_CORE_CONSTRAINT="${DRUPAL_CORE_CONSTRAINT:-^11}"
DRUPAL_ADMIN_USER="${DRUPAL_ADMIN_USER:-admin}"
DRUPAL_ADMIN_PASS="${DRUPAL_ADMIN_PASS:-admin}"

framework_scaffold() {
    echo-return; echo-cyan "Drupal project selected!"
    echo-white "Composer-managed. Core and contrib modules install into public/."
    echo-return

    # Written rather than downloaded so the docroot relocation is guaranteed
    # rather than patched in afterwards with sed.
    #
    # allow-plugins matters more than it looks: Composer 2.2+ blocks plugins by
    # default, and a blocked plugin aborts the install outright — leaving a
    # populated vendor/ and a docroot with no index.php, which reads as a broken
    # install rather than a config issue.
    #
    # The list must cover every composer-plugin in the RESOLVED tree, not just
    # Drupal's own. symfony/runtime is the easy one to miss: nothing in the
    # require block names it, it arrives transitively through drush, and omitting
    # it failed the first real `zeltro new drupal` here. If a future dependency
    # adds another plugin, find it with:
    #   python3 -c "import json;print([p['name'] for p in
    #     json.load(open('composer.lock'))['packages'] if p.get('type')=='composer-plugin'])"
    cat > composer.json << 'COMPOSEREOF'
{
    "name": "zeltro/drupal-project",
    "description": "Drupal project managed by Zeltro",
    "type": "project",
    "license": "GPL-2.0-or-later",
    "require": {
        "composer/installers": "^2.3",
        "drupal/core-composer-scaffold": "^11",
        "drupal/core-project-message": "^11",
        "drupal/core-recommended": "^11",
        "drush/drush": "^13"
    },
    "conflict": {
        "drupal/drupal": "*"
    },
    "minimum-stability": "stable",
    "prefer-stable": true,
    "config": {
        "allow-plugins": {
            "composer/installers": true,
            "drupal/core-composer-scaffold": true,
            "drupal/core-project-message": true,
            "symfony/runtime": true,
            "dealerdirect/phpcodesniffer-composer-installer": true,
            "php-http/discovery": true,
            "phpstan/extension-installer": true
        },
        "sort-packages": true
    },
    "extra": {
        "drupal-scaffold": {
            "locations": {
                "web-root": "public/"
            }
        },
        "installer-paths": {
            "public/core": ["type:drupal-core"],
            "public/libraries/{$name}": ["type:drupal-library"],
            "public/modules/contrib/{$name}": ["type:drupal-module"],
            "public/profiles/contrib/{$name}": ["type:drupal-profile"],
            "public/themes/contrib/{$name}": ["type:drupal-theme"],
            "drush/Commands/contrib/{$name}": ["type:drupal-drush"],
            "public/modules/custom/{$name}": ["type:drupal-custom-module"],
            "public/profiles/custom/{$name}": ["type:drupal-custom-profile"],
            "public/themes/custom/{$name}": ["type:drupal-custom-theme"]
        }
    }
}
COMPOSEREOF

    if [ "$DRUPAL_CORE_CONSTRAINT" != "^11" ]; then
        zeltro-sed "s|\"\\^11\"|\"$DRUPAL_CORE_CONSTRAINT\"|g" composer.json
    fi

    mkdir -p public/sites/default

    if [[ "$JSON_OUTPUT" == "1" ]]; then
        git init > /dev/null 2>&1
        git add . > /dev/null 2>&1
        git commit -m "Initial Drupal project setup" > /dev/null 2>&1
    else
        git init; git add .; git commit -m "Initial Drupal project setup"
    fi

    echo-green "Drupal project scaffolded — core installs on the next step."
}

framework_python_start_command() { echo ""; }

# Drupal has no .env. Connection settings live in settings.php, which
# `drush site:install` generates from the --db-url passed in
# framework_run_migrations, so there is nothing to write here.
framework_setup_env() {
    mkdir -p public/sites/default/files
    chmod -R 777 public/sites/default 2>/dev/null || true
    return 0
}

# Build the DSN drush wants for the shared service backing this project.
_drupal_db_url() {
    case "$DATABASE_ENGINE" in
        postgres|postgresql|pgsql)
            echo "pgsql://root:password@${POSTGRES_CONTAINER_NAME}:5432/${DB_NAME}" ;;
        sqlite|sqlite3)
            echo "sqlite://sites/default/files/.ht.sqlite" ;;
        *)
            # Shared MariaDB runs with an empty root password; the trailing colon
            # is required or drush reads the host as the password.
            echo "mysql://root:@${MARIADB_CONTAINER_NAME}:3306/${DB_NAME}" ;;
    esac
}

framework_run_migrations() {
    [ ! -f "composer.json" ] && return
    if [ ! -f "vendor/bin/drush" ]; then
        echo-yellow "drush not found in vendor/ — skipping site install."
        echo-white "Run 'zeltro composer install' then 'zeltro drush site:install' by hand."
        return
    fi

    # Drupal has no migrations in the Laravel sense — the equivalent first step
    # is site:install, which creates the schema, writes settings.php and makes
    # the admin account. Skip it when the site is already installed, so re-running
    # setup on an existing project does not wipe its content.
    if [ -f "public/sites/default/settings.php" ] && \
       grep -q "databases\['default'\]" public/sites/default/settings.php 2>/dev/null; then
        echo-cyan "Drupal is already installed — leaving the existing site alone."
        echo-white "Re-install from scratch with:"
        echo-white "  zeltro drush site:install --existing-config -y"
        return
    fi

    local db_url; db_url="$(_drupal_db_url)"

    echo-cyan "Installing Drupal (drush site:install) ..."; echo-white
    local install_ok=1
    if [[ "$JSON_OUTPUT" == "1" ]]; then
        drush-docker site:install standard \
            --db-url="$db_url" --site-name="$PROJECT_NAME" \
            --account-name="$DRUPAL_ADMIN_USER" --account-pass="$DRUPAL_ADMIN_PASS" \
            -y > /dev/null 2>&1 || install_ok=0
    else
        drush-docker site:install standard \
            --db-url="$db_url" --site-name="$PROJECT_NAME" \
            --account-name="$DRUPAL_ADMIN_USER" --account-pass="$DRUPAL_ADMIN_PASS" \
            -y || install_ok=0
    fi

    # Check the outcome rather than the exit code alone. This was `|| true`, which
    # meant a failed install reported success and left the user at Drupal's web
    # installer with a site Zeltro claimed was ready — the exact thing that hid
    # the drush invocation bug on the first real run. settings.php is the
    # artifact site:install writes last, so its absence is the reliable signal.
    if [ "$install_ok" = "0" ] || [ ! -f "public/sites/default/settings.php" ]; then
        echo-return
        echo-red "drush site:install did not complete."
        echo-white "Composer finished, so the codebase is fine — this is the install step."
        echo-white "The site will show Drupal's web installer until it succeeds. Retry with:"
        echo-white "  cd $PROJECTS_DIR_PATH/$PROJECT_NAME"
        echo-white "  zeltro drush site:install standard --db-url=$db_url -y"
        return 1
    fi

    # site:install locks the settings file down, so appending needs it writable
    # again. Without trusted_host_patterns Drupal logs a warning on every request
    # and the status report shows an error, which reads as a broken install.
    if [ -f "public/sites/default/settings.php" ]; then
        chmod u+w public/sites/default public/sites/default/settings.php 2>/dev/null || true
        # Match an ACTIVE assignment, not the string. Drupal's stock settings.php
        # documents trusted_host_patterns in six comment lines, so a plain
        # `grep -q trusted_host_patterns` always matches and this block would
        # never run — the setting would silently never be applied.
        if ! grep -qE "^[[:space:]]*\\\$settings\['trusted_host_patterns'\]" public/sites/default/settings.php 2>/dev/null; then
            cat >> public/sites/default/settings.php << EOF

/**
 * Added by Zeltro. The browser reaches this project by IP address (the
 * container IP, or the machine's LAN IP with the project's port), or as
 * localhost on macOS/Windows, so allow any IPv4 literal rather than one
 * address that changes if the project is recreated. The project name stays
 * for container-to-container requests.
 */
\$settings['trusted_host_patterns'] = [
  '^${PROJECT_NAME//./\\.}\$',
  '^localhost\$',
  '^\\d{1,3}(\\.\\d{1,3}){3}\$',
];
EOF
        fi
    fi

    # Zeltro does not write /etc/hosts, so http://<project>/ does not resolve
    # from the host. Print the address that does.
    local site_url
    site_url="$(zeltro_project_url "$PROJECT_NAME")"
    [ -n "$site_url" ] || site_url="<address from 'zeltro status $PROJECT_NAME'>"

    echo-green "Drupal installed."; echo-white
    echo-white "  Site:  $site_url/"
    echo-white "  Admin: $site_url/user/login  ($DRUPAL_ADMIN_USER / $DRUPAL_ADMIN_PASS)"
    echo-white "  Change the password with: zeltro drush user:password $DRUPAL_ADMIN_USER '<new>'"
}

framework_setup_gitignore() {
    [ -f ".gitignore" ] && grep -q "docker-compose.yaml" .gitignore && return

    cat > .gitignore << 'GITEOF'
# Docker infrastructure
docker-compose.yaml

# Composer dependencies and scaffolded core
/vendor/
/public/core/
/public/modules/contrib/
/public/themes/contrib/
/public/profiles/contrib/
/public/libraries/
/drush/Commands/contrib/

# Drupal scaffold files (regenerated by composer)
/public/index.php
/public/update.php
/public/.htaccess
/public/robots.txt
/public/web.config
/public/sites/default/default.settings.php
/public/sites/default/default.services.yml

# Site-specific settings and uploads
/public/sites/*/settings.php
/public/sites/*/settings.local.php
/public/sites/*/services.yml
/public/sites/*/files/

# IDE and OS
.vscode/
.idea/
*.swp
.DS_Store
GITEOF

    echo-green ".gitignore created for Drupal project!"
}
