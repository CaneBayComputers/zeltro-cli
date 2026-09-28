INSTALL_DISPLAY="Ollama + Open WebUI"
INSTALL_CREDENTIALS="create the admin account on first visit (first user registered is the admin)"
INSTALL_NOTES="CPU-only Ollama with no preloaded model — pull one from the WebUI Models page (or via docker exec) before chatting."

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  ollama:
    image: ollama/ollama:0.32.5
    restart: unless-stopped
    environment:
      OLLAMA_HOST: 0.0.0.0:11434
      OLLAMA_KEEP_ALIVE: 5m
      OLLAMA_MAX_LOADED_MODELS: "1"
    volumes:
      - ollama-models:/root/.ollama

  openwebui-app:
    image: ghcr.io/open-webui/open-webui:v0.11.0
    restart: unless-stopped
    environment:
      WEBUI_SECRET_KEY: "$secret_key"
      ENABLE_OLLAMA_API: "true"
      OLLAMA_BASE_URL: http://ollama:11434
      ENABLE_OPENAI_API: "false"
      WEBUI_URL: http://ollama-with-open-webui
    volumes:
      - open-webui-data:/app/backend/data
    depends_on:
      - ollama

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - openwebui-app

volumes:
  ollama-models:
  open-webui-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 256M;
    location / {
        proxy_pass http://openwebui-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 900s;
    }
}
NGINX
}
