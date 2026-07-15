#!/bin/bash
# Run ONCE on a temporary "builder" EC2 instance to produce the golden AMI for the
# backend tier. After this finishes, stop the instance and create an AMI from it —
# do not leave this instance running as a production node.
set -euo pipefail

REPO_URL="https://github.com/ismailrz/aws-auto-scaling-group-3-tier-app.git"

sudo dnf install -y python3.12 python3.12-pip git jq

id -u todo &>/dev/null || sudo useradd --system --create-home --home-dir /opt/todo --shell /sbin/nologin todo

sudo git clone --depth 1 "$REPO_URL" /opt/todo-src
sudo mkdir -p /opt/todo
sudo cp -r /opt/todo-src/backend /opt/todo/backend
sudo rm -rf /opt/todo-src

cd /opt/todo/backend
sudo python3.12 -m venv .venv
sudo ./.venv/bin/pip install --upgrade pip
sudo ./.venv/bin/pip install -r requirements.txt

sudo chown -R todo:todo /opt/todo/backend

sudo tee /etc/systemd/system/todo-backend.service >/dev/null <<'UNIT'
[Unit]
Description=Todo backend (FastAPI/uvicorn)
After=network.target

[Service]
Type=simple
User=todo
Group=todo
WorkingDirectory=/opt/todo/backend
EnvironmentFile=/etc/todo-backend.env
ExecStart=/opt/todo/backend/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/todo/backend
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
# Enable, but do NOT start: /etc/todo-backend.env only exists once user-data
# (which fetches DATABASE_URL from Secrets Manager) has run on first real boot.
sudo systemctl enable todo-backend

echo "Golden AMI prep complete. Stop this instance and create an AMI from it."
