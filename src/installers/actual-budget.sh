INSTALL_DISPLAY="Actual Budget"
INSTALL_NOTES="Set an optional server password on first visit to restrict access."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  actual-budget-app:
    image: actualbudget/actual-server:latest
    restart: unless-stopped
    volumes:
      - actual-budget-data:/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - actual-budget-app

volumes:
  actual-budget-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://actual-budget-app:5006;
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
