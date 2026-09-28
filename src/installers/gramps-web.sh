INSTALL_DISPLAY="Gramps Web"
INSTALL_CREDENTIALS="create the owner account on first visit"
INSTALL_NOTES="First boot creates an empty family tree; the first account you register becomes the tree owner."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  gramps-web-app:
    image: ghcr.io/gramps-project/grampsweb:26.7.1
    restart: unless-stopped
    environment:
      GRAMPSWEB_TREE: "Gramps Web"
      GRAMPSWEB_BASE_URL: http://gramps-web
      GRAMPSWEB_CELERY_CONFIG__broker_url: redis://zeltro-redis:6379/10
      GRAMPSWEB_CELERY_CONFIG__result_backend: redis://zeltro-redis:6379/10
      GRAMPSWEB_RATELIMIT_STORAGE_URI: redis://zeltro-redis:6379/11
    volumes:
      - gramps-users:/app/users
      - gramps-index:/app/indexdir
      - gramps-thumb-cache:/app/thumbnail_cache
      - gramps-cache:/app/cache
      - gramps-secret:/app/secret
      - gramps-db:/root/.gramps/grampsdb
      - gramps-media:/app/media
      - gramps-tmp:/tmp

  gramps-web-celery:
    image: ghcr.io/gramps-project/grampsweb:26.7.1
    restart: unless-stopped
    command: celery -A gramps_webapi.celery worker --loglevel=INFO --concurrency=2
    depends_on:
      - gramps-web-app
    environment:
      GRAMPSWEB_TREE: "Gramps Web"
      GRAMPSWEB_BASE_URL: http://gramps-web
      GRAMPSWEB_CELERY_CONFIG__broker_url: redis://zeltro-redis:6379/10
      GRAMPSWEB_CELERY_CONFIG__result_backend: redis://zeltro-redis:6379/10
      GRAMPSWEB_RATELIMIT_STORAGE_URI: redis://zeltro-redis:6379/11
    volumes:
      - gramps-users:/app/users
      - gramps-index:/app/indexdir
      - gramps-thumb-cache:/app/thumbnail_cache
      - gramps-cache:/app/cache
      - gramps-secret:/app/secret
      - gramps-db:/root/.gramps/grampsdb
      - gramps-media:/app/media
      - gramps-tmp:/tmp

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - gramps-web-app

volumes:
  gramps-users:
  gramps-index:
  gramps-thumb-cache:
  gramps-cache:
  gramps-secret:
  gramps-db:
  gramps-media:
  gramps-tmp:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 500M;
    location / {
        proxy_pass http://gramps-web-app:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINX
}
