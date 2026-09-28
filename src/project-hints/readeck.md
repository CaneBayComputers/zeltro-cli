# Readeck

Read-it-later and web archiving — saves the readable content of pages, with highlights and ebook export.

**Image**: `codeberg.org/readeck/readeck:0.23.4`
**Port**: 8000 (via nginx proxy)
**Database**: None (SQLite in the `readeck-data` volume)
**Credentials**: Create the first user on the `/onboarding` page at first visit

## Key Notes
- The image lives on Codeberg's registry, not Docker Hub or ghcr.io. The full `codeberg.org/...` path is required.
- Never lose the `readeck-data` volume. Readeck generates a `secret_key` into `config.toml` on first launch; if it regenerates, every session and API token is invalidated.
- Do not set `READECK_SERVER_BASE_URL` unless you mean it — once set it becomes the only valid URL for the instance and all reverse-proxy forwarded headers are ignored.
- `/` returns a 303 to the login/onboarding flow, which is the normal healthy response.
- The onboarding route only exists while there are zero users; the first account created is the admin.
- The installer exists: run `zeltro install readeck`.
