INSTALL_DISPLAY="Fider"
INSTALL_CREDENTIALS="Create the admin account on first visit"
INSTALL_NOTES="Outgoing mail goes to MailHog; sign-in links appear there rather than in a real inbox."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE fider;" 2>/dev/null || true
}

write_files() {
    local jwt_secret
    jwt_secret=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  fider-app:
    image: getfider/fider:v0.36.0
    restart: unless-stopped
    environment:
      BASE_URL: http://fider
      DATABASE_URL: postgres://root:password@zeltro-postgres:5432/fider?sslmode=disable
      JWT_SECRET: "$jwt_secret"
      EMAIL_NOREPLY: noreply@fider.local
      EMAIL_SMTP_HOST: zeltro-mailhog
      EMAIL_SMTP_PORT: 1025
      EMAIL_SMTP_USERNAME: ""
      EMAIL_SMTP_PASSWORD: ""
      ALLOW_PRIVATE_NETWORK_TARGETS: "true"

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - fider-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 20M;
    location / {
        proxy_pass http://fider-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
