INSTALL_DISPLAY="Flipt"
INSTALL_CREDENTIALS="no login — auth is disabled by default"
INSTALL_NOTES="Storage must be set to 'local' explicitly; Flipt v2 defaults to an in-memory backend that loses every flag on restart."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  flipt-app:
    image: flipt/flipt:v2.11.0
    restart: unless-stopped
    environment:
      FLIPT_STORAGE_DEFAULT_BACKEND_TYPE: local
      FLIPT_STORAGE_DEFAULT_BACKEND_PATH: /var/opt/flipt
      FLIPT_META_TELEMETRY_ENABLED: "false"
      FLIPT_META_CHECK_FOR_UPDATES: "false"
      FLIPT_LOG_LEVEL: info
    volumes:
      - flipt-data:/var/opt/flipt

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - flipt-app

volumes:
  flipt-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://flipt-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
