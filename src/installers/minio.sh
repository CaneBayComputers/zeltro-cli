INSTALL_DISPLAY="MinIO (Silo)"
INSTALL_CREDENTIALS="minioadmin / minioadmin123"
INSTALL_NOTES="S3-compatible object storage. Runs Silo, the maintained MinIO fork: same S3 API, MINIO_* settings and data format. API port 9000 is internal; the web console is at http://$PROJECT_NAME/."

# MinIO's own images are gone: the project was archived, minio/minio returns
# 404 on Docker Hub and the quay.io tags no longer resolve. pgsty/silo (formerly
# pgsty/minio) is the maintained community fork. Its entrypoint maps the
# `server` subcommand onto its `silo` binary, so MinIO's usual command line,
# ports and MINIO_ROOT_* variables work unchanged.
write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  minio-app:
    image: pgsty/silo:RELEASE.2026-09-03T13-18-01Z
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin123
    volumes:
      - minio-data:/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - minio-app

volumes:
  minio-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://minio-app:9001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
