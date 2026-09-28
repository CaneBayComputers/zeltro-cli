---
title: App library
nav_order: 6
---

# App library — `zeltro install`

`zeltro install <app> [name]` deploys a **finished third-party app**, fully configured and running, usually in under two minutes. Open it at the address `zeltro status <app>` prints.

```bash
zeltro install grafana       # monitoring dashboards
zeltro install gitea         # self-hosted git
zeltro install n8n           # workflow automation
zeltro install nextcloud     # file hosting
zeltro install --list        # everything available
```

For scaffolding a project *you write*, see [Frameworks](../frameworks/) instead. Guess wrong and Zeltro points you at the right command.

---

## What an installer does for you

Each installer captures one app's quirks once, so you (or your agent) never re-derive them:

- Creates the app's database on the shared service, plus a dedicated database user when the app refuses to run as root
- Generates secrets and app keys
- Writes a compose file wired to Zeltro's shared services instead of bundled databases
- Gives the app a static IP on Zeltro's network and a container name other containers can reach it by
- Starts the container and waits until it answers over HTTP

Newer installers **pin image tags to specific versions**, not `:latest`, so an install that worked yesterday works the same today and upgrades are deliberate. Some older installers still use floating tags; see [Available apps](#available-apps).

## Options

| Option | Description |
|---|---|
| `[name]` | Install under a different project name / hostname |
| `--image <ref>` | Override the image the installer would use |
| `--one-off` | Skip the AI hand-off after install |
| `--list` | List every available app |

```bash
zeltro install livewire sign-tools
zeltro install livewire sign-tools --image canebaycomputers/cbc:nginx-php8-vector
```

## Keeping installers current

```bash
zeltro update-installer <app>     # refresh one against current upstream, via AI
zeltro update-installer --all
zeltro create-installer "<idea>"  # write a brand-new installer, via AI
```

Both emit a prepared prompt telling an agent to fetch upstream, diff against the current installer, regenerate, verify end-to-end, and commit.

---

## Available apps

There are **214 apps**. Being straight about what has and has not been checked, because "200+ apps" is easy to say and hard to stand behind:

- **125 have been installed on a real machine**, checked over HTTP, and removed — 114 added in the 2026-08 catalogue expansion, plus 11 older ones spot-checked since. Every one of those pins its images to specific versions.
- **89 are older entries that predate that process.** They were written and used, but have not been through it, and most still track floating tags like `:latest`. They may well work; nobody has recently proved it.

If an older app misbehaves, [say so](https://github.com/CaneBayComputers/zeltro-cli/issues) — that is the fastest way for it to get fixed.

{: .note }
> A few apps (Karakeep, Open Archiver, Langfuse, Plane) bring their own Meilisearch or S3 (MinIO-compatible) container. Those two are *optional* shared services and off by default, so each app ships what it needs rather than assuming you enabled them. If you have enabled the shared one, you will have two — harmless, just not shared.

{: .warning }
> **Verified means "installs and responds", not "usable".** A handful of apps need a browser *secure context* for `crypto.subtle` or service workers, which a plain `http://` address cannot provide — those were deliberately left out rather than shipped as something that boots and then fails in the browser.

{: .warning }
> **Upstream changes to know about** (checked 2026-09-28):
>
> - **Whoogle Search** has been removed. Its maintainer ended the project on 24 July 2026 after Google blocked searches made without JavaScript, and it no longer returns results. `zeltro install searxng` is a self-hosted alternative.
> - **MinIO**'s open-source repository is archived, and its images have been removed from Docker Hub and Quay. `zeltro install minio`, the storage containers in **Plane** and **Langfuse**, and the optional shared `minio` service now run **[Silo](https://github.com/pgsty/silo)** (`pgsty/silo`), the maintained MinIO fork. It keeps MinIO's S3 API, `MINIO_*` settings, ports and data format, so the slug, hostname and credentials are unchanged.
> - **FreeScout**'s image moved from `tiredofit/` to `nfrastack/freescout` (2.x), and the installer now uses it. FreeScout only answers for the host in its `APP_URL`, so opening it by IP address returns *403 Untrusted Host* until you set `APP_URL` in the project's `docker-compose.yaml` to that address.
> - **Readeck** now installs 0.23.4; the 0.22.3 image the installer used is no longer published.
> - **Karakeep**'s headless-Chrome sidecar now comes from Docker Hub (`zenika/alpine-chrome`); the `gcr.io` copy is gone.
> - **Maybe Finance** is no longer maintained (final release v0.6.0, July 2025). **Sure** is the community fork and is in the list.
> - **Pingvin Share** was archived in June 2025.
> - **Trilium Notes**: the `trilium` installer, which ran the last `zadam/trilium` image from 2024, has been removed. Use `triliumnext`, the maintained version; `zeltro install trilium` points you there.
> - **LobeChat** is now called LobeHub. The installer runs the final 1.x LobeChat image.


| App | One-liner | Category |
|-----|-----------|----------|
| Activepieces | `zeltro install activepieces` | Automation |
| Actual Budget | `zeltro install actual-budget` | Finance |
| AFFiNE | `zeltro install affine` | Notes |
| Alexandrie | `zeltro install alexandrie` | Notes |
| AnythingLLM | `zeltro install anythingllm` | AI |
| Apache Superset | `zeltro install superset` | Analytics |
| Apprise API | `zeltro install apprise-api` | Notifications |
| Appsmith | `zeltro install appsmith` | Low-code |
| Appwrite | `zeltro install appwrite` | Backend |
| ArchiveBox | `zeltro install archivebox` | Archiving |
| Argilla | `zeltro install argilla` | AI |
| Audiobookshelf | `zeltro install audiobookshelf` | Media |
| authentik | `zeltro install authentik` | Auth |
| Baby Buddy | `zeltro install babybuddy` | Health |
| BentoPDF | `zeltro install bento-pdf` | Utilities |
| BookLore | `zeltro install booklore` | Books |
| BookStack | `zeltro install bookstack` | Wiki |
| BudgE | `zeltro install budge` | Finance |
| Budibase | `zeltro install budibase` | Low-code |
| Bugsink | `zeltro install bugsink` | Monitoring |
| Cachet | `zeltro install cachet` | Status |
| Cal.com | `zeltro install cal-com` | Scheduling |
| Calibre-Web | `zeltro install calibre-web` | Books |
| Calibre-Web Automated Book Downloader (Shelfmark) | `zeltro install calibre-web-automated-book-downloader` | Books |
| Campfire (ONCE) | `zeltro install once-campfire` | Chat |
| Cap (CAPTCHA) | `zeltro install cap-captcha` | Security |
| Changedetection.io | `zeltro install changedetection` | Monitoring |
| Checkmate | `zeltro install checkmate` | Monitoring |
| Chibisafe | `zeltro install chibisafe` | File sharing |
| ClassicPress | `zeltro install classicpress` | CMS |
| Cloudreve | `zeltro install cloudreve` | Files |
| Code-Server | `zeltro install code-server` | Dev Tools |
| CodiMD | `zeltro install codimd` | Notes |
| ConvertX | `zeltro install convertx` | Utilities |
| Coolify | `zeltro install coolify` | DevOps |
| CyberChef | `zeltro install cyberchef` | Utilities |
| Dashy | `zeltro install dashy` | Dashboard |
| Dify | `zeltro install dify` | AI |
| Directus | `zeltro install directus` | CMS |
| Docmost | `zeltro install docmost` | Wiki |
| Documenso | `zeltro install documenso` | Documents |
| DocuSeal | `zeltro install docuseal` | Documents |
| DokuWiki | `zeltro install dokuwiki` | Wiki |
| Dolibarr ERP/CRM | `zeltro install dolibarr` | ERP |
| Easy!Appointments | `zeltro install easyappointments` | Scheduling |
| ESPHome | `zeltro install esphome` | IoT |
| EspoCRM | `zeltro install espocrm` | CRM |
| Evolution API | `zeltro install evolution-api` | Messaging |
| Excalidraw | `zeltro install excalidraw` | Diagramming |
| Fider | `zeltro install fider` | Feedback |
| File Browser | `zeltro install filebrowser` | Files |
| FileFlows | `zeltro install fileflows` | Media |
| Firefly III | `zeltro install firefly-iii` | Finance |
| Fizzy | `zeltro install fizzy` | Utilities |
| Flame | `zeltro install flame` | Dashboard |
| Flarum | `zeltro install flarum` | Forum |
| Flipt | `zeltro install flipt` | Feature flags |
| Flowise | `zeltro install flowise` | AI |
| Forgejo | `zeltro install forgejo` | Git |
| FreeScout | `zeltro install freescout` | Help Desk |
| FreshRSS | `zeltro install freshrss` | RSS |
| Ghost | `zeltro install ghost` | Blogging |
| Gitea | `zeltro install gitea` | Git |
| Glance | `zeltro install glance` | Dashboard |
| Glances | `zeltro install glances` | Monitoring |
| GlitchTip | `zeltro install glitchtip` | Monitoring |
| GLPI | `zeltro install glpi` | IT Asset |
| GoatCounter | `zeltro install goatcounter` | Analytics |
| Gotify | `zeltro install gotify` | Notifications |
| GOWA (Go WhatsApp Web Multidevice) | `zeltro install gowa` | Messaging |
| Grafana | `zeltro install grafana` | Monitoring |
| Gramps Web | `zeltro install gramps-web` | Genealogy |
| Graylog | `zeltro install graylog` | Logging |
| Grist | `zeltro install grist` | Spreadsheet |
| Grocy | `zeltro install grocy` | Home |
| Healthchecks | `zeltro install healthchecks` | Monitoring |
| HedgeDoc | `zeltro install hedgedoc` | Notes |
| Heimdall | `zeltro install heimdall` | Dashboard |
| HeyForm | `zeltro install heyform` | Forms |
| Homarr | `zeltro install homarr` | Dashboard |
| Home Assistant | `zeltro install home-assistant` | Smart Home |
| Homebox | `zeltro install homebox` | Inventory |
| Homepage | `zeltro install homepage` | Dashboard |
| Homer | `zeltro install homer` | Dashboard |
| Hoppscotch | `zeltro install hoppscotch` | API |
| Immich | `zeltro install immich` | Photos |
| Infisical | `zeltro install infisical` | Secrets |
| Invoice Ninja | `zeltro install invoice-ninja` | Invoicing |
| IT Tools | `zeltro install it-tools` | Utilities |
| Jellyfin | `zeltro install jellyfin` | Media |
| Joplin Server | `zeltro install joplin` | Notes |
| Jupyter Notebook (Python) | `zeltro install jupyter-notebook-python` | Data |
| Kanboard | `zeltro install kanboard` | Project Mgmt |
| Karakeep | `zeltro install karakeep` | Bookmarks |
| Kavita | `zeltro install kavita` | Books |
| Keycloak | `zeltro install keycloak` | Auth |
| Kimai | `zeltro install kimai` | Time Tracking |
| Koel | `zeltro install koel` | Music |
| Label Studio | `zeltro install label-studio` | AI |
| Langflow | `zeltro install langflow` | AI |
| Langfuse | `zeltro install langfuse` | AI |
| Laravel Livewire | `zeltro install livewire` | Starter Kit |
| Leantime | `zeltro install leantime` | Project Mgmt |
| Lemmy | `zeltro install lemmy` | Social |
| LibreChat | `zeltro install librechat` | AI |
| LibreSpeed | `zeltro install librespeed` | Network |
| LibreTranslate | `zeltro install libretranslate` | Localization |
| LimeSurvey | `zeltro install limesurvey` | Surveys |
| linkding | `zeltro install linkding` | Bookmarks |
| linkding (plus) | `zeltro install linkding-plus` | Bookmarks |
| Linkwarden | `zeltro install linkwarden` | Bookmarks |
| Listmonk | `zeltro install listmonk` | Newsletters |
| LiteLLM Proxy | `zeltro install litellm` | AI |
| LobeChat | `zeltro install lobe-chat` | AI |
| LocalStack | `zeltro install localstack` | Dev Tools |
| Lowcoder | `zeltro install lowcoder` | Low-code |
| Lychee | `zeltro install lychee` | Photos |
| Mage AI | `zeltro install mage-ai` | Data |
| marimo | `zeltro install marimo` | Data |
| Mastodon | `zeltro install mastodon` | Social |
| Matomo | `zeltro install matomo` | Analytics |
| Mattermost | `zeltro install mattermost` | Chat |
| Mautic | `zeltro install mautic` | Marketing |
| Maybe Finance | `zeltro install maybe` | Finance |
| Mealie | `zeltro install mealie` | Recipes |
| MediaWiki | `zeltro install mediawiki` | Wiki |
| Meilisearch | `zeltro install meilisearch` | Search |
| Memos | `zeltro install memos` | Notes |
| Metabase | `zeltro install metabase` | Analytics |
| MindsDB | `zeltro install mindsdb` | AI |
| Miniflux | `zeltro install miniflux` | RSS |
| MinIO (Silo) | `zeltro install minio` | Storage |
| Mixpost Lite | `zeltro install mixpost` | Social |
| Monica CRM | `zeltro install monica` | CRM |
| Moodle | `zeltro install moodle` | Learning |
| n8n | `zeltro install n8n` | Automation |
| Navidrome | `zeltro install navidrome` | Media |
| NetBox | `zeltro install netbox` | Networking |
| Netdata | `zeltro install netdata` | Monitoring |
| New API | `zeltro install newapi` | AI |
| Nextcloud | `zeltro install nextcloud` | Files |
| Nginx Proxy Manager | `zeltro install nginx-proxy-manager` | Networking |
| NocoBase | `zeltro install nocobase` | Low-code |
| NocoDB | `zeltro install nocodb` | Database |
| NodeBB | `zeltro install nodebb` | Forum |
| ntfy | `zeltro install ntfy` | Notifications |
| Odoo | `zeltro install odoo` | ERP |
| Ollama + Open WebUI | `zeltro install ollama-with-open-webui` | AI |
| OneDev | `zeltro install onedev` | Git |
| Onetime Secret | `zeltro install onetimesecret` | Secrets |
| Open Archiver | `zeltro install open-archiver` | Archiving |
| Open WebUI | `zeltro install open-webui` | AI |
| OpnForm | `zeltro install opnform` | Forms |
| OrangeHRM | `zeltro install orangehrm` | HR |
| Outline | `zeltro install outline` | Wiki |
| ownCloud | `zeltro install owncloud` | Files |
| Paperless-ngx | `zeltro install paperless` | Documents |
| Paymenter | `zeltro install paymenter` | Billing |
| Penpot | `zeltro install penpot` | Design |
| PG Back Web | `zeltro install pgbackweb` | Backup |
| PhotoPrism | `zeltro install photoprism` | Photos |
| Pingvin Share | `zeltro install pingvinshare` | File sharing |
| Pixelfed | `zeltro install pixelfed` | Social |
| Plane | `zeltro install plane` | Project Mgmt |
| Plausible Analytics | `zeltro install plausible` | Analytics |
| PocketBase | `zeltro install pocketbase` | Backend |
| Portainer CE | `zeltro install portainer` | Docker UI |
| Pterodactyl Panel | `zeltro install pterodactyl` | Game panel |
| Pydio Cells | `zeltro install pydio-cells` | Files |
| Rallly | `zeltro install rallly` | Scheduling |
| Reactive Resume | `zeltro install reactive-resume` | Productivity |
| Readeck | `zeltro install readeck` | Bookmarks |
| Redash | `zeltro install redash` | Analytics |
| Redmine | `zeltro install redmine` | Project Mgmt |
| Roundcube | `zeltro install roundcube` | Webmail |
| Ryot | `zeltro install ryot` | Tracking |
| SearXNG | `zeltro install searxng` | Search |
| Shlink | `zeltro install shlink` | URL Shortener |
| SiYuan | `zeltro install siyuan` | Notes |
| Slash | `zeltro install slash` | Bookmarks |
| Snappymail | `zeltro install snappymail` | Webmail |
| Snipe-IT | `zeltro install snipe-it` | Asset Mgmt |
| SparkyFitness | `zeltro install sparkyfitness` | Health |
| Standard Notes | `zeltro install standard-notes` | Notes |
| Statusnook | `zeltro install statusnook` | Status |
| Stirling PDF | `zeltro install stirling-pdf` | Utilities |
| SuperTokens Core | `zeltro install supertokens` | Auth |
| Sure | `zeltro install sure` | Finance |
| Swetrix Analytics | `zeltro install swetrix` | Analytics |
| Taiga | `zeltro install taiga` | Project Mgmt |
| Tandoor Recipes | `zeltro install tandoor` | Recipes |
| Tolgee | `zeltro install tolgee` | Localization |
| Tooljet | `zeltro install tooljet` | Low-code |
| Traccar | `zeltro install traccar` | Tracking |
| TrailBase | `zeltro install trailbase` | Backend |
| Trilium Notes (TriliumNext) | `zeltro install triliumnext` | Notes |
| Twenty CRM | `zeltro install twenty` | CRM |
| Typebot | `zeltro install typebot` | Forms |
| Umami | `zeltro install umami` | Analytics |
| Unleash | `zeltro install unleash` | Feature flags |
| Uptime Kuma | `zeltro install uptime-kuma` | Monitoring |
| Vaultwarden | `zeltro install vaultwarden` | Passwords |
| VERT | `zeltro install vert` | Utilities |
| Vikunja | `zeltro install vikunja` | Project Mgmt |
| Wallabag | `zeltro install wallabag` | Read Later |
| Web-Check | `zeltro install web-check` | Utilities |
| Weblate | `zeltro install weblate` | Localization |
| wger | `zeltro install wger` | Fitness |
| Wiki.js | `zeltro install wikijs` | Wiki |
| Yamtrack | `zeltro install yamtrack` | Media |
| YOURLS | `zeltro install yourls` | URL Shortener |
| Zabbix | `zeltro install zabbix` | Monitoring |
| Zipline | `zeltro install zipline` | File sharing |
| Zulip | `zeltro install zulip` | Chat |

