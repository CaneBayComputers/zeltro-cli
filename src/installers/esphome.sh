INSTALL_DISPLAY="ESPHome"
INSTALL_CREDENTIALS="admin / admin123"
INSTALL_NOTES="On bridge networking there is no mDNS: devices need a fixed use_address/manual_ip or they show no status."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  esphome-app:
    image: ghcr.io/esphome/esphome:2026.7.3
    restart: unless-stopped
    environment:
      ESPHOME_USERNAME: admin
      ESPHOME_PASSWORD: admin123
      ESPHOME_TRUSTED_DOMAINS: "__ZELTRO_PROJECT__,__ZELTRO_IP__"
      TZ: UTC
    volumes:
      - esphome-config:/config
      - esphome-cache:/cache

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - esphome-app

volumes:
  esphome-config:
  esphome-cache:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://esphome-app:6052;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400s;
        proxy_buffering off;
    }
}
NGINX
}
