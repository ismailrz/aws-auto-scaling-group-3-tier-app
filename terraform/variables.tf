variable "aws_region" {
  description = "AWS region for everything below."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use. Leave empty to use the default credential chain (env vars, default profile, instance role, etc)."
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Prefix used to name/tag every resource."
  type        = string
  default     = "todo"
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "Exactly two AZs — everything here (ASGs, ALB, RDS Multi-AZ) assumes two."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.20.0/24", "10.0.21.0/24"]
}

# ---------------------------------------------------------------------------
# Domain vs. no domain — see terraform/README.md
# ---------------------------------------------------------------------------

variable "use_domain" {
  description = "true = host-based routing + ACM + Route 53 (app./api.<domain_name>). false = path-based routing over plain HTTP using the ALB's own DNS name."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Apex domain already hosted in Route 53 (e.g. example.com). Required, and must have a matching hosted zone, when use_domain = true."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Golden AMIs — baked manually via deploy/backend/bootstrap-ami.sh and
# deploy/frontend/bootstrap-ami.sh (Terraform does not build AMIs). See
# terraform/README.md for the chicken-and-egg note when use_domain = false.
# ---------------------------------------------------------------------------

variable "backend_ami_id" {
  description = "AMI ID produced by deploy/backend/bootstrap-ami.sh."
  type        = string
}

variable "frontend_ami_id" {
  description = "AMI ID produced by deploy/frontend/bootstrap-ami.sh (VITE_API_URL is baked in at build time — see terraform/README.md)."
  type        = string
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "backend_instance_type" {
  type    = string
  default = "t3.small"
}

variable "frontend_instance_type" {
  type    = string
  default = "t3.small"
}

variable "backend_min_size" {
  type    = number
  default = 2
}

variable "backend_desired_capacity" {
  type    = number
  default = 2
}

variable "backend_max_size" {
  type    = number
  default = 6
}

variable "frontend_min_size" {
  type    = number
  default = 2
}

variable "frontend_desired_capacity" {
  type    = number
  default = 2
}

variable "frontend_max_size" {
  type    = number
  default = 4
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "db_engine_version" {
  type    = string
  default = "16.4"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  description = "Cap for RDS storage autoscaling (gp3), so a runaway table can't autoscale the bill."
  type        = number
  default     = 100
}

variable "db_name" {
  type    = string
  default = "todo"
}

variable "db_username" {
  type    = string
  default = "todo"
}

variable "db_backup_retention_period" {
  description = "Days of automated RDS backups to retain. Some AWS accounts (e.g. new/free-tier-restricted ones) reject values above 1 with a FreeTierRestrictionError — raise this once your account allows it."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Defaults to false so this practice stack can be torn down with `terraform destroy`. Set true for anything real."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Defaults to true for the same reason as db_deletion_protection. Set false for anything real."
  type        = bool
  default     = true
}
