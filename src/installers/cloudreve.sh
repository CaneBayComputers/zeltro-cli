INSTALL_DISPLAY="Cloudreve"
INSTALL_CREDENTIALS="register on first visit — the first account registered becomes the administrator"
INSTALL_NOTES="No seeded admin and no password in the logs since v4 — sign up first, that account is the admin."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"cloudreve\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  cloudreve-app:
    image: cloudreve/cloudreve:4.18.0
    restart: unless-stopped
    environment:
      CR_CONF_Database.Type: postgres
      CR_CONF_Database.Host: zeltro-postgres
      CR_CONF_Database.Port: 5432
      CR_CONF_Database.User: root
      CR_CONF_Database.Password: password
      CR_CONF_Database.Name: cloudreve
      CR_CONF_Redis.Server: zeltro-redis:6379
      CR_CONF_Redis.DB: 4
      CR_CONF_System.ProxyHeader: X-Forwarded-For
      CR_CONF_OptionOverwrite.siteURL: http://cloudreve
    volumes:
      - cloudreve-data:/cloudreve/data

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - cloudreve-app

volumes:
  cloudreve-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://cloudreve-app:5212;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
        proxy_read_timeout 600s;
    }
}
NGINX
}
