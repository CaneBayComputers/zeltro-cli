# FreeScout

**Image**: `nfrastack/freescout:2.2.14` (the 2.x continuation of `tiredofit/freescout`, which is gone from Docker Hub)
**Port**: 80 (direct — no nginx proxy; the image includes its own web server)
**Database**: MariaDB — dedicated `freescout` user required (root login rejected by this image)
**Credentials**: `admin@freescout.local / freescout-admin` (set via `ADMIN_EMAIL` / `ADMIN_PASS`)

## Key Notes
- The image rejects the root MariaDB user — create a dedicated user first:
  ```
  docker exec zeltro-mariadb mariadb -u root -e "
    CREATE DATABASE IF NOT EXISTS freescout CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS 'freescout'@'%' IDENTIFIED BY 'freescout';
    GRANT ALL PRIVILEGES ON freescout.* TO 'freescout'@'%';
    FLUSH PRIVILEGES;"
  ```
- No nginx sidecar needed — the image bundles nginx and PHP-FPM.
- `SETUP_TYPE: AUTO` performs automatic installation on first start; first boot takes a few minutes.
- `ENABLE_AUTO_UPDATE: "FALSE"` prevents unexpected updates in a local env.
- 2.x renamed several variables: `SITE_URL` is now `APP_URL`, and FreeScout's own settings need a `FREESCOUT_` prefix (`DISPLAY_ERRORS` → `FREESCOUT_APP_DEBUG`, `APPLICATION_NAME` → `FREESCOUT_APPLICATION_NAME`). The log volume moved from `/www/logs` to `/logs`.
- FreeScout answers **403 "Untrusted Host"** to any Host header that is not the host in `APP_URL` (or listed in `FREESCOUT_APP_TRUSTED_HOSTS`). Browsing it by IP address needs `APP_URL` (or the trusted-hosts list) set to that address.
- Persist `freescout-data` (`/data`) and `freescout-logs` (`/logs`) volumes.
- The installer exists: run `zeltro install freescout`.
