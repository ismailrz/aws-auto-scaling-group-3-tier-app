#!/bin/bash
# Bakes a golden AMI for one tier (backend or frontend) end-to-end:
# launches a temporary builder EC2 instance in the VPC Terraform created,
# runs the matching bootstrap-ami.sh on it via SSM (no SSH needed), images
# it, and terminates the builder. Prints the resulting AMI ID at the end —
# put that into terraform/terraform.tfvars.
#
# Usage:
#   deploy/bake-ami.sh backend
#   deploy/bake-ami.sh frontend http://todo-alb-695255760.us-east-1.elb.amazonaws.com
#
# Requires: AWS CLI configured (respects AWS_PROFILE/--profile via the
# environment), and the Terraform in terraform/ already applied at least
# far enough to have the VPC, public subnets, and todo-backend/todo-frontend
# IAM instance profiles created.
set -euo pipefail

TIER="${1:-}"
VITE_API_URL="${2:-}"

if [[ "$TIER" != "backend" && "$TIER" != "frontend" ]]; then
  echo "Usage: $0 <backend|frontend> [vite_api_url]" >&2
  echo "  vite_api_url is required (and only used) for frontend, e.g.:" >&2
  echo "  $0 frontend http://todo-alb-695255760.us-east-1.elb.amazonaws.com" >&2
  exit 1
fi

if [[ "$TIER" == "frontend" && -z "$VITE_API_URL" ]]; then
  echo "frontend requires a vite_api_url argument, e.g.:" >&2
  echo "  $0 frontend http://todo-alb-695255760.us-east-1.elb.amazonaws.com" >&2
  exit 1
fi

RAW_BASE="https://raw.githubusercontent.com/ismailrz/aws-auto-scaling-group-3-tier-app/main"
PROFILE_NAME="todo-${TIER}"
BOOTSTRAP_URL="${RAW_BASE}/deploy/${TIER}/bootstrap-ami.sh"
STAMP=$(date -u +%Y%m%d%H%M%S)
AMI_NAME="todo-${TIER}-${STAMP}"

echo "==> Looking up the latest Amazon Linux 2023 AMI"
BUILDER_AMI=$(aws ssm get-parameters \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)

echo "==> Finding a public subnet from the Terraform-managed VPC"
PUBLIC_SUBNET=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=todo-public-*" \
  --query 'Subnets[0].SubnetId' --output text)

if [[ "$PUBLIC_SUBNET" == "None" || -z "$PUBLIC_SUBNET" ]]; then
  echo "No subnet tagged todo-public-* found — has terraform apply created the network yet?" >&2
  exit 1
fi

VPC_ID=$(aws ec2 describe-subnets --subnet-ids "$PUBLIC_SUBNET" --query 'Subnets[0].VpcId' --output text)
DEFAULT_SG=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' --output text)

echo "==> Launching builder instance (profile: ${PROFILE_NAME}, subnet: ${PUBLIC_SUBNET})"
BUILDER_ID=$(aws ec2 run-instances \
  --image-id "$BUILDER_AMI" \
  --instance-type t3.small \
  --subnet-id "$PUBLIC_SUBNET" \
  --security-group-ids "$DEFAULT_SG" \
  --associate-public-ip-address \
  --iam-instance-profile "Name=${PROFILE_NAME}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=todo-${TIER}-builder}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "    instance: ${BUILDER_ID}"

cleanup() {
  echo "==> Terminating builder instance ${BUILDER_ID}"
  aws ec2 terminate-instances --instance-ids "$BUILDER_ID" >/dev/null
}

echo "==> Waiting for the instance to register with SSM (up to ~3 min)"
for _ in $(seq 1 18); do
  COUNT=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${BUILDER_ID}" \
    --query 'length(InstanceInformationList)' --output text)
  [[ "$COUNT" == "1" ]] && break
  sleep 10
done

if [[ "$COUNT" != "1" ]]; then
  echo "Instance never registered with SSM — check its IAM instance profile has AmazonSSMManagedInstanceCore." >&2
  cleanup
  exit 1
fi

if [[ "$TIER" == "frontend" ]]; then
  RUN_CMD="export VITE_API_URL='${VITE_API_URL}'; curl -fsSL '${BOOTSTRAP_URL}' | bash"
else
  RUN_CMD="curl -fsSL '${BOOTSTRAP_URL}' | bash"
fi

echo "==> Running deploy/${TIER}/bootstrap-ami.sh on the builder via SSM"
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$BUILDER_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"${RUN_CMD}\"]" \
  --query 'Command.CommandId' --output text)

echo "    command: ${COMMAND_ID}"
echo "==> Waiting for it to finish (installs + builds can take a few minutes)"

for _ in $(seq 1 60); do
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" --instance-id "$BUILDER_ID" \
    --query 'Status' --output text 2>/dev/null || echo "Pending")
  case "$STATUS" in
    Success) break ;;
    Failed|Cancelled|TimedOut)
      echo "bootstrap-ami.sh failed (status: ${STATUS}). Output:" >&2
      aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$BUILDER_ID" \
        --query '{stdout:StandardOutputContent,stderr:StandardErrorContent}' --output text >&2
      echo "Builder instance ${BUILDER_ID} left running for debugging — terminate it manually when done." >&2
      exit 1
      ;;
  esac
  sleep 10
done

if [[ "$STATUS" != "Success" ]]; then
  echo "Timed out waiting for bootstrap-ami.sh. Builder instance ${BUILDER_ID} left running for debugging." >&2
  exit 1
fi

echo "==> bootstrap-ami.sh succeeded. Creating AMI: ${AMI_NAME}"
AMI_ID=$(aws ec2 create-image \
  --instance-id "$BUILDER_ID" \
  --name "$AMI_NAME" \
  --query 'ImageId' --output text)

echo "    ami: ${AMI_ID}"
echo "==> Waiting for the AMI to become available (up to a few minutes)"
aws ec2 wait image-available --image-ids "$AMI_ID"

cleanup

echo
echo "Done. ${TIER}_ami_id = ${AMI_ID}"
echo "Put this in terraform/terraform.tfvars as ${TIER}_ami_id, then terraform apply."
