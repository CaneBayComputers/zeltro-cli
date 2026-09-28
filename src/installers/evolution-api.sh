INSTALL_DISPLAY="Evolution API"
INSTALL_CREDENTIALS="API key: evolution123 (log in at http://evolution-api/manager)"
INSTALL_NOTES="Prisma migrations run at startup; if the database is unreachable the container exits instead of serving."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE evolution_api;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  evolution-app:
    image: evoapicloud/evolution-api:v2.3.7
    restart: unless-stopped
    environment:
      SERVER_TYPE: http
      SERVER_PORT: "8080"
      SERVER_URL: http://evolution-api
      AUTHENTICATION_API_KEY: evolution123
      DATABASE_PROVIDER: postgresql
      DATABASE_CONNECTION_URI: postgresql://root:password@zeltro-postgres:5432/evolution_api?schema=evolution_api
      DATABASE_CONNECTION_CLIENT_NAME: evolution_exchange
      DATABASE_SAVE_DATA_INSTANCE: "true"
      DATABASE_SAVE_DATA_NEW_MESSAGE: "true"
      DATABASE_SAVE_MESSAGE_UPDATE: "true"
      DATABASE_SAVE_DATA_CONTACTS: "true"
      DATABASE_SAVE_DATA_CHATS: "true"
      DATABASE_SAVE_DATA_LABELS: "true"
      DATABASE_SAVE_DATA_HISTORIC: "true"
      CACHE_REDIS_ENABLED: "true"
      CACHE_REDIS_URI: redis://zeltro-redis:6379/8
      CACHE_REDIS_PREFIX_KEY: evolution
      CACHE_REDIS_SAVE_INSTANCES: "false"
      CACHE_LOCAL_ENABLED: "false"
      CONFIG_SESSION_PHONE_CLIENT: Evolution API
      CONFIG_SESSION_PHONE_NAME: Chrome
      LOG_LEVEL: ERROR
      DEL_INSTANCE: "false"
    volumes:
      - evolution-instances:/evolution/instances

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - evolution-app

volumes:
  evolution-instances:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://evolution-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
}
