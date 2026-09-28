INSTALL_DISPLAY="Uptime Kuma"
INSTALL_NOTES="Create your admin account on first visit."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  uptime-kuma-app:
    image: louislam/uptime-kuma:1
    restart: unless-stopped
    volumes:
      - uptime-kuma-data:/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - uptime-kuma-app

volumes:
  uptime-kuma-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://uptime-kuma-app:3001;
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
