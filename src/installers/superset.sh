INSTALL_DISPLAY="Apache Superset"
INSTALL_CREDENTIALS="admin / admin"
INSTALL_NOTES="First startup takes ~2 minutes while Superset runs migrations and builds the UI. Visit http://$PROJECT_NAME/ when ready."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE superset;" 2>/dev/null || true
}

write_files() {
    local secret_key
    secret_key=$(openssl rand -hex 32)

    # Superset needs psycopg2-binary added (not included in the base image)
    cat > Dockerfile << 'DOCKEREOF'
FROM apache/superset:latest
USER root
RUN uv pip install --python /app/.venv/bin/python --no-cache psycopg2-binary
USER superset
DOCKEREOF

    mkdir -p superset
    cat > superset/superset_config.py << 'PYEOF'
import os

SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]
SQLALCHEMY_DATABASE_URI = os.environ["DATABASE_URL"]
ENABLE_PROXY_FIX = True
WTF_CSRF_ENABLED = True
TALISMAN_ENABLED = False
PYEOF

    cat > docker-compose.yaml << EOF
services:
  superset-app:
    build:
      context: .
      dockerfile: Dockerfile
    restart: unless-stopped
    environment:
      SUPERSET_CONFIG_PATH: /app/pythonpath/superset_config.py
      SUPERSET_SECRET_KEY: $secret_key
      DATABASE_URL: postgresql+psycopg2://root:password@zeltro-postgres:5432/superset
      SUPERSET_ADMIN_USERNAME: admin
      SUPERSET_ADMIN_PASSWORD: admin
      SUPERSET_ADMIN_FIRSTNAME: Zeltro
      SUPERSET_ADMIN_LASTNAME: Admin
      SUPERSET_ADMIN_EMAIL: admin@example.com
    command: >
      /bin/sh -c "
        superset db upgrade &&
        (superset fab create-admin
          --username admin
          --firstname Zeltro
          --lastname Admin
          --email admin@example.com
          --password admin || true) &&
        superset init &&
        gunicorn --bind 0.0.0.0:8088 --workers 2 --worker-class gthread --threads 8 --timeout 120 'superset.app:create_app()'
      "
    volumes:
      - ./superset/superset_config.py:/app/pythonpath/superset_config.py:ro
      - superset-home:/app/superset_home

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - superset-app

volumes:
  superset-home:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://superset-app:8088;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
}
NGINX
}
