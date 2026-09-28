# MinIO

**Image**: `pgsty/silo:RELEASE.2026-09-03T13-18-01Z` — Silo, the maintained MinIO fork (formerly `pgsty/minio`)
**Port**: 9001 (web console) → nginx; API on port 9000 (internal)
**Database**: None
**Credentials**: minioadmin / minioadmin123

## Key Notes
- MinIO's own images are gone: the project was archived, `minio/minio` returns 404 on Docker Hub and the `quay.io/minio/minio` tags no longer resolve. Do not use them.
- Silo keeps MinIO's S3 API, `MINIO_*` variables, ports and on-disk format, so it is a drop-in replacement. Its binary is `silo`, not `minio`; the image entrypoint maps `server ...` (and a leading `minio`) onto it, so only an overridden `entrypoint: sh` needs to call `silo` by name. `mc` is bundled.
- Command: `server /data --console-address ":9001"` — both API (9000) and console (9001) start.
- nginx proxies port 80 → the console (9001). API clients connect to port 9000 internally.
- S3-compatible API endpoint for applications: `http://minio-app:9000` (internal VPC, not proxied).
- The installer exists: run `zeltro install minio`.
