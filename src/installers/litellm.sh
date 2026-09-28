INSTALL_DISPLAY="LiteLLM Proxy"
INSTALL_CREDENTIALS="admin / admin123 at http://$PROJECT_NAME/ui/"
INSTALL_NOTES="The master key is written to litellm-master-key.txt in the project directory — clients send it as the OpenAI API key."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE litellm;" 2>/dev/null || true
}

write_files() {
    local master_key salt_key

    master_key="sk-$(openssl rand -hex 24)"
    salt_key="sk-$(openssl rand -hex 24)"

    printf '%s\n' "$master_key" > litellm-master-key.txt

    cat > docker-compose.yaml << EOF
services:
  litellm-app:
    image: ghcr.io/berriai/litellm:v1.95.0
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://root:password@zeltro-postgres:5432/litellm
      STORE_MODEL_IN_DB: "True"
      LITELLM_MASTER_KEY: "$master_key"
      LITELLM_SALT_KEY: "$salt_key"
      UI_USERNAME: admin
      UI_PASSWORD: admin123
      REDIS_URL: redis://zeltro-redis:6379/7
      LITELLM_MODE: PRODUCTION
      LITELLM_LOG: INFO

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - litellm-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 128M;
    location / {
        proxy_pass http://litellm-app:4000;
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
