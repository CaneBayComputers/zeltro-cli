INSTALL_DISPLAY="Moodle"
INSTALL_CREDENTIALS="admin / Admin123!"
INSTALL_NOTES="First boot runs the Moodle CLI installer and can take 3-5 minutes before the site responds."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE DATABASE IF NOT EXISTS moodle CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS 'moodle'@'%' IDENTIFIED BY 'moodle';
        ALTER USER 'moodle'@'%' IDENTIFIED BY 'moodle';
        GRANT ALL PRIVILEGES ON moodle.* TO 'moodle'@'%';
        FLUSH PRIVILEGES;
    "
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  moodle-app:
    image: erseco/alpine-moodle:v5.2.1
    restart: unless-stopped
    environment:
      DB_TYPE: mariadb
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_NAME: moodle
      DB_USER: moodle
      DB_PASS: moodle
      DB_PREFIX: mdl_
      SITE_URL: http://moodle
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: "Admin123!"
      MOODLE_EMAIL: admin@example.com
      MOODLE_SITENAME: Moodle
      SMTP_HOST: zeltro-mailhog
      SMTP_PORT: 1025
      SMTP_SECURITY: ""
    volumes:
      - moodle-data:/var/www/moodledata

  nginx:
    image: nginx:1.30-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - moodle-app

volumes:
  moodle-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://moodle-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
NGINX
}
