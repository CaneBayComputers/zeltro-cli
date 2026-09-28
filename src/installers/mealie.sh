INSTALL_DISPLAY="Mealie"
INSTALL_CREDENTIALS="changeme@example.com / MyPassword"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  mealie-app:
    image: ghcr.io/mealie-recipes/mealie:latest
    restart: unless-stopped
    environment:
      BASE_URL: http://mealie
      ALLOW_SIGNUP: "true"
      TZ: UTC
    volumes:
      - mealie-data:/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - mealie-app

volumes:
  mealie-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://mealie-app:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
