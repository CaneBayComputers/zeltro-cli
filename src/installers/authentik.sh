INSTALL_DISPLAY="authentik"
INSTALL_CREDENTIALS="akadmin / admin123 (finish setup at http://authentik/if/flow/initial-setup/)"
INSTALL_NOTES="The worker container is required — it applies the blueprints that create the default login flows."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"authentik\";" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -base64 60 | tr -d '\n')

    cat > docker-compose.yaml << EOF
services:
  authentik-server:
    image: ghcr.io/goauthentik/server:2026.5.6
    restart: unless-stopped
    command: server
    environment:
      AUTHENTIK_SECRET_KEY: "$secret_key"
      AUTHENTIK_POSTGRESQL__HOST: zeltro-postgres
      AUTHENTIK_POSTGRESQL__PORT: 5432
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__USER: root
      AUTHENTIK_POSTGRESQL__PASSWORD: password
      AUTHENTIK_ERROR_REPORTING__ENABLED: "false"
      AUTHENTIK_DISABLE_UPDATE_CHECK: "true"
      AUTHENTIK_EMAIL__HOST: zeltro-mailhog
      AUTHENTIK_EMAIL__PORT: 1025
      AUTHENTIK_EMAIL__USE_TLS: "false"
      AUTHENTIK_EMAIL__FROM: authentik@example.com
      AUTHENTIK_BOOTSTRAP_PASSWORD: admin123
      AUTHENTIK_BOOTSTRAP_EMAIL: admin@example.com
    volumes:
      - authentik-media:/media
      - authentik-templates:/templates

  authentik-worker:
    image: ghcr.io/goauthentik/server:2026.5.6
    restart: unless-stopped
    command: worker
    user: root
    environment:
      AUTHENTIK_SECRET_KEY: "$secret_key"
      AUTHENTIK_POSTGRESQL__HOST: zeltro-postgres
      AUTHENTIK_POSTGRESQL__PORT: 5432
      AUTHENTIK_POSTGRESQL__NAME: authentik
      AUTHENTIK_POSTGRESQL__USER: root
      AUTHENTIK_POSTGRESQL__PASSWORD: password
      AUTHENTIK_ERROR_REPORTING__ENABLED: "false"
      AUTHENTIK_DISABLE_UPDATE_CHECK: "true"
      AUTHENTIK_EMAIL__HOST: zeltro-mailhog
      AUTHENTIK_EMAIL__PORT: 1025
      AUTHENTIK_EMAIL__USE_TLS: "false"
      AUTHENTIK_EMAIL__FROM: authentik@example.com
      AUTHENTIK_BOOTSTRAP_PASSWORD: admin123
      AUTHENTIK_BOOTSTRAP_EMAIL: admin@example.com
    volumes:
      - authentik-media:/media
      - authentik-templates:/templates
      - authentik-certs:/certs

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - authentik-server

volumes:
  authentik-media:
  authentik-templates:
  authentik-certs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://authentik-server:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
