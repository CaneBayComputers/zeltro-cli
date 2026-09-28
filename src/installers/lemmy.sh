INSTALL_DISPLAY="Lemmy"
INSTALL_CREDENTIALS="lemmy / lemmylemmy (admin account created on first start)"
INSTALL_NOTES="Federated link aggregator (Reddit alternative). Admin account set in lemmy.hjson setup block."

pre_install() {
    docker exec zeltro-postgres psql -U root -d postgres -c "CREATE DATABASE lemmy;" 2>/dev/null || true
}

write_files() {
    cat > docker-compose.yaml << 'EOF'
x-logging: &default-logging
  driver: "json-file"
  options:
    max-size: "50m"
    max-file: "4"

services:
  nginx:
    image: nginx:1-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./proxy_params:/etc/nginx/proxy_params:ro
    depends_on:
      - lemmy-backend
      - lemmy-ui

  lemmy-backend:
    image: dessalines/lemmy:0.19.18
    restart: unless-stopped
    environment:
      RUST_LOG: warn
    volumes:
      - ./lemmy.hjson:/config/config.hjson:ro
    depends_on:
      - pictrs
    logging: *default-logging

  lemmy-ui:
    image: dessalines/lemmy-ui:0.19.18
    restart: unless-stopped
    environment:
      LEMMY_UI_LEMMY_INTERNAL_HOST: lemmy-backend:8536
      LEMMY_UI_LEMMY_EXTERNAL_HOST: __ZELTRO_IP__
      LEMMY_UI_HTTPS: "false"
    depends_on:
      - lemmy-backend
    logging: *default-logging

  pictrs:
    image: asonix/pictrs:0.5.23
    hostname: pictrs
    restart: unless-stopped
    environment:
      PICTRS__SERVER__API_KEY: zeltro-pictrs-key
      RUST_BACKTRACE: full
      PICTRS__MEDIA__VIDEO__VIDEO_CODEC: vp9
      PICTRS__MEDIA__ANIMATION__MAX_WIDTH: 256
      PICTRS__MEDIA__ANIMATION__MAX_HEIGHT: 256
      PICTRS__MEDIA__ANIMATION__MAX_FRAME_COUNT: 400
    user: 991:991
    volumes:
      - lemmy-pictrs-data:/mnt
    logging: *default-logging

volumes:
  lemmy-pictrs-data:
EOF

    cat > nginx.conf << 'NGINX'
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=5s;

    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;

    map "$request_method:$http_accept" $proxpass {
        default "http://lemmy-ui:1234";
        "~^(?:GET|HEAD):.*?application\/(?:activity|ld)\+json" "http://lemmy-backend:8536";
        "~^(?!(GET|HEAD)).*:" "http://lemmy-backend:8536";
    }

    server {
        set $lemmy_ui "lemmy-ui:1234";
        set $lemmy_backend "lemmy-backend:8536";

        listen 80;
        server_name lemmy;
        server_tokens off;
        client_max_body_size 20M;

        include proxy_params;

        location / {
            proxy_pass $proxpass;
            rewrite ^(.+)/+$ $1 permanent;
        }

        location = /.well-known/security.txt {
            proxy_pass "http://$lemmy_ui";
        }

        location ~ ^/(api|pictrs|feeds|nodeinfo|.well-known|version|sitemap.xml) {
            proxy_pass "http://$lemmy_backend";
            include proxy_params;
        }
    }
}
NGINX

    cat > proxy_params << 'PARAMS'
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Server $host;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
PARAMS

    cat > lemmy.hjson << 'HJSON'
{
  setup: {
    admin_username: "lemmy"
    admin_password: "lemmylemmy"
    site_name: "lemmy"
  }

  database: {
    uri: "postgresql://root:password@zeltro-postgres:5432/lemmy"
  }

  hostname: "lemmy"
  bind: "0.0.0.0"
  port: 8536
  tls_enabled: false
  cors_origin: "http://lemmy"

  pictrs: {
    url: "http://pictrs:8080/"
    api_key: "zeltro-pictrs-key"
  }
}
HJSON
}
