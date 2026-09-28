INSTALL_DISPLAY="Tooljet"
INSTALL_NOTES="Low-code app builder. First startup takes ~60 seconds for migrations. Create your admin account on first visit."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE tooljet_production;" 2>/dev/null || true
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE tooljet_db;" 2>/dev/null || true
}

write_files() {
    local lockbox_key secret_key pgrst_secret
    lockbox_key=$(openssl rand -hex 32)
    secret_key=$(openssl rand -hex 64)
    pgrst_secret=$(openssl rand -hex 32)

    cat > .env << EOF
TOOLJET_HOST=http://tooljet
SERVE_CLIENT=true
PORT=3000
NODE_ENV=production
DISABLE_TOOLJET_TELEMETRY=true

LOCKBOX_MASTER_KEY=$lockbox_key
SECRET_KEY_BASE=$secret_key

PG_HOST=zeltro-postgres
PG_PORT=5432
PG_DB=tooljet_production
PG_USER=root
PG_PASS=password
PGSSLMODE=disable
DATABASE_URL=postgres://root:password@zeltro-postgres:5432/tooljet_production?sslmode=disable

TOOLJET_DB=tooljet_db
TOOLJET_DB_HOST=zeltro-postgres
TOOLJET_DB_PORT=5432
TOOLJET_DB_USER=root
TOOLJET_DB_PASS=password
TOOLJET_DB_BULK_UPLOAD_MAX_ROWS=5000
TOOLJET_DB_BULK_UPLOAD_MAX_CSV_FILE_SIZE_MB=5

PGRST_JWT_SECRET=$pgrst_secret
PGRST_DB_URI=postgres://root:password@zeltro-postgres:5432/tooljet_db
PGRST_LOG_LEVEL=info
PGRST_DB_PRE_CONFIG=postgrest.pre_config

REDIS_HOST=zeltro-redis
REDIS_PORT=6379
REDIS_USER=default
REDIS_PASSWORD=

SMTP_DOMAIN=zeltro-mailhog
SMTP_PORT=1025
DEFAULT_FROM_EMAIL=tooljet@tooljet.local
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  tooljet-app:
    image: tooljet/tooljet-ce:latest
    restart: unless-stopped
    env_file:
      - .env
    environment:
      SERVE_CLIENT: "true"
      PORT: "3000"
      NODE_ENV: production
    command: npm run start:prod

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - tooljet-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://tooljet-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX
}
