INSTALL_DISPLAY="PG Back Web"
INSTALL_CREDENTIALS="Create the first user on first visit"
INSTALL_NOTES="Add zeltro-postgres as a backup source with: postgresql://root:password@zeltro-postgres:5432/<db>?sslmode=disable"

pre_install() {
    docker exec -e PGPASSWORD=password zeltro-postgres psql -U root -d postgres \
      -c "CREATE DATABASE \"pgbackweb\";" 2>/dev/null || true
}

write_files() {
    local encryption_key

    encryption_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  pgbackweb-app:
    image: eduardolat/pgbackweb:0.5.1
    restart: unless-stopped
    environment:
      PBW_ENCRYPTION_KEY: "$encryption_key"
      PBW_POSTGRES_CONN_STRING: "postgresql://root:password@zeltro-postgres:5432/pgbackweb?sslmode=disable"
      TZ: UTC
    volumes:
      - pgbackweb-backups:/backups

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - pgbackweb-app

volumes:
  pgbackweb-backups:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 0;
    location / {
        proxy_pass http://pgbackweb-app:8085;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_buffering off;
    }
}
NGINX
}
