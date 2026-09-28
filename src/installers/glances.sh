INSTALL_DISPLAY="Glances"
INSTALL_NOTES="No login required. Monitors the host system and all Docker containers."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  glances-app:
    image: nicolargo/glances:latest-full
    restart: unless-stopped
    pid: host
    environment:
      GLANCES_OPT: -w
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - glances-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://glances-app:61208;
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
