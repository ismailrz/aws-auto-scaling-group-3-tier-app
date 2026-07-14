locals {
  name = var.project_name

  common_tags = {
    Project = var.project_name
  }

  # Backend's CORS_ORIGINS is set at boot via user data, not baked into the
  # AMI, so — unlike the frontend's VITE_API_URL — it has no chicken-and-egg
  # problem: the ALB always exists by the time an instance boots.
  cors_origins = var.use_domain ? "https://app.${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}
