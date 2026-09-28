INSTALL_DISPLAY="FileFlows"
INSTALL_CREDENTIALS="no login by default — open the dashboard and start configuring"
INSTALL_NOTES="Server-only install: put media under the fileflows-media volume. The image is ~1 GB, so the first pull is slow."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  fileflows-app:
    image: revenz/fileflows:26.07
    restart: unless-stopped
    environment:
      TZ: UTC
    volumes:
      - fileflows-data:/app/Data
      - fileflows-logs:/app/Logs
      - fileflows-temp:/temp
      - fileflows-media:/media

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - fileflows-app

volumes:
  fileflows-data:
  fileflows-logs:
  fileflows-temp:
  fileflows-media:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 2G;
    location / {
        proxy_pass http://fileflows-app:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_request_buffering off;
    }
}
NGINX
}
