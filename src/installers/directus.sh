INSTALL_DISPLAY="Directus"
INSTALL_CREDENTIALS="admin@example.com / admin123"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE directus;" 2>/dev/null || true
}

write_files() {
    local key secret
    key=$(openssl rand -hex 16)
    secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  directus-app:
    image: directus/directus:latest
    restart: unless-stopped
    environment:
      KEY: $key
      SECRET: $secret
      ADMIN_EMAIL: admin@example.com
      ADMIN_PASSWORD: admin123
      DB_CLIENT: pg
      DB_HOST: zeltro-postgres
      DB_PORT: 5432
      DB_DATABASE: directus
      DB_USER: root
      DB_PASSWORD: password
      CACHE_ENABLED: "true"
      CACHE_STORE: redis
      REDIS: redis://zeltro-redis:6379
      WEBSOCKETS_ENABLED: "true"
      PUBLIC_URL: http://directus
    volumes:
      - directus-uploads:/directus/uploads
      - directus-extensions:/directus/extensions

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - directus-app

volumes:
  directus-uploads:
  directus-extensions:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://directus-app:8055;
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
