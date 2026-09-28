INSTALL_DISPLAY="Pixelfed"
INSTALL_CREDENTIALS="register at http://$PROJECT_NAME/register (first account, then promote it with: zeltro exec-root php artisan user:admin <username>)"
INSTALL_NOTES="Federated image-sharing platform. First boot runs migrations and can take ~2 minutes. Email is wired to MailHog, so activation links land at http://zeltro-mailhog:8025/."

pre_install() {
    # Pixelfed will not migrate into a database that does not exist yet.
    docker exec zeltro-mariadb mariadb -uroot -e "CREATE DATABASE IF NOT EXISTS \`pixelfed\`;" 2>/dev/null || true
}

# Pixelfed runs several hundred migrations against an empty database on first
# boot — measured at ~210s — so the default 75s readiness window is far too short.
INSTALL_READY_RETRIES=60

write_files() {
    APP_KEY="base64:$(head -c 32 /dev/urandom | base64)"

    cat > docker-compose.yaml << COMPOSE
services:
  app:
    image: zknt/pixelfed:20260706
    restart: unless-stopped
    environment:
      APP_NAME: "$PROJECT_NAME"
      APP_ENV: production
      APP_KEY: "$APP_KEY"
      APP_DEBUG: "false"
      APP_URL: "http://$PROJECT_NAME"
      # Pixelfed binds its routes to these domains, so a browser on any other
      # Host gets 404 for every page. __ZELTRO_IP__ is filled in by zeltro install
      # with the project's address before the first boot.
      APP_DOMAIN: "__ZELTRO_IP__"
      ADMIN_DOMAIN: "__ZELTRO_IP__"
      SESSION_DOMAIN: "__ZELTRO_IP__"
      TRUST_PROXIES: "*"
      DB_CONNECTION: mysql
      DB_HOST: zeltro-mariadb
      DB_PORT: "3306"
      DB_DATABASE: pixelfed
      DB_USERNAME: root
      DB_PASSWORD: ""
      REDIS_HOST: zeltro-redis
      REDIS_PORT: "6379"
      CACHE_DRIVER: redis
      QUEUE_DRIVER: redis
      SESSION_DRIVER: redis
      MAIL_DRIVER: smtp
      MAIL_HOST: zeltro-mailhog
      MAIL_PORT: "1025"
      # Needs a TLD or Pixelfed's validator rejects it and the container
      # crash-loops. .test is reserved for exactly this. MailHog catches it anyway.
      MAIL_FROM_ADDRESS: "pixelfed@$PROJECT_NAME.test"
      MAIL_FROM_NAME: "$PROJECT_NAME"
      MAIL_ENCRYPTION: "null"
      OPEN_REGISTRATION: "true"
      ENFORCE_EMAIL_VERIFICATION: "false"
    volumes:
      # storage/ holds uploaded media and must persist. bootstrap/ deliberately
      # does NOT: it contains Laravel's cached config, so persisting it pins a
      # stale config across container recreation — a bad value survives the fix.
      - pixelfed-storage:/var/www/storage

volumes:
  pixelfed-storage:
COMPOSE
}
