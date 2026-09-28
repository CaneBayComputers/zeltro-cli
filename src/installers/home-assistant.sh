INSTALL_DISPLAY="Home Assistant"
INSTALL_NOTES="First visit shows the onboarding wizard. Reverse-proxy headers are pre-configured."

write_files() {
    # configuration.yaml below uses !include for automations/scripts/scenes and
    # a themes directory. If those are missing, HA fails to load the whole file
    # and falls back to defaults — which means the http: block is ignored and
    # every proxied request is rejected with 400:
    #   "A request from a reverse proxy was received ... but your HTTP
    #    integration is not set-up for reverse proxies"
    # Create them so the config actually applies.
    mkdir -p config/themes
    printf '[]\n' > config/automations.yaml
    printf '{}\n' > config/scripts.yaml
    printf '[]\n' > config/scenes.yaml

    cat > config/configuration.yaml << 'EOF'
default_config:

frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.0.0.0/8
EOF

    cat > docker-compose.yaml << 'EOF'
services:
  home-assistant-app:
    image: ghcr.io/home-assistant/home-assistant:stable
    restart: unless-stopped
    environment:
      TZ: UTC
    volumes:
      - ./config:/config

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - home-assistant-app
EOF

    cat > nginx.conf << 'NGINX'
map $request_method $ha_proxy_method {
    default $request_method;
    HEAD GET;
}

server {
    listen 80;
    location / {
        proxy_pass http://home-assistant-app:8123;
        proxy_method $ha_proxy_method;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
}
