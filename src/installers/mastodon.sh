INSTALL_DISPLAY="Mastodon"
INSTALL_CREDENTIALS="Register on first visit — first account becomes admin"
INSTALL_NOTES="Federated social network. Runs migrations on first startup (~60s). Visit http://$PROJECT_NAME/ to create your account."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE mastodon_production;" 2>/dev/null || true
}

write_files() {
    local secret_key_base ar_det_key ar_deriv_salt ar_primary_key vapid_private vapid_public
    secret_key_base=$(openssl rand -hex 64)
    ar_det_key=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    ar_deriv_salt=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
    ar_primary_key=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)

    # Generate VAPID keys using the mastodon image
    local vapid_output
    vapid_output=$(docker run --rm \
        -e RAILS_ENV=production \
        -e SECRET_KEY_BASE=bootstrap \
        ghcr.io/mastodon/mastodon:v4.5.9 \
        bundle exec rake mastodon:webpush:generate_vapid_key 2>/dev/null)
    vapid_private=$(echo "$vapid_output" | grep VAPID_PRIVATE_KEY | cut -d= -f2)
    vapid_public=$(echo "$vapid_output" | grep VAPID_PUBLIC_KEY | cut -d= -f2)

    cat > .env.production << EOF
LOCAL_DOMAIN=mastodon
WEB_DOMAIN=mastodon
# LOCAL_DOMAIN/WEB_DOMAIN are the instance's permanent identity, so they stay a
# name. Rails only answers Hosts it knows, though, so the project IP -- filled
# in by zeltro install before the first boot -- is allowed as an alternate.
ALTERNATE_DOMAINS=__ZELTRO_IP__
STREAMING_API_BASE_URL=ws://__ZELTRO_IP__
LOCAL_HTTPS=false
FORCE_SSL=false

RAILS_ENV=production
NODE_ENV=production
RAILS_SERVE_STATIC_FILES=true
BIND=0.0.0.0
PORT=3000
TRUSTED_PROXY_IP=__ZELTRO_IP__/24

DB_HOST=zeltro-postgres
DB_PORT=5432
DB_NAME=mastodon_production
DB_USER=root
DB_PASS=password

REDIS_HOST=zeltro-redis
REDIS_PORT=6379

ES_ENABLED=false

SECRET_KEY_BASE=$secret_key_base
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$ar_det_key
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$ar_deriv_salt
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$ar_primary_key
VAPID_PRIVATE_KEY=$vapid_private
VAPID_PUBLIC_KEY=$vapid_public

SMTP_SERVER=localhost
SMTP_PORT=25
SMTP_FROM_ADDRESS=notifications@mastodon
SMTP_DELIVERY_METHOD=smtp
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  db-migrate:
    image: ghcr.io/mastodon/mastodon:v4.5.9
    restart: on-failure
    env_file: .env.production
    command: bundle exec rails db:migrate
    depends_on: []

  nginx:
    image: nginx:1.27-alpine
    restart: always
    depends_on:
      db-migrate:
        condition: service_completed_successfully
      mastodon-web:
        condition: service_healthy
      streaming:
        condition: service_healthy
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - mastodon-system:/mastodon/public/system:ro

  mastodon-web:
    image: ghcr.io/mastodon/mastodon:v4.5.9
    restart: always
    env_file: .env.production
    command: bundle exec puma -C config/puma.rb
    depends_on:
      db-migrate:
        condition: service_completed_successfully
    healthcheck:
      test:
        - CMD-SHELL
        - curl -s --noproxy localhost localhost:3000/health | grep -q 'OK' || exit 1
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    volumes:
      - mastodon-system:/mastodon/public/system

  streaming:
    image: ghcr.io/mastodon/mastodon-streaming:v4.5.9
    restart: always
    env_file: .env.production
    # .env.production sets PORT=3000 for the web process, and streaming reads
    # PORT too. Without this it listened on 3000, its healthcheck (and nginx)
    # looked on 4000, and nginx waited forever on a streaming that never
    # turned healthy.
    environment:
      PORT: "4000"
    command: node ./streaming/index.js
    depends_on:
      db-migrate:
        condition: service_completed_successfully
    healthcheck:
      test:
        - CMD-SHELL
        - curl -s --noproxy localhost localhost:4000/api/v1/streaming/health | grep -q 'OK' || exit 1
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  sidekiq:
    image: ghcr.io/mastodon/mastodon:v4.5.9
    restart: always
    env_file: .env.production
    command: bundle exec sidekiq
    depends_on:
      db-migrate:
        condition: service_completed_successfully
    volumes:
      - mastodon-system:/mastodon/public/system

volumes:
  mastodon-system:
EOF

    # X-Forwarded-Proto https: Mastodon's production config sets force_ssl
    # unconditionally (FORCE_SSL=false is not read), so a request it believes is
    # plain http is redirected to https://<host>/, where nothing listens. The
    # header comes from a trusted proxy (TRUSTED_PROXY_IP is the project /24).
    cat > nginx.conf << 'NGINX'
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name mastodon;
    client_max_body_size 80m;

    keepalive_timeout 70;

    location /system/ {
        alias /mastodon/public/system/;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location /api/v1/streaming {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_http_version 1.1;
        proxy_pass http://streaming:4000;
    }

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_http_version 1.1;
        proxy_pass http://mastodon-web:3000;
    }
}
NGINX
}
