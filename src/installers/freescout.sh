INSTALL_DISPLAY="FreeScout"
INSTALL_CREDENTIALS="admin@freescout.local / freescout-admin"
INSTALL_NOTES="Help desk / shared inbox. First boot takes a few minutes. FreeScout answers 403 Untrusted Host on any address other than APP_URL, which zeltro install sets to the project IP, so open it there (not the LAN address)."
INSTALL_READY_RETRIES=60

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS freescout CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    # FreeScout requires a dedicated DB user — the image rejects root
    docker exec zeltro-mariadb mariadb -u root -e "
        CREATE USER IF NOT EXISTS 'freescout'@'%' IDENTIFIED BY 'freescout';
        ALTER USER 'freescout'@'%' IDENTIFIED BY 'freescout';
        GRANT ALL PRIVILEGES ON freescout.* TO 'freescout'@'%';
        FLUSH PRIVILEGES;
    "
}

# nfrastack/freescout is the 2.x continuation of tiredofit/freescout, which is
# gone from Docker Hub. 2.x renamed SITE_URL to APP_URL, moved the log volume
# from /www/logs to /logs, and wants FreeScout's own settings prefixed with
# FREESCOUT_ (DISPLAY_ERRORS -> FREESCOUT_APP_DEBUG, APPLICATION_NAME ->
# FREESCOUT_APPLICATION_NAME).
write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  freescout-app:
    image: nfrastack/freescout:2.2.14
    restart: unless-stopped
    environment:
      ADMIN_EMAIL: admin@freescout.local
      ADMIN_FIRST_NAME: Admin
      ADMIN_LAST_NAME: User
      ADMIN_PASS: freescout-admin
      APP_URL: http://freescout
      SETUP_TYPE: AUTO
      DB_TYPE: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: 3306
      DB_NAME: freescout
      DB_USER: freescout
      DB_PASS: freescout
      DB_SSL: "FALSE"
      ENABLE_AUTO_UPDATE: "FALSE"
      FREESCOUT_APPLICATION_NAME: FreeScout
      FREESCOUT_APP_DEBUG: "false"
      FREESCOUT_APP_TIMEZONE: UTC
    volumes:
      - freescout-data:/data
      - freescout-logs:/logs

volumes:
  freescout-data:
  freescout-logs:
EOF
}
