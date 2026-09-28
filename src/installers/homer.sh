INSTALL_DISPLAY="Homer"
INSTALL_NOTES="Edit ~/zeltro-projects/homer/assets/config.yml to customize your dashboard."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  homer-app:
    image: b4bz/homer:latest
    restart: unless-stopped
    environment:
      INIT_ASSETS: 1
    volumes:
      - homer-assets:/www/assets

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - homer-app

volumes:
  homer-assets:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://homer-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
