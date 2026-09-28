INSTALL_DISPLAY="Label Studio"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to create your account on first launch."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  label-studio-app:
    image: heartexlabs/label-studio:latest
    restart: unless-stopped
    environment:
      # DJANGO_DB must be "sqlite" — using "default" causes it to try PostgreSQL
      DJANGO_DB: sqlite
      LOCAL_FILES_SERVING_ENABLED: "true"
    volumes:
      - label-studio-data:/label-studio/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - label-studio-app

volumes:
  label-studio-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://label-studio-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINX
}
