INSTALL_DISPLAY="Lychee"
INSTALL_NOTES="Install wizard appears on first visit at /install/admin — create admin account there."

pre_install() {
    echo-white "  Generating Lychee APP_KEY..."
    LYCHEE_APP_KEY="base64:$(openssl rand -base64 32)"
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE DATABASE IF NOT EXISTS lychee;
        CREATE USER IF NOT EXISTS 'lychee'@'%' IDENTIFIED BY 'lycheepass';
        ALTER USER 'lychee'@'%' IDENTIFIED BY 'lycheepass';
        GRANT ALL PRIVILEGES ON lychee.* TO 'lychee'@'%';
        FLUSH PRIVILEGES;
    "
}

write_files() {
    cat > docker-compose.yaml << EOF
services:
  lychee-app:
    image: lycheeorg/lychee:latest
    restart: unless-stopped
    environment:
      DB_CONNECTION: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_DATABASE: lychee
      DB_USERNAME: lychee
      DB_PASSWORD: "lycheepass"
      APP_URL: http://lychee
      APP_KEY: "$LYCHEE_APP_KEY"
      TIMEZONE: UTC
    volumes:
      - lychee-uploads:/var/www/html/public/uploads
      - lychee-sym:/var/www/html/public/sym

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - lychee-app

volumes:
  lychee-uploads:
  lychee-sym:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://lychee-app:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
