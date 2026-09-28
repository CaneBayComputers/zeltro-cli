INSTALL_DISPLAY="n8n"
INSTALL_NOTES="Create the owner account on first visit."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  n8n-app:
    image: n8nio/n8n:latest
    restart: unless-stopped
    environment:
      N8N_HOST: __ZELTRO_IP__
      N8N_PORT: 5678
      N8N_PROTOCOL: http
      # The auth cookie is Secure by default, which a browser never sends back
      # over plain http://<ip>/, so the owner could not stay signed in.
      N8N_SECURE_COOKIE: "false"
      WEBHOOK_URL: http://n8n/
      GENERIC_TIMEZONE: UTC
    volumes:
      - n8n-data:/home/node/.n8n

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - n8n-app

volumes:
  n8n-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://n8n-app:5678;
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
