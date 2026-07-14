#!/bin/bash
# Run ONCE on a temporary "builder" EC2 instance to produce the golden AMI for the
# frontend tier. After this finishes, stop the instance and create an AMI from it —
# do not leave this instance running as a production node.
#
# VITE_API_URL is a Vite build-time env var — it gets inlined into the client
# bundle, so it MUST point at the real backend address here, before
# `npm run build`. Use your real API domain if you have one
# (https://api.yourdomain.com), otherwise the ALB's own DNS name
# (http://<your-alb-dns-name>, no trailing path) — see DEPLOYMENT.md's
# "Domain vs. no domain".
set -euo pipefail

REPO_URL="git@github.com:ismailrz/aws-auto-scaling-group-3-tier-app.git"

sudo dnf install -y nodejs20 git

id -u todo &>/dev/null || sudo useradd --system --create-home --home-dir /opt/todo --shell /sbin/nologin todo

sudo git clone --depth 1 "$REPO_URL" /opt/todo-src
sudo mkdir -p /opt/todo
sudo cp -r /opt/todo-src/frontend /opt/todo/frontend
sudo rm -rf /opt/todo-src

cd /opt/todo/frontend
export VITE_API_URL="https://api.yourdomain.com"
sudo -E npm ci
sudo -E npm run build

sudo chown -R todo:todo /opt/todo/frontend

sudo tee /etc/systemd/system/todo-frontend.service >/dev/null <<'UNIT'
[Unit]
Description=Todo frontend (TanStack Start / Nitro node-server)
After=network.target

[Service]
Type=simple
User=todo
Group=todo
WorkingDirectory=/opt/todo/frontend
EnvironmentFile=/etc/todo-frontend.env
ExecStart=/usr/bin/node /opt/todo/frontend/.output/server/index.mjs
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/todo/frontend
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable todo-frontend

echo "Golden AMI prep complete. Stop this instance and create an AMI from it."
