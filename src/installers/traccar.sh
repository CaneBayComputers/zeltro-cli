INSTALL_DISPLAY="Traccar"
INSTALL_CREDENTIALS="admin / admin"
INSTALL_NOTES="Web UI only — the GPS device protocol ports (5000-5150) are not published, so real trackers cannot report in."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  traccar-app:
    image: traccar/traccar:6.14.5
    restart: unless-stopped
    volumes:
      - traccar-data:/opt/traccar/data
      - traccar-logs:/opt/traccar/logs

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - traccar-app

volumes:
  traccar-data:
  traccar-logs:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 64M;
    location / {
        proxy_pass http://traccar-app:8082;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
    }
}
NGINX
}
