INSTALL_DISPLAY="Jupyter Notebook (Python)"
INSTALL_CREDENTIALS="No login — token authentication is disabled for local dev"
INSTALL_NOTES="Notebooks live in /home/jovyan/work (persisted). The image ships numpy, pandas, matplotlib, scikit-learn."

write_files() {
    cat > docker-compose.yaml << 'EOF'
services:
  jupyter-app:
    image: quay.io/jupyter/scipy-notebook:2026-08-03
    restart: unless-stopped
    # Exec form avoids shell quoting games: an empty token disables auth.
    command: ["start-notebook.py", "--IdentityProvider.token=", "--ServerApp.allow_remote_access=True", "--ServerApp.root_dir=/home/jovyan/work"]
    environment:
      DOCKER_STACKS_JUPYTER_CMD: notebook
      RESTARTABLE: "yes"
    volumes:
      - jupyter-work:/home/jovyan/work

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - jupyter-app

volumes:
  jupyter-work:
EOF

    cat > nginx.conf << 'NGINX'
server {
    listen 80;
    client_max_body_size 200M;
    location / {
        proxy_pass http://jupyter-app:8888;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_buffering off;
    }
}
NGINX
}
