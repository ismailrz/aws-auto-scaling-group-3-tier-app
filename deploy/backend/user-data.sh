#!/bin/bash
# Runs on EVERY boot via the Launch Template "user data" field.
# Fetches the DB credentials from Secrets Manager (never baked into the AMI)
# and starts the service.
set -euo pipefail

SECRET_ID="todo/backend/database-url"
REGION="us-east-1"

DATABASE_URL=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query SecretString --output text)

# CORS_ORIGINS: use your real frontend domain if you have one
# (https://app.yourdomain.com), otherwise the ALB's own DNS name
# (http://<your-alb-dns-name>) — see DEPLOYMENT.md's "Domain vs. no domain".
cat > /etc/todo-backend.env <<EOF
DATABASE_URL=${DATABASE_URL}
CORS_ORIGINS=https://app.yourdomain.com
EOF
chmod 600 /etc/todo-backend.env

systemctl daemon-reload
systemctl enable --now todo-backend
