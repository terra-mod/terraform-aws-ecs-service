# Core Settings
variable vpc_id {
  description = "The ID of the VPC."
  type        = string
}

variable cluster_name {
  description = "The name of the Cluster the Service will be associated with."
  type        = string
}

variable name {
  description = "The name of the service."
  type        = string
}

variable desired_count {
  description = "The desired task count for the Service. When Auto Scaling is enabled, this works as just the initial value - subsequent changes to this value are ignored."
  type        = number
  default     = 1
}

variable launch_type {
  description = "The launch type on which to run your service. The valid values are `EC2` and `FARGATE`. This module defaults to `FARGATE`."
  type        = string
  default     = "FARGATE"
}

variable networking_subnets {
  description = "The subnets for the Service."
  type        = list(string)
}

variable networking_assign_public_ip {
  description = "Assign a public IP address to the ENI (Fargate launch type only). Valid values are `true` or `false`. Default `false`."
  type        = bool
  default     = false
}

variable environment {
  description = "The environment the service is running in."
  type        = string
  default     = null
}

variable ecs_service_tagging_enabled {
  description = "The ability to tag ECS Services was recently released, but requires an account to opt-in. If your account has not opted in, adding tags to the Service will fail."
  type        = bool
  default     = true
}

variable tags {
  description = "Any additional tags that should be added to taggable resources created by this module."
  type        = map(string)
  default     = {}
}

variable deployment_minimum_healthy_percent {
  description = "lower limit (% of desired_count) of # of running tasks during a deployment."
  default     = 100
}

variable deployment_maximum_percent {
  description = "upper limit (% of desired_count) of # of running tasks during a deployment."
  default     = 200
}

# Task Definition
variable task_definition {
  description = "A JSON encoded list of task definitions to define the containers for this service. If registering with a load balancer, make sure at least one container within is named the same as the service."
  type        = string
}

variable task_network_mode {
  description = "The Docker networking mode to use for the containers in the task. The valid values are `none`, `bridge`, `awsvpc`, and `host`."
  type        = string
  default     = "awsvpc"
}

variable task_requires_compatibilities {
  description = "A set of launch types required by the task. The valid values are `EC2` and `FARGATE.`"
  type        = list(string)
  default     = ["FARGATE"]
}

variable task_memory {
  description = "The number of MiB of memory to reserve for the task."
  default     = 1024
}

variable task_cpu {
  description = "The number of cpu units to reserve for the task."
  default     = 256
}

variable cloudwatch_log_group_arn {
  description = "If the service is expected to log to CloudWatch logs, specify the Log Group ARN. This is used to create the necessary IAM policy granting permission to write to that Log Group."
  type        = string
  default     = null
}

# Ingress
variable ingress_target_container {
  description = "The name of the target container the Load Balancer will try to reach."
  type        = string
  default     = null
}

variable ingress_target_port {
  description = "The port that the Load Balancer should use as a target."
  type        = number
  default     = null
}

variable ingress_protocol {
  description = "The protocol to use for ingress through the load balancer. One of `HTTP`, `HTTPS`, or `TCP`."
  type        = string
  default     = "TCP"
}

# Service Discovery
variable enable_service_discovery {
  description = "Whether the service should be registered with Service Discovery. In order to use Service Disovery, an existing DNS Namespace must exist and be passed in."
  type        = bool
  default     = false
}

variable service_discovery_ingress_cidr_blocks {
  description = "The CIDR Blocks that should be used to limit ingress to the Service."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable service_discovery_namespace_id {
  description = "The ID of the namespace to use for DNS configuration."
  type        = string
  default     = null
}

variable service_discovery_dns_record_type {
  description = "The type of the resource, which indicates the value that Amazon Route 53 returns in response to DNS queries. One of `A` or `SRV`."
  type        = string
  default     = "A"
}

variable service_discovery_dns_ttl {
  description = "The amount of time, in seconds, that you want DNS resolvers to cache the settings for this resource record set."
  type        = number
  default     = 10
}

variable service_discovery_routing_policy {
  description = "he routing policy that you want to apply to all records that Route 53 creates when you register an instance and specify the service. One of `MULTIVALUE` or `WEIGHTED`."
  type        = string
  default     = "MULTIVALUE"
}

variable service_discovery_failure_threshold {
  description = "The number of 30-second intervals that you want service discovery to wait before it changes the health status of a service instance. Maximum value of 10."
  type        = number
  default     = 1
}

# Load Balancing
variable enable_load_balancing {
  description = "Whether an ALB should be associated to the service. To use Load Balancing, the ARN of an existing Listener must be passed in."
  type        = bool
  default     = false
}

variable load_balancer_listener_arn {
  description = "The ARN of a Load Balancer Listener associated to an ALB."
  type        = string
  default     = null
}

variable load_balancer_security_group {
  description = "The security group of load balancer."
  type        = string
  default     = null
}

variable load_balancer_use_sticky_sessions {
  description = "Whether or not to enable Sticky Sessions via the `lb_cookie`. This is discouraged wherever possible."
  type        = bool
  default     = false
}

variable load_balancer_sticky_session_duration {
  description = "The time period, in seconds, during which requests from a client should be routed to the same target. Between 1 and 604800."
  type        = number
  default     = 86400
}

variable health_check_grace_period_seconds {
  description = <<EOT
    Tasks behind a load balancer are being monitored by it. When a task is seen as unhealthy by the load balancer, the ECS
    service will stop it. It can be an issue on Task startup if the ELB health checks marks the task as unhealthy before
    it had time to warm up. The service would shut the task down prematurely.

    This property defaults to 2 minutes. If you frequently experience tasks being stopped just after being started you
    may need to increase this value.
EOT

  default = 120
}

variable healthcheck_path {
  description = "The path that should be used as a health check for your service, e.g `/health`, `/status`, or `/ping`."
  type        = string
  default     = "/"
}

variable healthcheck_healthy_threshold {
  description = "The number of times the health check must pass before considering a target healthy."
  type        = string
  default     = 2
}

variable healthcheck_unhealthy_threshold {
  description = "The number of times the health check must fail before considering a target unhealthy."
  type        = string
  default     = 2
}

variable healthcheck_timeout {
  description = "The amount of time before the health check should timeout."
  type        = string
  default     = 5
}

variable healthcheck_protocol {
  description = "The protocol for the health check, either `HTTP` or `TCP`."
  type        = string
  default     = "HTTP"
}

variable healthcheck_interval {
  description = "How often in seconds the health check should be performed."
  type        = string
  default     = 30
}

variable load_balancer_draining_delay {
  description = "The time to wait for in-flight requests to complete while deregistering a target."
  default     = 30
}

# Secrets
variable secrets_policy_arn {
  description = "The ARN of a IAM Policy that grants the Service access to one or more SecretsManager Secrets."
  type        = string
  default     = null
}

# ECS Auto Scaling
variable enable_auto_scaling {
  description = "Whether or not to include a Target Tracking Scaling Policy. Treat as a tinyint - use `1` for true, `0` for false."
  type        = bool
  default     = false
}

variable scaling_min_capacity {
  description = "The minimum number of tasks that should be running for the ECS Service. Defaults to 2 in production, 1 otherwise."
  default     = 1
}

variable scaling_max_capacity {
  description = "The maximum number of tasks that should be running for the ECS Service. Defaults to 10."
  default     = 10
}

variable scaling_cooldown {
  description = "The amount of time in seconds that must pass before another scaling event can happen."
  default     = 60
}

variable scaling_metric {
  description = "The scaling metric to use (`ECSServiceAverageCPUUtilization` or `ECSServiceAverageMemoryUtilization`). Defaults to `ECSServiceAverageCPUUtilization`."
  default     = "ECSServiceAverageCPUUtilization"
}

variable scaling_threshold {
  description = "The desired value for the `scaling_metric`. Defaults to 70%."
  default     = 70
}
