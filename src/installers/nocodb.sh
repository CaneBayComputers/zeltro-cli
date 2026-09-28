INSTALL_DISPLAY="NocoDB"
INSTALL_CREDENTIALS="Set admin credentials on first visit"
INSTALL_NOTES="Open-source Airtable alternative. First user to register becomes admin."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE nocodb;" 2>/dev/null || true
}

write_files() {
    local jwt_secret
    jwt_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  nocodb-app:
    image: nocodb/nocodb:latest
    restart: unless-stopped
    environment:
      NC_DB: "pg://zeltro-postgres:5432?u=root&p=password&d=nocodb"
      NC_AUTH_JWT_SECRET: $jwt_secret
      NC_PUBLIC_URL: http://nocodb
    volumes:
      - nocodb-data:/usr/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - nocodb-app

volumes:
  nocodb-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://nocodb-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
