INSTALL_DISPLAY="Nextcloud"
INSTALL_NOTES="Complete the admin account setup on first visit."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  nextcloud-app:
    image: nextcloud:latest
    restart: unless-stopped
    environment:
      MYSQL_HOST: zeltro-mariadb
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: root
      MYSQL_PASSWORD: ""
      REDIS_HOST: zeltro-redis
      REDIS_HOST_PORT: 6379
      # Space-separated. The IP is how a browser on this machine reaches it,
      # the project name is how other containers do. No OVERWRITEHOST: it made
      # every generated link (and the post-login redirect) http://nextcloud/.
      NEXTCLOUD_TRUSTED_DOMAINS: "__ZELTRO_PROJECT__ __ZELTRO_IP__"
      OVERWRITEPROTOCOL: http
    volumes:
      - nextcloud-data:/var/www/html

volumes:
  nextcloud-data:
EOF
}
