INSTALL_DISPLAY="Vikunja"
INSTALL_NOTES="First user to register becomes admin."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS vikunja;"
}

write_files() {
    local secret
    secret=$(openssl rand -hex 32)

    # Vikunja's process runs as uid 1000, but Docker creates a named volume
    # owned by root — the app then crash-loops on
    # "storage validation failed: permission denied [process uid=1000, dir owner uid=0]".
    # A bind mount inside the project is writable, keeps uploads with the
    # project like every other Zeltro data path, and can be chmod'd here.
    mkdir -p files
    chmod 777 files

    cat > docker-compose.yaml << EOF
services:
  vikunja-app:
    image: vikunja/vikunja:2.4.0
    restart: unless-stopped
    environment:
      VIKUNJA_DATABASE_TYPE: mysql
      VIKUNJA_DATABASE_HOST: zeltro-mariadb
      VIKUNJA_DATABASE_USER: root
      VIKUNJA_DATABASE_PASSWORD: ""
      VIKUNJA_DATABASE_DATABASE: vikunja
      VIKUNJA_SERVICE_SECRET: "$secret"
      VIKUNJA_SERVICE_PUBLICURL: http://vikunja/
      VIKUNJA_SERVICE_FRONTENDURL: http://vikunja/
    volumes:
      - ./files:/app/vikunja/files

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - vikunja-app

EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://vikunja-app:3456;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
