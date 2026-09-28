INSTALL_DISPLAY="Langflow"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="First boot builds the component index and can take 1-2 minutes before the UI answers."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE langflow;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  langflow-app:
    image: langflowai/langflow:1.11.2
    restart: unless-stopped
    environment:
      LANGFLOW_HOST: 0.0.0.0
      LANGFLOW_PORT: "7860"
      LANGFLOW_DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/langflow
      LANGFLOW_CONFIG_DIR: /app/langflow
      LANGFLOW_AUTO_LOGIN: "false"
      LANGFLOW_SUPERUSER: admin
      LANGFLOW_SUPERUSER_PASSWORD: admin123
      LANGFLOW_SECRET_KEY: "$secret_key"
      DO_NOT_TRACK: "true"
    volumes:
      - langflow-data:/app/langflow

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - langflow-app

volumes:
  langflow-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 256M;
    location / {
        proxy_pass http://langflow-app:7860;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
