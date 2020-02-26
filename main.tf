/**
 * Requires Terraform >= 0.12
 */
terraform {
  required_version = "~> 0.12"
}

locals {
  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
    Service     = var.name
  })
}

/**
 * Create a default Security Group - ingress and egress rules are attached separately to allow additional rules
 * outside of this module to be attached to this security group if desired.
 */
resource aws_security_group security_group {
  description = "ECS Service security group for ${var.cluster_name} ${var.name}."

  vpc_id = var.vpc_id
  name   = var.name

  tags = local.tags
}

/**
 * Creates an default egress rule.
 */
resource aws_security_group_rule egress {
  security_group_id = aws_security_group.security_group.id

  description = "Default egress - fully open."
  type        = "egress"

  from_port = 0
  to_port   = 0
  protocol  = -1

  cidr_blocks = ["0.0.0.0/0"]
}

/**
 * Creates the default ingress rule for the service for service discovery.
 */
resource aws_security_group_rule sds_ingress {
  count = var.enable_service_discovery ? 1 : 0

  security_group_id = aws_security_group.security_group.id

  description = "Main ingress rule."
  type        = "ingress"

  from_port = var.ingress_target_port
  to_port   = var.ingress_target_port
  protocol  = var.ingress_protocol

  cidr_blocks = var.service_discovery_ingress_cidr_blocks
}

/**
 * Creates the default ingress rule for the service for load balancing.
 */
resource aws_security_group_rule lb_ingress {
  count = var.enable_load_balancing ? 1 : 0

  security_group_id = aws_security_group.security_group.id

  description = "Main ingress rule."
  type        = "ingress"

  from_port = var.ingress_target_port
  to_port   = var.ingress_target_port
  protocol  = var.ingress_protocol

  source_security_group_id = var.load_balancer_security_group
}

/**
 * The ECS task definition.
 */
resource aws_ecs_task_definition task {
  family             = var.name
  task_role_arn      = aws_iam_role.ecs_execution_role.arn
  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  cpu    = var.task_cpu
  memory = var.task_memory

  lifecycle {
    create_before_destroy = true
  }

  network_mode             = var.task_network_mode
  requires_compatibilities = var.task_requires_compatibilities

  container_definitions = var.task_definition
}

/**
 * Generate the actual ECS Service
 */
resource aws_ecs_service service {
  name                               = var.name
  cluster                            = var.cluster_name
  launch_type                        = var.launch_type
  task_definition                    = aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  # This is only used with Load Balancing
  health_check_grace_period_seconds = var.enable_load_balancing ? var.health_check_grace_period_seconds : null

  network_configuration {
    security_groups  = [aws_security_group.security_group.id]
    subnets          = var.networking_subnets
    assign_public_ip = var.networking_assign_public_ip
  }

  # When Service Discovery is enabled
  dynamic service_registries {
    for_each = aws_service_discovery_service.sds

    content {
      registry_arn = service_registries.value.arn
      port         = var.service_discovery_dns_record_type == "SRV" ? var.ingress_target_port : null
    }
  }

  # When Load Balancing is enabled
  dynamic load_balancer {
    for_each = aws_lb_target_group.target

    content {
      container_name   = var.ingress_target_container
      container_port   = load_balancer.value.port
      target_group_arn = var.load_balancer_listener_arn
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  # AWS Accounts need to opt-in to allowing tagging of this resource, else this will
  # cause the resource creation to fail.
  tags = var.ecs_service_tagging_enabled ? local.tags : null
}

/**
 * Create a new Service Discovery Service.
 */
resource aws_service_discovery_service sds {
  count = var.enable_service_discovery ? 1 : 0

  name = "${var.cluster_name}-${var.name}"

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = var.service_discovery_dns_ttl
      type = var.service_discovery_dns_record_type
    }
  }

  health_check_custom_config {
    failure_threshold = var.service_discovery_failure_threshold
  }
}

/**
 * Create a Target Group to target the instances in the ECS Service.
 */
resource aws_lb_target_group target {
  count = var.enable_load_balancing ? 1 : 0

  name        = var.name
  port        = var.ingress_target_port
  protocol    = var.ingress_protocol
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.load_balancer_draining_delay

  stickiness {
    type            = "lb_cookie"
    enabled         = var.load_balancer_use_sticky_sessions
    cookie_duration = var.load_balancer_sticky_session_duration
  }

  health_check {
    healthy_threshold   = var.healthcheck_healthy_threshold
    unhealthy_threshold = var.healthcheck_unhealthy_threshold

    timeout  = var.healthcheck_timeout
    protocol = var.healthcheck_protocol

    path     = var.healthcheck_path
    interval = var.healthcheck_interval
  }
}

/*
 * When using Auto Scaling, we target the Desired Count on the service.
 */
resource aws_appautoscaling_target scaling_target {
  count = var.enable_auto_scaling ? 1 : 0

  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.scaling_min_capacity
  max_capacity       = var.scaling_max_capacity
}

/**
 * Use a TargetTrackingScaling policy to scale based on the given metric (CPU or Memory).
 */
resource aws_appautoscaling_policy auto_scaling {
  count = var.enable_auto_scaling ? 1 : 0

  name              = "${var.cluster_name}-${var.name}-auto-scaling"
  service_namespace = "ecs"
  resource_id       = "service/${var.cluster_name}/${aws_ecs_service.service.name}"

  target_tracking_scaling_policy_configuration {
    target_value       = var.scaling_threshold
    scale_in_cooldown  = var.scaling_cooldown
    scale_out_cooldown = var.scaling_cooldown

    predefined_metric_specification {
      predefined_metric_type = var.scaling_metric
    }
  }

  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "TargetTrackingScaling"

  depends_on = [aws_appautoscaling_target.scaling_target]
}

/**
 * Generates the Role for the ECS Container
 */
resource aws_iam_role ecs_execution_role {
  name = "${var.cluster_name}-${var.name}-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

/**
 * Generates the Policy for the ECS Container
 */
resource aws_iam_role_policy ecs_execution_role_policy {
  name = "${var.cluster_name}-${var.name}-execution-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
    %{if var.cloudwatch_log_group_arn != null}
    ,{
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${var.cloudwatch_log_group_arn}"
    }
    %{endif}
  ]
}
EOF
}

/**
 * Attach a policy to the given role to allow access to Secrets in Secrets Manager.
 */
resource aws_iam_role_policy_attachment secrets_policy_attachment {
  count = var.secrets_policy_arn != null ? 1 : 0

  role       = aws_iam_role.ecs_execution_role.id
  policy_arn = var.secrets_policy_arn
}
