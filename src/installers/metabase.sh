INSTALL_DISPLAY="Metabase"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to complete setup. First startup takes ~60 seconds for JVM initialization."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  metabase-app:
    image: metabase/metabase:latest
    restart: unless-stopped
    environment:
      MB_DB_TYPE: h2
      MB_DB_FILE: /metabase-data/metabase.db
      JAVA_TIMEZONE: UTC
    volumes:
      - metabase-data:/metabase-data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - metabase-app

volumes:
  metabase-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://metabase-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
    }
}
NGINX
}
