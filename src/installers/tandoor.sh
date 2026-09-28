INSTALL_DISPLAY="Tandoor Recipes"
INSTALL_NOTES="Create the admin user via: zeltro exec python3 manage.py createsuperuser"

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE tandoor;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 25)

    cat > docker-compose.yaml << EOF
services:
  tandoor-app:
    image: vabene1111/recipes:latest
    restart: unless-stopped
    environment:
      SECRET_KEY: "$secret_key"
      DB_ENGINE: django.db.backends.postgresql
      POSTGRES_HOST: zeltro-postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: root
      POSTGRES_PASSWORD: password
      POSTGRES_DB: tandoor
      ALLOWED_HOSTS: "*"
      CSRF_TRUSTED_ORIGINS: http://tandoor
      GUNICORN_MEDIA: 1
      DEBUG: 0
    volumes:
      - tandoor-staticfiles:/opt/recipes/staticfiles
      - tandoor-mediafiles:/opt/recipes/mediafiles

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - tandoor-staticfiles:/static:ro
      - tandoor-mediafiles:/media:ro
    depends_on:
      - tandoor-app

volumes:
  tandoor-staticfiles:
  tandoor-mediafiles:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;

    location /static/ {
        alias /static/;
    }

    location /media/ {
        alias /media/;
    }

    location / {
        proxy_pass http://tandoor-app:80;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX
}
