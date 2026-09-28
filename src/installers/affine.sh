INSTALL_DISPLAY="AFFiNE"
INSTALL_CREDENTIALS="Register on first visit (first account becomes the server owner)"
INSTALL_NOTES="A one-shot migration container runs before the server; the first boot takes about a minute."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE affine;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  affine-migration:
    image: ghcr.io/toeverything/affine:0.27.0
    command: ['sh', '-c', 'node ./scripts/self-host-predeploy.js']
    restart: on-failure
    environment:
      REDIS_SERVER_HOST: zeltro-redis
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/affine
      AFFINE_INDEXER_ENABLED: "false"
    volumes:
      - affine-storage:/root/.affine/storage
      - affine-config:/root/.affine/config

  affine-server:
    image: ghcr.io/toeverything/affine:0.27.0
    restart: unless-stopped
    environment:
      REDIS_SERVER_HOST: zeltro-redis
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/affine
      AFFINE_INDEXER_ENABLED: "false"
      AFFINE_SERVER_EXTERNAL_URL: http://affine
      AFFINE_SERVER_HTTPS: "false"
    volumes:
      - affine-storage:/root/.affine/storage
      - affine-config:/root/.affine/config
    depends_on:
      affine-migration:
        condition: service_completed_successfully

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - affine-server

volumes:
  affine-storage:
  affine-config:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://affine-server:3010;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINX
}
