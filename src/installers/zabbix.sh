INSTALL_DISPLAY="Zabbix"
INSTALL_CREDENTIALS="Admin / zabbix"
INSTALL_NOTES="Enterprise monitoring platform. First startup takes ~60 seconds for database initialization."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE zabbix;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  zabbix-server:
    image: zabbix/zabbix-server-pgsql:alpine-latest
    restart: unless-stopped
    environment:
      DB_SERVER_HOST: zeltro-postgres
      DB_SERVER_PORT: "5432"
      POSTGRES_DB: zabbix
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      ZBX_LISTENPORT: "10051"

  zabbix-web:
    image: zabbix/zabbix-web-nginx-pgsql:alpine-latest
    restart: unless-stopped
    depends_on:
      - zabbix-server
    environment:
      DB_SERVER_HOST: zeltro-postgres
      DB_SERVER_PORT: "5432"
      POSTGRES_DB: zabbix
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      ZBX_SERVER_HOST: zabbix-server
      ZBX_SERVER_PORT: "10051"
      PHP_TZ: UTC
      ZBX_SERVER_NAME: Zabbix

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - zabbix-web
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://zabbix-web:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
