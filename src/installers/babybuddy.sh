INSTALL_DISPLAY="Baby Buddy"
INSTALL_CREDENTIALS="admin / admin"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE babybuddy;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  babybuddy-app:
    image: lscr.io/linuxserver/babybuddy:latest
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
      TZ: UTC
      SECRET_KEY: $secret_key
      DB_ENGINE: django.db.backends.postgresql
      DB_HOST: zeltro-postgres
      DB_PORT: 5432
      DB_NAME: babybuddy
      DB_USER: root
      DB_PASSWORD: password
      CSRF_TRUSTED_ORIGINS: http://babybuddy
      ALLOWED_HOSTS: __ZELTRO_PROJECT__,__ZELTRO_IP__,localhost,127.0.0.1
      EMAIL_HOST: zeltro-mailhog
      EMAIL_PORT: 1025
    volumes:
      - babybuddy-config:/config

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - babybuddy-app

volumes:
  babybuddy-config:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://babybuddy-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
