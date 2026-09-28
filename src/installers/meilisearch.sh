INSTALL_DISPLAY="Meilisearch"

write_files() {
    local master_key
    master_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  meilisearch-app:
    image: getmeili/meilisearch:latest
    restart: unless-stopped
    environment:
      MEILI_ENV: production
      MEILI_MASTER_KEY: $master_key
    volumes:
      - meilisearch-data:/meili_data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - meilisearch-app

volumes:
  meilisearch-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://meilisearch-app:7700;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINX
}
