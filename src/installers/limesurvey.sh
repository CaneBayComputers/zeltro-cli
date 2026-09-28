INSTALL_DISPLAY="LimeSurvey"
INSTALL_CREDENTIALS="admin / admin123"

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE DATABASE IF NOT EXISTS limesurvey;
        CREATE USER IF NOT EXISTS 'limesurvey'@'%' IDENTIFIED BY 'limesurvey';
        ALTER USER 'limesurvey'@'%' IDENTIFIED BY 'limesurvey';
        GRANT ALL PRIVILEGES ON limesurvey.* TO 'limesurvey'@'%';
        FLUSH PRIVILEGES;
    "
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  limesurvey-app:
    image: martialblog/limesurvey:latest
    restart: unless-stopped
    environment:
      DB_TYPE: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_NAME: limesurvey
      DB_USERNAME: limesurvey
      DB_PASSWORD: "limesurvey"
      ADMIN_USER: admin
      ADMIN_NAME: Administrator
      ADMIN_EMAIL: admin@example.com
      ADMIN_PASSWORD: admin123
      PUBLIC_URL: http://limesurvey
    volumes:
      - limesurvey-upload:/var/www/html/upload

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - limesurvey-app

volumes:
  limesurvey-upload:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://limesurvey-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
