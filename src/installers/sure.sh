INSTALL_DISPLAY="Sure"
INSTALL_CREDENTIALS="Register the first account on first visit"
INSTALL_NOTES="First boot runs Rails db:prepare against zeltro-postgres — allow ~60 seconds."

# db:prepare + asset boot on a cold Rails container.
INSTALL_READY_RETRIES=24

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"sure\";" 2>/dev/null || true
}

write_files() {
    local secret_key_base

    secret_key_base=$(openssl rand -hex 64)

    cat > docker-compose.yaml << EOF
services:
  sure-app:
    image: ghcr.io/we-promise/sure:0.7.0-hotfix.2
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
      POSTGRES_DB: sure
      REDIS_URL: "redis://zeltro-redis:6379/1"
    volumes:
      - sure-storage:/rails/storage

  sure-worker:
    image: ghcr.io/we-promise/sure:0.7.0-hotfix.2
    restart: unless-stopped
    command: bundle exec sidekiq
    environment:
      SELF_HOSTED: "true"
      RAILS_FORCE_SSL: "false"
      RAILS_ASSUME_SSL: "false"
      SECRET_KEY_BASE: "$secret_key_base"
      DB_HOST: zeltro-postgres
      DB_PORT: "5432"
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      POSTGRES_DB: sure
      REDIS_URL: "redis://zeltro-redis:6379/1"
    depends_on:
      - sure-app
    volumes:
      - sure-storage:/rails/storage

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - sure-app

volumes:
  sure-storage:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://sure-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
