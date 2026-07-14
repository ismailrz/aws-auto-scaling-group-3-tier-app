#!/bin/bash
# Runs on EVERY boot via the Launch Template "user data" field. Rendered by
# Terraform (templatefile in launch_templates.tf) — the values below come
# from the RDS instance and the CORS origin computed in locals.tf, not from
# anything hardcoded in this repo.
set -euo pipefail

SECRET_ID="${db_secret_arn}"
REGION="${aws_region}"

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query SecretString --output text)

DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)

cat > /etc/todo-backend.env <<EOF
DATABASE_URL=postgresql+psycopg2://$${DB_USER}:$${DB_PASS}@${db_host}:${db_port}/${db_name}
CORS_ORIGINS=${cors_origins}
EOF
chmod 600 /etc/todo-backend.env

systemctl daemon-reload
systemctl enable --now todo-backend
