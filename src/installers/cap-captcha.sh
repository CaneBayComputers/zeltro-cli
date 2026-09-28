INSTALL_DISPLAY="Cap (CAPTCHA)"
INSTALL_CREDENTIALS="admin key: zeltro-cap-admin-key"
INSTALL_NOTES="The admin key IS the dashboard login; all state lives in the shared Redis under the 'cap:' prefix."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  cap-app:
    image: tiago2/cap:3.1.9
    restart: unless-stopped
    environment:
      ADMIN_KEY: zeltro-cap-admin-key
      SERVER_PORT: "3000"
      SERVER_HOSTNAME: 0.0.0.0
      REDIS_URL: redis://zeltro-redis:6379/9
      REDIS_PREFIX: "cap:"
      CORS_ORIGIN: "*"
    volumes:
      - cap-data:/usr/src/app/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - cap-app

volumes:
  cap-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 10M;
    location / {
        proxy_pass http://cap-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
