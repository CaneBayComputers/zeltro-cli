INSTALL_DISPLAY="PhotoPrism"
INSTALL_CREDENTIALS="admin / admin1234"
INSTALL_NOTES="Place photos in ~/zeltro-projects/photoprism/originals/ then run 'zeltro exec photoprism-app photoprism index' to index them."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS photoprism;"
}

write_files() {
    mkdir -p originals storage

    cat > docker-compose.yaml << 'EOF'
services:
  photoprism-app:
    image: photoprism/photoprism:latest
    restart: unless-stopped
    environment:
      PHOTOPRISM_AUTH_MODE: password
      PHOTOPRISM_SITE_URL: http://photoprism/
      PHOTOPRISM_ADMIN_USER: admin
      PHOTOPRISM_ADMIN_PASSWORD: admin1234
      PHOTOPRISM_DATABASE_DRIVER: mysql
      PHOTOPRISM_DATABASE_SERVER: zeltro-mariadb:3306
      PHOTOPRISM_DATABASE_NAME: photoprism
      PHOTOPRISM_DATABASE_USER: root
      PHOTOPRISM_DATABASE_PASSWORD: ""
    volumes:
      - ./originals:/photoprism/originals
      - ./storage:/photoprism/storage

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - photoprism-app
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 500M;
    location / {
        proxy_pass http://photoprism-app:2342;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
