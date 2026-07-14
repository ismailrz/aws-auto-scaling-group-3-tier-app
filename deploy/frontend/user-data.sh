#!/bin/bash
# Runs on EVERY boot via the Launch Template "user data" field.
# Frontend has no runtime secrets — VITE_API_URL was already baked in at build
# time — this just sets the port Nitro's node-server listens on.
set -euo pipefail

cat > /etc/todo-frontend.env <<EOF
PORT=3000
HOST=0.0.0.0
EOF

systemctl daemon-reload
systemctl enable --now todo-frontend
