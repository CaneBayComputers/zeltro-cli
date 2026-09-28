INSTALL_DISPLAY="Listmonk"
INSTALL_CREDENTIALS="admin / admin12345"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE listmonk;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  listmonk-app:
    image: listmonk/listmonk:latest
    restart: unless-stopped
    command:
      - sh
      - -c
      - >
        ./listmonk --install --idempotent --yes --config '' &&
        ./listmonk --upgrade --yes --config '' &&
        ./listmonk --config ''
    environment:
      TZ: UTC
      LISTMONK_app__address: 0.0.0.0:9000
      LISTMONK_db__host: zeltro-postgres
      LISTMONK_db__port: 5432
      LISTMONK_db__user: root
      LISTMONK_db__password: password
      LISTMONK_db__database: listmonk
      LISTMONK_db__ssl_mode: disable
      LISTMONK_ADMIN_USER: admin
      LISTMONK_ADMIN_PASSWORD: admin12345
    volumes:
      - listmonk-uploads:/listmonk/uploads

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - listmonk-app

volumes:
  listmonk-uploads:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 50M;
    location / {
        proxy_pass http://listmonk-app:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
