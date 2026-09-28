INSTALL_DISPLAY="Tolgee"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="Tolgee's embedded Postgres is disabled — it uses the shared zeltro-postgres instead."

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"tolgee\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  tolgee-app:
    image: tolgee/tolgee:v3.216.4
    restart: unless-stopped
    environment:
      TOLGEE_POSTGRES_AUTOSTART_ENABLED: "false"
      SPRING_DATASOURCE_URL: jdbc:postgresql://zeltro-postgres:5432/tolgee
      SPRING_DATASOURCE_USERNAME: root
      SPRING_DATASOURCE_PASSWORD: password
      TOLGEE_AUTHENTICATION_ENABLED: "true"
      TOLGEE_AUTHENTICATION_INITIAL_USERNAME: admin
      TOLGEE_AUTHENTICATION_INITIAL_PASSWORD: admin123
      TOLGEE_FRONT_END_URL: http://tolgee
      TOLGEE_FILE_STORAGE_FS_DATA_PATH: /data
      SERVER_PORT: "8080"
    volumes:
      - tolgee-data:/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - tolgee-app

volumes:
  tolgee-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://tolgee-app:8080;
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
