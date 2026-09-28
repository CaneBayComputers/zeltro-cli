INSTALL_DISPLAY="SuperTokens Core"
INSTALL_CREDENTIALS="no login — headless auth API; GET http://supertokens/hello returns Hello"
INSTALL_NOTES="This is the SuperTokens core only. There is no web UI: point your app's SuperTokens backend SDK at http://supertokens as the connectionURI."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"supertokens\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  supertokens-core:
    image: supertokens/supertokens-postgresql:12.0.9
    restart: unless-stopped
    environment:
      POSTGRESQL_CONNECTION_URI: "postgresql://root:password@zeltro-postgres:5432/supertokens"
      DISABLE_TELEMETRY: "true"

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - supertokens-core
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;

    # Root is not an API path on the core; surface the health endpoint there
    # so http://supertokens/ answers 200 instead of 404.
    location = / {
        proxy_pass http://supertokens-core:3567/hello;
        proxy_set_header Host $http_host;
    }

    location / {
        proxy_pass http://supertokens-core:3567;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
