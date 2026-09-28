INSTALL_DISPLAY="Open WebUI"
INSTALL_NOTES="Create your first admin account on first visit. Ollama integration is disabled by default."

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  open-webui-app:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    environment:
      WEBUI_SECRET_KEY: $secret_key
      ENABLE_OLLAMA_API: "false"
      OLLAMA_BASE_URL: ""
    volumes:
      - open-webui-data:/app/backend/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - open-webui-app

volumes:
  open-webui-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://open-webui-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
