INSTALL_DISPLAY="Checkmate"
INSTALL_CREDENTIALS="Register on first visit"
INSTALL_NOTES="Uptime and infrastructure monitor (formerly BlueWave Uptime). Uses the shared MongoDB."

write_files() {
    local jwt_secret
    jwt_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  checkmate-app:
    image: ghcr.io/bluewave-labs/checkmate:3.10.0
    restart: unless-stopped
    environment:
      DB_CONNECTION_STRING: "mongodb://root:password@zeltro-mongo:27017/checkmate?authSource=admin"
      CLIENT_HOST: http://checkmate
      JWT_SECRET: "$jwt_secret"
      LOG_LEVEL: warn

  nginx:
    image: nginx:1.29-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - checkmate-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 32M;
    location / {
        proxy_pass http://checkmate-app:52345;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300;
    }
}
NGINX
}
