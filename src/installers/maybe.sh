INSTALL_DISPLAY="Maybe Finance"
INSTALL_CREDENTIALS="Register on first visit"
INSTALL_NOTES="Rails app — the first boot runs migrations and asset setup, which takes a couple of minutes."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE maybe;" 2>/dev/null || true
}

write_files() {
    local secret_key_base
    secret_key_base=$(openssl rand -hex 64)

    cat > docker-compose.yaml << EOF
services:
  maybe-web:
    image: ghcr.io/maybe-finance/maybe:0.6.0
    restart: unless-stopped
    environment:
      SELF_HOSTED: "true"
      RAILS_FORCE_SSL: "false"
      RAILS_ASSUME_SSL: "false"
      SECRET_KEY_BASE: "$secret_key_base"
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      POSTGRES_DB: maybe
      REDIS_URL: redis://zeltro-redis:6379/1
    volumes:
      - maybe-storage:/rails/storage

  maybe-worker:
    image: ghcr.io/maybe-finance/maybe:0.6.0
    command: bundle exec sidekiq
    restart: unless-stopped
    environment:
      SELF_HOSTED: "true"
      RAILS_FORCE_SSL: "false"
      RAILS_ASSUME_SSL: "false"
      SECRET_KEY_BASE: "$secret_key_base"
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      POSTGRES_DB: maybe
      REDIS_URL: redis://zeltro-redis:6379/1
    volumes:
      - maybe-storage:/rails/storage
    depends_on:
      - maybe-web

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - maybe-web

volumes:
  maybe-storage:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://maybe-web:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
    }
}
NGINX
}
