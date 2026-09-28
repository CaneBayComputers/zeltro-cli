# Langfuse

Open-source LLM observability: traces, evals, prompt management and cost tracking for AI apps.

**Image**: `langfuse/langfuse:4.4.0` (web) + `langfuse/langfuse-worker:4.4.0` + `clickhouse/clickhouse-server:25.12` + `pgsty/silo:RELEASE.2026-09-03T13-18-01Z` (Silo, the maintained MinIO fork) + `nginx:1.30.4-alpine`
**Port**: 3000 on the web container (behind the nginx reverse proxy on 80)
**Database**: PostgreSQL (`zeltro-postgres`, database `langfuse`) + Redis (`zeltro-redis`, DB 6); ClickHouse and MinIO run as sidecars
**Credentials**: `admin@example.com` / `admin123` (seeded via the `LANGFUSE_INIT_*` vars)

## Key Notes
- Langfuse v3+ is **not** a single container. ClickHouse (analytics) and S3-compatible object storage (event/media blobs) are hard requirements, so they ship as sidecars — Zeltro's shared MinIO is an opt-in profile service and cannot be relied on.
- Config lives in `.env`, shared by the web and worker containers via `env_file`. Keep them on identical values; a mismatched `ENCRYPTION_KEY` or `SALT` silently breaks decryption.
- Redis is wired with `REDIS_CONNECTION_STRING` rather than `REDIS_HOST`/`REDIS_AUTH` because `zeltro-redis` has no password. DB 6 keeps BullMQ queues out of other projects' keyspace.
- `zeltro-redis` runs `maxmemory-policy noeviction`, which is what BullMQ requires — do not change it.
- The `LANGFUSE_INIT_*` block only seeds on a genuinely empty database. Wipe the `langfuse` Postgres DB if you need to re-seed.
- Browser-side media uploads point at the internal `http://langfuse-minio:9000`, which the browser cannot reach — trace ingestion and the UI work, but attaching media from the UI does not.
- The `langfuse-minio` sidecar runs Silo because MinIO's own images are gone. Its binary is `silo`, not `minio`: the `sh -c` command that pre-creates the `langfuse` bucket directory must hand off via `exec docker-entrypoint.sh server ...` (or `silo server ...`). `minio server` fails with "not found".
- ClickHouse migrations run at first boot; allow 2-3 minutes before the proxy returns 200.
- The installer exists: run `zeltro install langfuse`.
