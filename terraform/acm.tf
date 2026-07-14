# Only created when var.use_domain = true. See terraform/README.md.

data "aws_route53_zone" "this" {
  count = var.use_domain ? 1 : 0
  name  = var.domain_name
}

resource "aws_acm_certificate" "this" {
  count                     = var.use_domain ? 1 : 0
  domain_name               = "app.${var.domain_name}"
  subject_alternative_names = ["api.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name}-cert" })
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.use_domain ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.use_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "app" {
  count   = var.use_domain ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api" {
  count   = var.use_domain ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
