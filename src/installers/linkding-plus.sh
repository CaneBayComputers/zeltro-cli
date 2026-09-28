INSTALL_DISPLAY="linkding (plus)"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="The 'plus' image bundles Chromium for HTML snapshots — enable archiving per-bookmark or globally in Settings."

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"linkding_plus\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  linkding-app:
    image: sissbruecker/linkding:1.45.0-plus
    restart: unless-stopped
    environment:
      LD_SUPERUSER_NAME: admin
      LD_SUPERUSER_PASSWORD: admin123
      LD_DB_ENGINE: postgres
      LD_DB_HOST: zeltro-postgres
      LD_DB_PORT: "5432"
      LD_DB_DATABASE: linkding_plus
      LD_DB_USER: root
      LD_DB_PASSWORD: password
      LD_CSRF_TRUSTED_ORIGINS: http://linkding-plus
      LD_ENABLE_SNAPSHOTS: "True"
    volumes:
      - linkding-data:/etc/linkding/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - linkding-app

volumes:
  linkding-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://linkding-app:9090;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
