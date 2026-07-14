output "alb_dns_name" {
  description = "ALB's own DNS name. If use_domain = false, this is the URL you hit directly (http://<this>)."
  value       = aws_lb.this.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master username/password (managed by AWS, fetched at boot by the backend's user data)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "app_url" {
  value = var.use_domain ? "https://app.${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}

output "api_url" {
  value = var.use_domain ? "https://api.${var.domain_name}" : "http://${aws_lb.this.dns_name}"
}
