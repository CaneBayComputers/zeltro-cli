INSTALL_DISPLAY="GlitchTip"
INSTALL_CREDENTIALS="Register on first visit (first user becomes the superuser)"
INSTALL_NOTES="Sentry-compatible error tracking. Point your SDK DSN at http://glitchtip/<project-id>."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE glitchtip;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > .env << EOF
DATABASE_URL=postgres://root:password@zeltro-postgres:5432/glitchtip
REDIS_URL=redis://zeltro-redis:6379/0
SECRET_KEY=$secret_key
PORT=8000
GLITCHTIP_DOMAIN=http://glitchtip
DEFAULT_FROM_EMAIL=glitchtip@example.com
EMAIL_URL=smtp://zeltro-mailhog:1025
ENABLE_OPEN_USER_REGISTRATION=True
CELERY_WORKER_AUTOSCALE=1,3
CELERY_WORKER_MAX_TASKS_PER_CHILD=10000
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  glitchtip-migrate:
    image: glitchtip/glitchtip:6.2.3
    command: ./bin/run-migrate.sh
    restart: on-failure
    env_file: .env

  glitchtip-web:
    image: glitchtip/glitchtip:6.2.3
    restart: unless-stopped
    env_file: .env
    volumes:
      - glitchtip-uploads:/code/uploads
    depends_on:
      glitchtip-migrate:
        condition: service_completed_successfully

  glitchtip-worker:
    image: glitchtip/glitchtip:6.2.3
    command: ./bin/run-celery-with-beat.sh
    restart: unless-stopped
    env_file: .env
    volumes:
      - glitchtip-uploads:/code/uploads
    depends_on:
      glitchtip-migrate:
        condition: service_completed_successfully

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - glitchtip-web

volumes:
  glitchtip-uploads:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://glitchtip-web:8000;
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
