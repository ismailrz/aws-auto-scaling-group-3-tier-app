# Terraform deployment

This is an alternative to the manual [DEPLOYMENT.md](../DEPLOYMENT.md) walkthrough —
same architecture (VPC across 2 AZs, two independent ASGs, ALB, RDS Multi-AZ),
provisioned declaratively instead of clicked through the console. Read
DEPLOYMENT.md first if you haven't; this doc assumes you know *why* each piece
exists and only covers what's different about doing it with Terraform.

## What Terraform does and doesn't manage

Terraform creates the VPC, security groups, RDS instance, IAM roles, ALB,
target groups, listeners, launch templates, and ASGs (§1–§2, §3, §4, §8, §9
of DEPLOYMENT.md).

Terraform does **not** bake AMIs. Golden-AMI creation (§6) stays a manual
step via `deploy/backend/bootstrap-ami.sh` and `deploy/frontend/bootstrap-ami.sh`
run on a temporary builder instance — Terraform just consumes the resulting
AMI IDs as `backend_ami_id` / `frontend_ami_id` variables. If you want that
step automated too, that's what [Packer](https://www.packer.io/) is for; not
included here.

## Domain vs. no domain

Same two paths as DEPLOYMENT.md, controlled by `var.use_domain`:

- `use_domain = true` — set `domain_name` to an apex domain with an existing
  Route 53 hosted zone. Terraform requests the ACM cert, validates it via
  DNS, and sets up host-based routing (`app.<domain>` / `api.<domain>`) plus
  the `app`/`api` A records.
- `use_domain = false` (default) — no ACM cert, no Route 53 records. A
  single HTTP:80 listener on the ALB with path-based routing
  (`/todos*`/`/health` → backend, everything else → frontend), same as
  DEPLOYMENT.md §8b.

### The one thing Terraform doesn't remove: the AMI ordering catch

`VITE_API_URL` is baked into the frontend at build time, inside
`bootstrap-ami.sh` — a step that happens *before* `terraform apply`, since
Terraform consumes the AMI ID rather than producing it. Without a domain,
that value has to be the ALB's DNS name, which doesn't exist until the ALB
does. Terraform can't fix this for you because the AMI is built outside of
it. Work around it the same way as the manual guide:

```bash
# 1. Create just the ALB first, to learn its DNS name.
terraform apply -target=aws_lb.this

terraform output alb_dns_name
# e.g. todo-alb-1234567890.us-east-1.elb.amazonaws.com

# 2. Bake the frontend AMI with that value as VITE_API_URL
#    (deploy/frontend/bootstrap-ami.sh), then the backend AMI.

# 3. Fill in backend_ami_id / frontend_ami_id in terraform.tfvars,
#    then apply everything else.
terraform apply
```

If you're going the `use_domain = true` route, skip this — `app.<domain>` /
`api.<domain>` are known upfront, so a normal single `terraform apply` works.

The backend's `CORS_ORIGINS` has no such problem: it's set by user data at
boot time (computed in `locals.tf` from `aws_lb.this.dns_name`), not baked
into the AMI, so it's always correct by the time an instance actually starts.

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: use_domain/domain_name, backend_ami_id, frontend_ami_id

terraform init
terraform plan
terraform apply
```

State is local (`terraform.tfstate`, gitignored) by default, which is fine
solo. If more than one person/machine will run this, switch to the S3+DynamoDB
backend commented out in `versions.tf` first.

## Teardown

```bash
terraform destroy
```

`db_deletion_protection` and `db_skip_final_snapshot` default to values that
make this a clean, repeatable teardown (`false` / `true`) rather than
production-safe defaults — flip both before using this against anything you
care about keeping.

## Files

| File | Matches DEPLOYMENT.md |
|---|---|
| `network.tf` | §1 Network |
| `security_groups.tf` | §2 Security groups |
| `rds.tf` | §3 RDS PostgreSQL |
| `iam.tf` | §4 IAM |
| `acm.tf` | §8a domain path (ACM + Route 53) |
| `alb.tf` | §8 Target groups + ALB + routing |
| `launch_templates.tf` | §7 Launch Templates |
| `asg.tf` | §9 Auto Scaling Groups + scaling policies |
| `templates/backend-user-data.sh.tpl` | rendered version of `deploy/backend/user-data.sh` |

Deploys (new AMI → production) still go through ASG Instance Refresh, same as
DEPLOYMENT.md §9 — update `backend_ami_id`/`frontend_ami_id` in
`terraform.tfvars` and `terraform apply`; the launch templates use
`create_before_destroy`, and you still trigger the actual rollout via
`aws autoscaling start-instance-refresh` (or add an
`aws_autoscaling_group` `instance_refresh` block if you want Terraform to
kick it off automatically on every apply).
