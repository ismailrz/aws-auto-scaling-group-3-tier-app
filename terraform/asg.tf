resource "aws_autoscaling_group" "backend" {
  name                = "${local.name}-backend"
  vpc_zone_identifier = aws_subnet.private_app[*].id
  target_group_arns   = [aws_lb_target_group.backend.arn]

  min_size         = var.backend_min_size
  desired_capacity = var.backend_desired_capacity
  max_size         = var.backend_max_size

  health_check_type         = "ELB"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-backend"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "frontend" {
  name                = "${local.name}-frontend"
  vpc_zone_identifier = aws_subnet.private_app[*].id
  target_group_arns   = [aws_lb_target_group.frontend.arn]

  min_size         = var.frontend_min_size
  desired_capacity = var.frontend_desired_capacity
  max_size         = var.frontend_max_size

  health_check_type         = "ELB"
  health_check_grace_period = 30

  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-frontend"
    propagate_at_launch = true
  }
}

# --- Backend: request-count-per-target is a better signal than CPU for an
# I/O-bound API waiting on Postgres. CPU stays as a belt-and-suspenders
# backup policy.

resource "aws_autoscaling_policy" "backend_requests" {
  name                   = "${local.name}-backend-requests"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.backend.arn_suffix}"
    }
    target_value = 200
  }
}

resource "aws_autoscaling_policy" "backend_cpu" {
  name                   = "${local.name}-backend-cpu"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70
  }
}

# --- Frontend: CPU is the primary signal (SSR/static rendering is more
# CPU-bound than I/O-bound).

resource "aws_autoscaling_policy" "frontend_cpu" {
  name                   = "${local.name}-frontend-cpu"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}
