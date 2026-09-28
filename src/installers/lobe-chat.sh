INSTALL_DISPLAY="LobeChat"
INSTALL_CREDENTIALS="none — set ACCESS_CODE in the compose environment if you want a gate"
INSTALL_NOTES="Client-database edition: conversations live in your browser's IndexedDB, so clearing site data wipes them."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  lobe-chat-app:
    image: lobehub/lobe-chat:1.143.3
    restart: unless-stopped
    environment:
      PORT: "3210"
      APP_URL: http://lobe-chat
      ACCESS_CODE: ""

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - lobe-chat-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 128M;
    location / {
        proxy_pass http://lobe-chat-app:3210;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
