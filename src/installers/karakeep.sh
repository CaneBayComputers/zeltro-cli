INSTALL_DISPLAY="Karakeep"
INSTALL_CREDENTIALS="Register on first visit — the first account is the admin"
INSTALL_NOTES="Ships its own Meilisearch and headless Chrome sidecars; AI tagging stays off unless you set OPENAI_API_KEY."
INSTALL_READY_RETRIES=40

write_files() {
    local nextauth_secret meili_key
    nextauth_secret=$(openssl rand -hex 32)
    meili_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  karakeep-app:
    image: ghcr.io/karakeep-app/karakeep:0.33.1
    restart: unless-stopped
    environment:
      DATA_DIR: /data
      NEXTAUTH_SECRET: "$nextauth_secret"
      NEXTAUTH_URL: http://karakeep
      MEILI_ADDR: http://meilisearch:7700
      MEILI_MASTER_KEY: "$meili_key"
      BROWSER_WEB_URL: http://chrome:9222
      DISABLE_NEW_RELEASE_CHECK: "true"
    volumes:
      - karakeep-data:/data
    depends_on:
      - meilisearch

  meilisearch:
    image: getmeili/meilisearch:v1.41.0
    restart: unless-stopped
    environment:
      MEILI_NO_ANALYTICS: "true"
      MEILI_MASTER_KEY: "$meili_key"
    volumes:
      - karakeep-meili:/meili_data

  chrome:
    image: zenika/alpine-chrome:124
    restart: unless-stopped
    command:
      - --no-sandbox
      - --disable-gpu
      - --disable-dev-shm-usage
      - --remote-debugging-address=0.0.0.0
      - --remote-debugging-port=9222
      - --hide-scrollbars
      - --disable-blink-features=AutomationControlled
      - --window-size=1440,900

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - karakeep-app

volumes:
  karakeep-data:
  karakeep-meili:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://karakeep-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
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
