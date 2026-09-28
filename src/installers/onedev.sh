INSTALL_DISPLAY="OneDev"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="Git-over-SSH (port 6611) is not published — clone over HTTP."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE \"onedev\";" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  onedev-app:
    image: 1dev/server:16.4.1
    restart: unless-stopped
    environment:
      hibernate_dialect: io.onedev.server.persistence.PostgreSQLDialect
      hibernate_connection_driver_class: org.postgresql.Driver
      hibernate_connection_url: jdbc:postgresql://zeltro-postgres:5432/onedev
      hibernate_connection_username: root
      hibernate_connection_password: password
      initial_user: admin
      initial_password: admin123
      initial_email: admin@example.com
      initial_server_url: http://onedev
    volumes:
      - onedev-data:/opt/onedev

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - onedev-app

volumes:
  onedev-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 512M;
    location / {
        proxy_pass http://onedev-app:6610;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }
}
NGINX
}
