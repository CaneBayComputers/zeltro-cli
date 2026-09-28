INSTALL_DISPLAY="Graylog"
INSTALL_CREDENTIALS="admin / admin"
INSTALL_NOTES="First startup takes ~90 seconds while OpenSearch and Graylog initialize. Visit http://$PROJECT_NAME/ after startup."

write_files() {
    local password_secret root_password_sha2
    password_secret=$(openssl rand -hex 16)
    # SHA-256 of "admin"
    root_password_sha2="8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918"

    cat > docker-compose.yaml << EOF
services:
  graylog-opensearch:
    image: opensearchproject/opensearch:2.4.0
    restart: unless-stopped
    environment:
      discovery.type: single-node
      OPENSEARCH_JAVA_OPTS: -Xms512m -Xmx512m
      DISABLE_INSTALL_DEMO_CONFIG: "true"
      DISABLE_SECURITY_PLUGIN: "true"
    volumes:
      - graylog-opensearch-data:/usr/share/opensearch/data
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536

  graylog-app:
    image: graylog/graylog:6.0
    restart: unless-stopped
    depends_on:
      - graylog-opensearch
    environment:
      GRAYLOG_PASSWORD_SECRET: $password_secret
      GRAYLOG_ROOT_PASSWORD_SHA2: $root_password_sha2
      GRAYLOG_HTTP_EXTERNAL_URI: http://graylog/
      GRAYLOG_MONGODB_URI: mongodb://root:password@zeltro-mongo:27017/graylog?authSource=admin
      GRAYLOG_ELASTICSEARCH_HOSTS: http://graylog-opensearch:9200
    volumes:
      - graylog-data:/usr/share/graylog/data

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - graylog-app

volumes:
  graylog-opensearch-data:
  graylog-data:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 100M;
    location / {
        proxy_pass http://graylog-app:9000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Graylog-Server-URL http://graylog/;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
