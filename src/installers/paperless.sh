INSTALL_DISPLAY="Paperless-ngx"
INSTALL_CREDENTIALS="admin / admin"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE paperless;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 25)

    cat > docker-compose.yaml << EOF
services:
  paperless-app:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    restart: unless-stopped
    environment:
      PAPERLESS_DBHOST: zeltro-postgres
      PAPERLESS_DBPORT: 5432
      PAPERLESS_DBUSER: root
      PAPERLESS_DBPASS: password
      PAPERLESS_DBNAME: paperless
      PAPERLESS_REDIS: redis://zeltro-redis:6379
      PAPERLESS_SECRET_KEY: "$secret_key"
      PAPERLESS_URL: http://paperless
      PAPERLESS_ADMIN_USER: admin
      PAPERLESS_ADMIN_PASSWORD: admin
    volumes:
      - paperless-data:/usr/src/paperless/data
      - paperless-media:/usr/src/paperless/media
      - paperless-export:/usr/src/paperless/export
      - paperless-consume:/usr/src/paperless/consume

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - paperless-app

volumes:
  paperless-data:
  paperless-media:
  paperless-export:
  paperless-consume:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://paperless-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
