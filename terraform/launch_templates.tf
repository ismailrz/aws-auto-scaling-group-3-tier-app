resource "aws_launch_template" "backend" {
  name_prefix   = "${local.name}-backend-"
  image_id      = var.backend_ami_id
  instance_type = var.backend_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.backend.arn
  }

  vpc_security_group_ids = [aws_security_group.backend.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/backend-user-data.sh.tpl", {
    db_secret_arn = aws_db_instance.this.master_user_secret[0].secret_arn
    aws_region    = var.aws_region
    db_host       = aws_db_instance.this.address
    db_port       = aws_db_instance.this.port
    db_name       = var.db_name
    cors_origins  = local.cors_origins
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name}-backend" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "frontend" {
  name_prefix   = "${local.name}-frontend-"
  image_id      = var.frontend_ami_id
  instance_type = var.frontend_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.frontend.arn
  }

  vpc_security_group_ids = [aws_security_group.frontend.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # No domain-dependent values — VITE_API_URL is already baked into the AMI
  # at build time (deploy/frontend/bootstrap-ami.sh), so this file is used
  # unmodified. See terraform/README.md.
  user_data = base64encode(file("${path.module}/../deploy/frontend/user-data.sh"))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name}-frontend" })
  }

  lifecycle {
    create_before_destroy = true
  }
}
