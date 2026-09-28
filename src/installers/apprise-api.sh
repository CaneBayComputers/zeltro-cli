INSTALL_DISPLAY="Apprise API"
INSTALL_CREDENTIALS="no login required"
INSTALL_NOTES="Save a config under a key at http://apprise-api/, then notify with: curl -X POST -d 'body=hi' http://apprise-api/notify/<key>"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  notifier:
    image: caronc/apprise:v1.5.1
    restart: unless-stopped
    environment:
      APPRISE_STATEFUL_MODE: simple
      APPRISE_WORKER_COUNT: "1"
      APPRISE_ADMIN: "yes"
      TZ: UTC
    volumes:
      - apprise-config:/config
      - apprise-attach:/attach
      - apprise-plugin:/plugin

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - notifier

volumes:
  apprise-config:
  apprise-attach:
  apprise-plugin:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://notifier:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
}
NGINX
}
