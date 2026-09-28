INSTALL_DISPLAY="Trilium Notes (TriliumNext)"
INSTALL_CREDENTIALS="Set your login password on first visit"
INSTALL_NOTES="The maintained successor to zadam/trilium; data lives in the triliumnext-data volume."
INSTALL_READY_RETRIES=30

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  triliumnext-app:
    image: ghcr.io/triliumnext/trilium:v0.104.1
    restart: unless-stopped
    environment:
      TRILIUM_DATA_DIR: /home/node/trilium-data
    volumes:
      - triliumnext-data:/home/node/trilium-data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - triliumnext-app

volumes:
  triliumnext-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 500M;
    location / {
        proxy_pass http://triliumnext-app:8080;
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
