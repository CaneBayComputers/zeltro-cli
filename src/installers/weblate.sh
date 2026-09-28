INSTALL_DISPLAY="Weblate"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="First boot runs a long migration — give it a few minutes before the page answers."

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"weblate\";" 2>/dev/null || true
}

write_files() {
    # NOTE: the app service must NOT be called weblate-* — Zeltro's web-service
    # detection regex is ^(nginx|web|app|api|server|frontend|backend|http) and
    # "weblate-app" matches on "web", which would hand the project IP to the
    # wrong container. Hence "translate-server".
    cat > docker-compose.yaml << 'EOF'
services:
  translate-server:
    image: weblate/weblate:2026.8.0.0
    restart: unless-stopped
    environment:
      WEBLATE_DEBUG: "0"
      WEBLATE_LOGLEVEL: INFO
      WEBLATE_SITE_TITLE: Weblate
      WEBLATE_SITE_DOMAIN: __ZELTRO_IP__
      WEBLATE_ALLOWED_HOSTS: "*"
      WEBLATE_ADMIN_NAME: Weblate Admin
      WEBLATE_ADMIN_EMAIL: admin@example.com
      WEBLATE_ADMIN_PASSWORD: admin123
      WEBLATE_SERVER_EMAIL: weblate@example.com
      WEBLATE_DEFAULT_FROM_EMAIL: weblate@example.com
      WEBLATE_REGISTRATION_OPEN: "1"
      WEBLATE_EMAIL_HOST: zeltro-mailhog
      WEBLATE_EMAIL_PORT: "1025"
      WEBLATE_EMAIL_USE_TLS: "0"
      WEBLATE_EMAIL_USE_SSL: "0"
      POSTGRES_HOST: zeltro-postgres
      POSTGRES_PORT: "5432"
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      POSTGRES_DB: weblate
      POSTGRES_DATABASE: weblate
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      REDIS_DB: "1"
      CLIENT_MAX_BODY_SIZE: 200M
    volumes:
      - weblate-data:/app/data
      - weblate-cache:/app/cache

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - translate-server

volumes:
  weblate-data:
  weblate-cache:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://translate-server:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX
}
