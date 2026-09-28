INSTALL_DISPLAY="Jellyfin"
INSTALL_NOTES="Complete the setup wizard on first visit. Add media libraries after creating your admin account."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  jellyfin-app:
    image: jellyfin/jellyfin:latest
    restart: unless-stopped
    volumes:
      - jellyfin-config:/config
      - jellyfin-cache:/cache
      - ./media:/media

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - jellyfin-app

volumes:
  jellyfin-config:
  jellyfin-cache:
EOF

    mkdir -p media

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://jellyfin-app:8096;
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
