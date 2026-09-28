# Trilium Notes (TriliumNext)

Hierarchical note-taking with scripting and relations — the maintained successor to `zadam/trilium`.

**Image**: `ghcr.io/triliumnext/trilium:v0.104.1`
**Port**: 8080 (via nginx proxy)
**Database**: None (SQLite in the `triliumnext-data` volume)
**Credentials**: Set your login password on first visit

## Key Notes
- Do not add `user:` to the app service. The entrypoint starts as root, chowns `/home/node/trilium-data`, then drops to the `node` user itself. Pinning `user: "1000:1000"` makes that chown fail with "Operation not permitted" and the container restart-loops.
- `TRILIUM_DATA_DIR` must match the volume mount point.
- It replaces the old `trilium` installer (the unmaintained `zadam/trilium` image), which has been removed; `zeltro install trilium` now points here. Data from a `zadam/trilium` volume is not migrated automatically.
- The installer exists: run `zeltro install triliumnext`.
