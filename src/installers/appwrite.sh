INSTALL_DISPLAY="Appwrite"
INSTALL_NOTES="Visit http://$PROJECT_NAME/ to create your first admin account. Background workers are not included — use for API/SDK development and testing."

pre_install() {
    docker exec zeltro-mariadb mariadb -u root -e "CREATE DATABASE IF NOT EXISTS appwrite CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

write_files() {
    local openssl_key
    openssl_key=$(openssl rand -hex 32)

    cat > docker-compose.yaml << EOF
services:
  appwrite-app:
    image: appwrite/appwrite:1.5.7
    restart: unless-stopped
    environment:
      _APP_ENV: production
      _APP_WORKER_PER_CORE: "6"
      _APP_OPENSSL_KEY_V1: $openssl_key
      _APP_DOMAIN: __ZELTRO_IP__
      _APP_DOMAIN_FUNCTIONS: functions.appwrite
      _APP_DOMAIN_TARGET: __ZELTRO_IP__
      _APP_DOMAIN_TARGET_CNAME: appwrite
      _APP_OPTIONS_FORCE_HTTPS: disabled
      _APP_DB_HOST: zeltro-mariadb
      _APP_DB_PORT: "3306"
      _APP_DB_SCHEMA: appwrite
      _APP_DB_USER: root
      _APP_DB_PASS: ""
      _APP_REDIS_HOST: zeltro-redis
      _APP_REDIS_PORT: "6379"
      _APP_SMTP_HOST: zeltro-mailhog
      _APP_SMTP_PORT: "1025"
      _APP_STORAGE_LIMIT: "30000000"
      _APP_FUNCTIONS_SIZE_LIMIT: "30000000"
      _APP_FUNCTIONS_TIMEOUT: "900"
      _APP_FUNCTIONS_BUILD_TIMEOUT: "900"
    volumes:
      - appwrite-uploads:/storage/uploads
      - appwrite-cache:/storage/cache
      - appwrite-config:/storage/config
      - appwrite-certificates:/storage/certificates
      - appwrite-functions:/storage/functions

volumes:
  appwrite-uploads:
  appwrite-cache:
  appwrite-config:
  appwrite-certificates:
  appwrite-functions:
EOF
}
