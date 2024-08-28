/**
 * Requires Terraform >= 0.12
 */
terraform {
  required_version = ">= 0.12"
}

locals {
  tags = merge(merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Cluster     = var.cluster_name
    Service     = var.name
  }), var.overwrite_tags)
}

/**
 * Create a default Security Group - ingress and egress rules are attached separately to allow additional rules
 * outside of this module to be attached to this security group if desired.
 */
resource aws_security_group security_group {
  count = var.task_network_mode == "awsvpc" ? 1 : 0

  description = "ECS Service security group for ${var.cluster_name} ${var.name}."

  vpc_id = var.vpc_id
  name   = var.name

  tags = local.tags
}

/**
 * Creates an default egress rule.
 */
resource aws_security_group_rule egress {
  count = var.task_network_mode == "awsvpc" && var.security_group_default_egress ? 1 : 0

  security_group_id = aws_security_group.security_group[0].id

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
  for_each = var.task_network_mode == "awsvpc" ? var.security_group_cidr_blocks : []

  security_group_id = aws_security_group.security_group[0].id

  description = "CIDR Block Ingress rule."
  type        = "ingress"

  from_port = var.ingress_target_port
  to_port   = var.ingress_target_port
  protocol  = var.ingress_protocol

  cidr_blocks = [each.value]
}

/**
 * Creates the default ingress rule for the service for load balancing.
 */
resource aws_security_group_rule lb_ingress {
  for_each = var.task_network_mode == "awsvpc" ? var.security_group_allowed_security_groups : []

  security_group_id = aws_security_group.security_group[0].id

  description = "Security Group Ingress rule."
  type        = "ingress"

  from_port = var.ingress_target_port
  to_port   = var.ingress_target_port
  protocol  = var.ingress_protocol

  source_security_group_id = each.value
}

/**
 * The ECS task definition.
 */
resource aws_ecs_task_definition task {
  family             = var.name
  task_role_arn      = var.use_task_role ? aws_iam_role.ecs_task_role[0].arn : null
  execution_role_arn = var.use_execution_role ? aws_iam_role.ecs_execution_role[0].arn : null

  cpu    = var.task_cpu
  memory = var.task_memory

  lifecycle {
    create_before_destroy = true
  }

  network_mode             = var.task_network_mode
  requires_compatibilities = var.task_requires_compatibilities

  container_definitions = var.task_definition

  dynamic "volume" {
    for_each = var.task_volumes

    content {
      name      = volume.value["name"]
      host_path = volume.value["host_path"]
    }
  }
}

/**
 * Generate the actual ECS Service
 */
resource aws_ecs_service service {
  name                               = var.name
  cluster                            = var.cluster_name
  launch_type                        = var.launch_type
  scheduling_strategy                = var.scheduling_strategy
  platform_version                   = var.platform_version
  task_definition                    = aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  dynamic "ordered_placement_strategy" {
    for_each = var.launch_type == "FARGATE" || var.scheduling_strategy == "DAEMON" ? [] : [1]

    content {
      type  = "spread"
      field = "attribute:ecs.availability-zone"
    }
  }

  # This is only used with Load Balancing
  health_check_grace_period_seconds = length(var.load_balancer_target_groups) > 0 ? var.health_check_grace_period_seconds : null

  # Only include a network configuration for `awsvpc` network mode
  dynamic network_configuration {
    for_each = var.task_network_mode == "awsvpc" ? [aws_security_group.security_group.*.id] : []

    content {
      security_groups  = concat(network_configuration.value, var.service_security_groups)
      subnets          = var.networking_subnets
      assign_public_ip = var.networking_assign_public_ip
    }
  }

  # When Service Discovery is enabled
  dynamic service_registries {
    for_each = aws_service_discovery_service.sds

    # Setting port is not supported whne using "host" or "bridge" network mode.
    content {
      registry_arn   = service_registries.value.arn
      port           = var.task_network_mode == "awsvpc" ? var.service_discovery_container_port : null
      container_name = var.service_discovery_container_name
      container_port = var.service_discovery_container_port
    }
  }

  # When Load Balancing is enabled
  dynamic load_balancer {
    for_each = var.load_balancer_target_groups

    content {
      container_name   = var.ingress_target_container
      container_port   = var.ingress_target_port
      target_group_arn = load_balancer.value
    }
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

  name = var.name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = var.service_discovery_dns_ttl
      type = var.service_discovery_dns_record_type
    }

    routing_policy = var.service_discovery_routing_policy
  }

  health_check_custom_config {
    failure_threshold = var.service_discovery_failure_threshold
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
  count = var.use_execution_role ? 1 : 0

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
 * Generates a default Policy for the ECS Container
 */
resource aws_iam_role_policy ecs_execution_default_policy {
  count = var.use_execution_role ? 1 : 0

  name = "${var.cluster_name}-${var.name}-default-policy"
  role = aws_iam_role.ecs_execution_role[0].id

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
    },
    %{ if var.cloudwatch_log_group_arn != null }
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${replace(var.cloudwatch_log_group_arn, "/:\\*$/", "")}:*"
    }
    %{ endif }
  ]
}
EOF
}

/**
 * Generates a Task Role for the ECS Task.
 */
resource aws_iam_role ecs_task_role {
  count = var.use_task_role ? 1 : 0

  name = "${var.cluster_name}-${var.name}-task-role"

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
 * Attach a additional policies to the ECS Task Role.
 */
resource aws_iam_role_policy_attachment task_policy_attachments {
  count = var.use_task_role ? length(var.task_role_policy_arns) : 0

  role       = aws_iam_role.ecs_task_role[0].id
  policy_arn = element(var.task_role_policy_arns, count.index)
}

/**
 * Attach a additional policies to the ECS Execution Role.
 */
resource aws_iam_role_policy_attachment execution_policy_attachments {
  count = var.use_execution_role ? length(var.execution_role_policy_arns) : 0

  role       = aws_iam_role.ecs_execution_role[0].id
  policy_arn = element(var.execution_role_policy_arns, count.index)
}
