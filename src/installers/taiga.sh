INSTALL_DISPLAY="Taiga"
INSTALL_NOTES="Open-source project management. Register at http://$PROJECT_NAME/ to create your account. First startup takes ~60 seconds."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE taiga;" 2>/dev/null || true
}

write_files() {
    local secret_key erlang_cookie
    secret_key=$(openssl rand -hex 32)
    erlang_cookie=$(openssl rand -hex 16)

    mkdir -p taiga-gateway

    cat > .env << EOF
TAIGA_SCHEME=http
TAIGA_DOMAIN=__ZELTRO_IP__
SUBPATH=""
WEBSOCKETS_SCHEME=ws
SECRET_KEY="$secret_key"
POSTGRES_USER=root
POSTGRES_PASSWORD=password
EMAIL_BACKEND=console
EMAIL_HOST=zeltro-mailhog
EMAIL_PORT=1025
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
EMAIL_DEFAULT_FROM=taiga@taiga.local
EMAIL_USE_TLS=False
EMAIL_USE_SSL=False
RABBITMQ_USER=taiga
RABBITMQ_PASS=taiga
RABBITMQ_VHOST=taiga
RABBITMQ_ERLANG_COOKIE=$erlang_cookie
ATTACHMENTS_MAX_AGE=360
ENABLE_TELEMETRY=False
EOF

    cat > docker-compose.yaml << 'EOF'
x-environment: &common-env
  POSTGRES_DB: taiga
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  POSTGRES_HOST: zeltro-postgres
  TAIGA_SECRET_KEY: ${SECRET_KEY}
  TAIGA_SITES_SCHEME: ${TAIGA_SCHEME}
  TAIGA_SITES_DOMAIN: ${TAIGA_DOMAIN}
  TAIGA_SUBPATH: ${SUBPATH}
  EMAIL_BACKEND: django.core.mail.backends.${EMAIL_BACKEND}.EmailBackend
  DEFAULT_FROM_EMAIL: ${EMAIL_DEFAULT_FROM}
  EMAIL_USE_TLS: ${EMAIL_USE_TLS}
  EMAIL_USE_SSL: ${EMAIL_USE_SSL}
  EMAIL_HOST: ${EMAIL_HOST}
  EMAIL_PORT: ${EMAIL_PORT}
  EMAIL_HOST_USER: ${EMAIL_HOST_USER}
  EMAIL_HOST_PASSWORD: ${EMAIL_HOST_PASSWORD}
  RABBITMQ_USER: ${RABBITMQ_USER}
  RABBITMQ_PASS: ${RABBITMQ_PASS}
  ENABLE_TELEMETRY: ${ENABLE_TELEMETRY}

x-volumes: &common-volumes
  - taiga-static-data:/taiga-back/static
  - taiga-media-data:/taiga-back/media

services:
  taiga-back:
    image: taigaio/taiga-back:latest
    restart: unless-stopped
    environment: *common-env
    volumes: *common-volumes
    depends_on:
      - taiga-events-rabbitmq
      - taiga-async-rabbitmq

  taiga-async:
    image: taigaio/taiga-back:latest
    restart: unless-stopped
    entrypoint:
      - /taiga-back/docker/async_entrypoint.sh
    environment: *common-env
    volumes: *common-volumes
    depends_on:
      - taiga-events-rabbitmq
      - taiga-async-rabbitmq

  taiga-async-rabbitmq:
    image: rabbitmq:3.8-management-alpine
    restart: unless-stopped
    hostname: taiga-async-rabbitmq
    environment:
      RABBITMQ_ERLANG_COOKIE: ${RABBITMQ_ERLANG_COOKIE}
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASS}
      RABBITMQ_DEFAULT_VHOST: ${RABBITMQ_VHOST}
    volumes:
      - taiga-async-rabbitmq-data:/var/lib/rabbitmq

  taiga-front:
    image: taigaio/taiga-front:latest
    restart: unless-stopped
    environment:
      TAIGA_URL: "${TAIGA_SCHEME}://${TAIGA_DOMAIN}"
      TAIGA_WEBSOCKETS_URL: "${WEBSOCKETS_SCHEME}://${TAIGA_DOMAIN}"
      TAIGA_SUBPATH: "${SUBPATH}"

  taiga-events:
    image: taigaio/taiga-events:latest
    restart: unless-stopped
    environment:
      RABBITMQ_USER: ${RABBITMQ_USER}
      RABBITMQ_PASS: ${RABBITMQ_PASS}
      TAIGA_SECRET_KEY: ${SECRET_KEY}
    depends_on:
      - taiga-events-rabbitmq

  taiga-events-rabbitmq:
    image: rabbitmq:3.8-management-alpine
    restart: unless-stopped
    hostname: taiga-events-rabbitmq
    environment:
      RABBITMQ_ERLANG_COOKIE: ${RABBITMQ_ERLANG_COOKIE}
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASS}
      RABBITMQ_DEFAULT_VHOST: ${RABBITMQ_VHOST}
    volumes:
      - taiga-events-rabbitmq-data:/var/lib/rabbitmq

  taiga-protected:
    image: taigaio/taiga-protected:latest
    restart: unless-stopped
    environment:
      MAX_AGE: ${ATTACHMENTS_MAX_AGE}
      SECRET_KEY: ${SECRET_KEY}

  taiga-gateway:
    image: nginx:1.19-alpine
    restart: unless-stopped
    volumes:
      - ./taiga-gateway/taiga.conf:/etc/nginx/conf.d/default.conf:ro
      - taiga-static-data:/taiga/static
      - taiga-media-data:/taiga/media
    depends_on:
      - taiga-front
      - taiga-back
      - taiga-events
      - taiga-protected

volumes:
  taiga-static-data:
  taiga-media-data:
  taiga-async-rabbitmq-data:
  taiga-events-rabbitmq-data:
EOF

    cat > taiga-gateway/taiga.conf << 'NGINX'
server {
    listen 80 default_server;
    client_max_body_size 100M;
    charset utf-8;

    location / {
        proxy_pass http://taiga-front/;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
    }

    location /api/ {
        proxy_pass http://taiga-back:8000/api/;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
    }

    location /admin/ {
        proxy_pass http://taiga-back:8000/admin/;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
    }

    location /static/ {
        alias /taiga/static/;
    }

    location /_protected/ {
        internal;
        alias /taiga/media/;
        add_header Content-disposition "attachment";
    }

    location /media/exports/ {
        alias /taiga/media/exports/;
        add_header Content-disposition "attachment";
    }

    location /media/ {
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://taiga-protected:8003/;
    }

    location /events {
        proxy_pass http://taiga-events:8888/events;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
    }
}
NGINX
}
