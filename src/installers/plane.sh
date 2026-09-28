INSTALL_DISPLAY="Plane"
INSTALL_CREDENTIALS="Register on first visit"
INSTALL_NOTES="Open-source project management (Jira alternative). First startup takes ~60 seconds for migrations."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE plane;" 2>/dev/null || true
}

write_files() {
    local secret_key live_secret minio_key minio_secret
    secret_key=$(openssl rand -hex 32)
    live_secret=$(openssl rand -hex 32)
    minio_key=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 20)
    minio_secret=$(openssl rand -hex 24)

    cat > .env << EOF
APP_RELEASE=stable
APP_DOMAIN=plane
WEB_URL=http://plane
CORS_ALLOWED_ORIGINS=http://plane

PGHOST=zeltro-postgres
PGDATABASE=plane
POSTGRES_USER=root
POSTGRES_PASSWORD=password
POSTGRES_DB=plane
POSTGRES_PORT=5432
DATABASE_URL=postgresql://root:password@zeltro-postgres:5432/plane

REDIS_HOST=zeltro-redis
REDIS_PORT=6379
REDIS_URL=redis://zeltro-redis:6379/

RABBITMQ_HOST=plane-mq
RABBITMQ_PORT=5672
RABBITMQ_USER=plane
RABBITMQ_PASSWORD=plane
RABBITMQ_VHOST=plane
AMQP_URL=amqp://plane:plane@plane-mq:5672/plane

LISTEN_HTTP_PORT=80
LISTEN_HTTPS_PORT=443
SITE_ADDRESS=:80
FILE_SIZE_LIMIT=5242880

AWS_REGION=
AWS_ACCESS_KEY_ID=$minio_key
AWS_SECRET_ACCESS_KEY=$minio_secret
AWS_S3_ENDPOINT_URL=http://plane-minio:9000
AWS_S3_BUCKET_NAME=uploads
USE_MINIO=1
MINIO_ENDPOINT_SSL=0

SECRET_KEY=$secret_key
LIVE_SERVER_SECRET_KEY=$live_secret
DEBUG=0
GUNICORN_WORKERS=1
API_KEY_RATE_LIMIT=60/minute

CERT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory
CERT_EMAIL=
CERT_ACME_DNS=
EOF

    cat > docker-compose.yaml << 'EOF'
x-db-env: &db-env
  PGHOST: ${PGHOST:-zeltro-postgres}
  PGDATABASE: ${PGDATABASE:-plane}
  POSTGRES_USER: ${POSTGRES_USER:-root}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
  POSTGRES_DB: ${POSTGRES_DB:-plane}
  POSTGRES_PORT: ${POSTGRES_PORT:-5432}

x-redis-env: &redis-env
  REDIS_HOST: ${REDIS_HOST:-zeltro-redis}
  REDIS_PORT: ${REDIS_PORT:-6379}
  REDIS_URL: ${REDIS_URL:-redis://zeltro-redis:6379/}

x-minio-env: &minio-env
  MINIO_ROOT_USER: ${AWS_ACCESS_KEY_ID}
  MINIO_ROOT_PASSWORD: ${AWS_SECRET_ACCESS_KEY}

x-aws-s3-env: &aws-s3-env
  AWS_REGION: ${AWS_REGION:-}
  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
  AWS_S3_ENDPOINT_URL: ${AWS_S3_ENDPOINT_URL:-http://plane-minio:9000}
  AWS_S3_BUCKET_NAME: ${AWS_S3_BUCKET_NAME:-uploads}

x-proxy-env: &proxy-env
  APP_DOMAIN: ${APP_DOMAIN:-plane}
  FILE_SIZE_LIMIT: ${FILE_SIZE_LIMIT:-5242880}
  CERT_EMAIL: ${CERT_EMAIL:-}
  CERT_ACME_CA: ${CERT_ACME_CA:-https://acme-v02.api.letsencrypt.org/directory}
  CERT_ACME_DNS: ${CERT_ACME_DNS:-}
  LISTEN_HTTP_PORT: ${LISTEN_HTTP_PORT:-80}
  LISTEN_HTTPS_PORT: ${LISTEN_HTTPS_PORT:-443}
  BUCKET_NAME: ${AWS_S3_BUCKET_NAME:-uploads}
  SITE_ADDRESS: ${SITE_ADDRESS:-:80}

x-mq-env: &mq-env
  RABBITMQ_HOST: ${RABBITMQ_HOST:-plane-mq}
  RABBITMQ_PORT: ${RABBITMQ_PORT:-5672}
  RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER:-plane}
  RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD:-plane}
  RABBITMQ_DEFAULT_VHOST: ${RABBITMQ_VHOST:-plane}
  RABBITMQ_VHOST: ${RABBITMQ_VHOST:-plane}

x-live-env: &live-env
  API_BASE_URL: ${API_BASE_URL:-http://api:8000}
  LIVE_SERVER_SECRET_KEY: ${LIVE_SERVER_SECRET_KEY}

x-app-env: &app-env
  WEB_URL: ${WEB_URL:-http://plane}
  DEBUG: ${DEBUG:-0}
  CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS:-http://plane}
  GUNICORN_WORKERS: ${GUNICORN_WORKERS:-1}
  USE_MINIO: ${USE_MINIO:-1}
  DATABASE_URL: ${DATABASE_URL:-postgresql://root:password@zeltro-postgres:5432/plane}
  SECRET_KEY: ${SECRET_KEY}
  AMQP_URL: ${AMQP_URL:-amqp://plane:plane@plane-mq:5672/plane}
  API_KEY_RATE_LIMIT: ${API_KEY_RATE_LIMIT:-60/minute}
  MINIO_ENDPOINT_SSL: ${MINIO_ENDPOINT_SSL:-0}
  LIVE_SERVER_SECRET_KEY: ${LIVE_SERVER_SECRET_KEY}

services:
  # Listed first on purpose: setup gives the static IP and container name to the
  # first service whose name looks web-facing, and `web` (the Next.js frontend
  # on :3000) matched before this gateway did, so nothing answered on port 80.
  nginx:
    image: makeplane/plane-proxy:${APP_RELEASE:-stable}
    restart: unless-stopped
    environment:
      <<: *proxy-env
    volumes:
      - plane-proxy-config:/config
      - plane-proxy-data:/data
    depends_on:
      - web
      - api
      - space
      - admin
      - live

  web:
    image: makeplane/plane-frontend:${APP_RELEASE:-stable}
    restart: unless-stopped
    depends_on:
      - api
      - worker

  space:
    image: makeplane/plane-space:${APP_RELEASE:-stable}
    restart: unless-stopped
    depends_on:
      - api
      - worker
      - web

  admin:
    image: makeplane/plane-admin:${APP_RELEASE:-stable}
    restart: unless-stopped
    depends_on:
      - api
      - web

  live:
    image: makeplane/plane-live:${APP_RELEASE:-stable}
    restart: unless-stopped
    environment:
      <<: [*live-env, *redis-env]
    depends_on:
      - api
      - web

  api:
    image: makeplane/plane-backend:${APP_RELEASE:-stable}
    command: ./bin/docker-entrypoint-api.sh
    restart: unless-stopped
    volumes:
      - plane-logs-api:/code/plane/logs
    environment:
      <<: [*app-env, *db-env, *redis-env, *minio-env, *aws-s3-env, *proxy-env]
    depends_on:
      - plane-mq
      - plane-minio

  worker:
    image: makeplane/plane-backend:${APP_RELEASE:-stable}
    command: ./bin/docker-entrypoint-worker.sh
    restart: unless-stopped
    volumes:
      - plane-logs-worker:/code/plane/logs
    environment:
      <<: [*app-env, *db-env, *redis-env, *minio-env, *aws-s3-env, *proxy-env]
    depends_on:
      - api
      - plane-mq
      - plane-minio

  beat-worker:
    image: makeplane/plane-backend:${APP_RELEASE:-stable}
    command: ./bin/docker-entrypoint-beat.sh
    restart: unless-stopped
    volumes:
      - plane-logs-beat:/code/plane/logs
    environment:
      <<: [*app-env, *db-env, *redis-env, *minio-env, *aws-s3-env, *proxy-env]
    depends_on:
      - api
      - plane-mq
      - plane-minio

  migrator:
    image: makeplane/plane-backend:${APP_RELEASE:-stable}
    command: ./bin/docker-entrypoint-migrator.sh
    restart: on-failure
    volumes:
      - plane-logs-migrator:/code/plane/logs
    environment:
      <<: [*app-env, *db-env, *redis-env, *minio-env, *aws-s3-env, *proxy-env]
    depends_on:
      - plane-mq
      - plane-minio

  plane-mq:
    image: rabbitmq:3.13.6-management-alpine
    restart: unless-stopped
    environment:
      <<: *mq-env
    volumes:
      - plane-mq-data:/var/lib/rabbitmq

  plane-minio:
    image: minio/minio:latest
    command: server /export --console-address ":9090"
    restart: unless-stopped
    environment:
      <<: *minio-env
    volumes:
      - plane-uploads:/export

volumes:
  plane-uploads:
  plane-logs-api:
  plane-logs-worker:
  plane-logs-beat:
  plane-logs-migrator:
  plane-mq-data:
  plane-proxy-config:
  plane-proxy-data:
EOF
}
