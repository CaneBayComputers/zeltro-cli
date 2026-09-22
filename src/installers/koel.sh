INSTALL_DISPLAY="Koel"
INSTALL_CREDENTIALS="admin@example.com / KoelAdmin123"
INSTALL_NOTES="Place your music files in the koel-music volume then scan from the admin panel at http://$PROJECT_NAME/."

# Shared between pre_install and write_files
KOEL_APP_KEY="base64:$(openssl rand -base64 32)"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE koel;" 2>/dev/null || true

    # Koel's init writes back to .env; bind-mounting the file fails due to AppArmor on the host.
    # Write .env inside the ephemeral container and run koel:init there, then use SKIP_INIT for the main container.
    docker run --rm --network "$(zeltro_network_name)" \
        --entrypoint /bin/sh \
        phanan/koel:latest \
        -c "cat > /var/www/html/.env << 'ENVEOF'
APP_KEY=$KOEL_APP_KEY
APP_URL=http://koel
DB_CONNECTION=pgsql
DB_HOST=zeltro-postgres
DB_PORT=5432
DB_DATABASE=koel
DB_USERNAME=root
DB_PASSWORD=password
FORCE_HTTPS=false
ADMIN_EMAIL=admin@example.com
ADMIN_NAME=Admin
ADMIN_PASSWORD=KoelAdmin123
MEMORY_LIMIT=512
ENVEOF
php artisan koel:init --no-assets --no-interaction" 2>/dev/null || true
}

write_files() {
    cat > .env << ENV
APP_KEY=$KOEL_APP_KEY
APP_URL=http://koel
DB_CONNECTION=pgsql
DB_HOST=zeltro-postgres
DB_PORT=5432
DB_DATABASE=koel
DB_USERNAME=root
DB_PASSWORD=password
FORCE_HTTPS=false
ADMIN_EMAIL=admin@example.com
ADMIN_NAME=Admin
ADMIN_PASSWORD=KoelAdmin123
MEMORY_LIMIT=512
ENV

    cat > docker-compose.yaml << 'EOF'
services:
  koel-app:
    image: phanan/koel:latest
    restart: unless-stopped
    env_file: ./.env
    environment:
      SKIP_INIT: "1"
    volumes:
      - koel-music:/music
      - koel-search-indexes:/var/www/html/storage/search-indexes

volumes:
  koel-music:
  koel-search-indexes:
EOF
}
