INSTALL_DISPLAY="Onetime Secret"
INSTALL_CREDENTIALS="anonymous use needs no login — see notes to create an admin"
INSTALL_NOTES="Create an admin with: docker exec onetimesecret-app bin/ots customers create you@example.com --role colonel"

write_files() {
    local app_secret
    app_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  onetimesecret-app:
    image: onetimesecret/onetimesecret:v0.26.3
    container_name: onetimesecret-app
    restart: unless-stopped
    environment:
      RACK_ENV: production
      REDIS_URL: redis://zeltro-redis:6379/0
      VALKEY_URL: redis://zeltro-redis:6379/0
      SECRET: "$app_secret"
      HOST: onetimesecret
      SSL: "false"
      AUTHENTICATION_MODE: simple

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - onetimesecret-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://onetimesecret-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }
}
NGINX
}
