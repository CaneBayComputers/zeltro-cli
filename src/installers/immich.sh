INSTALL_DISPLAY="Immich"
INSTALL_NOTES="First user to register becomes admin. Allow 30+ seconds after startup for migrations."

write_files() {
    mkdir -p upload pgdata

    cat > docker-compose.yaml << 'EOF'
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    restart: unless-stopped
    environment:
      DB_HOSTNAME: immich-db
      DB_USERNAME: postgres
      DB_PASSWORD: postgres
      DB_DATABASE_NAME: immich
      REDIS_HOSTNAME: zeltro-redis
    volumes:
      - ./upload:/usr/src/app/upload
    depends_on:
      - immich-db

  immich-db:
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: immich
    volumes:
      - ./pgdata:/var/lib/postgresql/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - immich-server
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 500M;
    location / {
        proxy_pass http://immich-server:2283;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }
}
NGINX
}
