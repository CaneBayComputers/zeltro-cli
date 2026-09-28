INSTALL_DISPLAY="Homarr"
INSTALL_CREDENTIALS="create the admin account with the onboarding wizard on first visit"
INSTALL_NOTES="SECRET_ENCRYPTION_KEY is generated at install time — losing it makes stored integration credentials unreadable."

write_files() {
    local encryption_key
    encryption_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  homarr-app:
    image: ghcr.io/homarr-labs/homarr:v1.73.0
    restart: unless-stopped
    environment:
      SECRET_ENCRYPTION_KEY: "$encryption_key"
      AUTH_PROVIDERS: credentials
      TZ: Etc/UTC
    volumes:
      - homarr-appdata:/appdata

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - homarr-app

volumes:
  homarr-appdata:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://homarr-app:7575;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
