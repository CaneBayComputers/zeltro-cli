INSTALL_DISPLAY="Glance"
INSTALL_NOTES="Dashboard layout is driven by ./glance.yml in the project directory; Glance auto-reloads it on save."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  glance-app:
    image: glanceapp/glance:v0.8.5
    restart: unless-stopped
    environment:
      TZ: Etc/UTC
    volumes:
      - ./glance.yml:/app/config/glance.yml
      - glance-assets:/app/assets

  nginx:
    image: nginx:1.30.4-alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - glance-app

volumes:
  glance-assets:
EOF

    cat > glance.yml << 'GLANCE'
server:
  host: 0.0.0.0
  port: 8080
  proxied: true

pages:
  - name: Home
    columns:
      - size: small
        widgets:
          - type: calendar
            first-day-of-week: monday

          - type: bookmarks
            groups:
              - title: Zeltro
                links:
                  - title: Zeltro CLI
                    url: https://zeltro.build/
                  - title: Zeltro on GitHub
                    url: https://github.com/CaneBayComputers/zeltro-cli

      - size: full
        widgets:
          - type: search
            autofocus: true

          - type: group
            widgets:
              - type: hacker-news
              - type: lobsters
GLANCE

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    location / {
        proxy_pass http://glance-app:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
}
