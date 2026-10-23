INSTALL_DISPLAY="Snipe-IT"
INSTALL_NOTES="Setup wizard appears on first visit — create admin account there."

pre_install() {
    zeltro_pull_image snipe/snipe-it
    echo-white "  Generating Snipe-IT APP_KEY ..."
    SNIPEIT_APP_KEY=$(docker run --rm snipe/snipe-it php artisan key:generate --show 2>/dev/null | tr -d '\r\n')
    if [ -z "$SNIPEIT_APP_KEY" ]; then
        echo-red "  Failed to generate APP_KEY. Is Docker running?"
        exit 1
    fi
    echo-green "  APP_KEY generated."
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS snipeit;"
}

write_files() {
    cat > docker-compose.yaml << EOF
services:
  snipe-it:
    image: snipe/snipe-it:latest
    restart: unless-stopped
    environment:
      APP_ENV: production
      APP_DEBUG: "false"
      APP_KEY: "$SNIPEIT_APP_KEY"
      APP_URL: http://snipe-it
      DB_CONNECTION: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_DATABASE: snipeit
      DB_USERNAME: root
      DB_PASSWORD: ""
      MAIL_DRIVER: log
    volumes:
      - snipeit-data:/var/lib/snipeit

volumes:
  snipeit-data:
EOF
}
