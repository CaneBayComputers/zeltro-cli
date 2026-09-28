INSTALL_DISPLAY="Grafana"
INSTALL_CREDENTIALS="admin / admin"

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  grafana-app:
    image: grafana/grafana:latest
    restart: unless-stopped
    environment:
      GF_SERVER_ROOT_URL: http://grafana/
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - grafana-data:/var/lib/grafana

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - grafana-app

volumes:
  grafana-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://grafana-app:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
