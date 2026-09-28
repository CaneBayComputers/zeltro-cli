INSTALL_DISPLAY="GOWA (Go WhatsApp Web Multidevice)"
INSTALL_CREDENTIALS="admin / admin123 (HTTP basic auth)"
INSTALL_NOTES="Link a phone by scanning the QR code at /app/login; session data lives in the gowa-storages volume."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  gowa-app:
    image: aldinokemal2104/go-whatsapp-web-multidevice:v9.0.0
    restart: unless-stopped
    command: ["rest", "--port=3000"]
    environment:
      APP_PORT: "3000"
      APP_DEBUG: "false"
      APP_OS: Zeltro
      APP_BASIC_AUTH: admin:admin123
      DB_URI: file:storages/whatsapp.db?_foreign_keys=on
    volumes:
      - gowa-storages:/app/storages
      - gowa-statics:/app/statics

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - gowa-app

volumes:
  gowa-storages:
  gowa-statics:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://gowa-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
