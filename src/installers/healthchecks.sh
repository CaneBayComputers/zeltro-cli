INSTALL_DISPLAY="Healthchecks"
INSTALL_CREDENTIALS="admin@example.com / admin123"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE healthchecks;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  healthchecks-app:
    image: healthchecks/healthchecks:latest
    restart: unless-stopped
    environment:
      DB: postgres
      DB_HOST: zeltro-postgres
      DB_PORT: 5432
      DB_NAME: healthchecks
      DB_USER: root
      DB_PASSWORD: password
      SECRET_KEY: $secret_key
      DEBUG: "False"
      ALLOWED_HOSTS: __ZELTRO_PROJECT__,__ZELTRO_IP__,localhost,127.0.0.1
      SITE_ROOT: http://healthchecks
      SITE_NAME: Healthchecks
      SUPERUSER_EMAIL: admin@example.com
      SUPERUSER_PASSWORD: admin123
      DEFAULT_FROM_EMAIL: healthchecks@example.com
      EMAIL_HOST: zeltro-mailhog
      EMAIL_PORT: 1025
      EMAIL_USE_TLS: "False"
      REGISTRATION_OPEN: "False"
    volumes:
      - healthchecks-data:/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - healthchecks-app

volumes:
  healthchecks-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://healthchecks-app:8000;
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
