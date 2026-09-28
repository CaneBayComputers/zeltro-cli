INSTALL_DISPLAY="Ghost"
INSTALL_NOTES="Admin panel is at http://$PROJECT_NAME/ghost/ — create the owner account on first visit."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  ghost-app:
    image: ghost:latest
    restart: unless-stopped
    environment:
      url: http://ghost
      NODE_ENV: development
      database__client: sqlite3
      database__connection__filename: /var/lib/ghost/content/data/ghost.db
      database__useNullAsDefault: "true"
    volumes:
      - ghost-content:/var/lib/ghost/content

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - ghost-app

volumes:
  ghost-content:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://ghost-app:2368;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
