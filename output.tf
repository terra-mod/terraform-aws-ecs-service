output ecs_execution_role_id {
  description = "The ID for the Task Execution Role attached to the Service."
  value       = var.use_execution_role ? aws_iam_role.ecs_execution_role[0].id : null
}

output ecs_task_role_id {
  description = "The ID for the Task Execution Role attached to the Service."
  value       = var.use_task_role ? aws_iam_role.ecs_task_role[0].id : null
}

output security_group_id {
  description = "The ID of the Security Group generated for the Service"
  value       = coalescelist(aws_security_group.security_group.*.id, [null])[0]
}

output service_discovery_service_arn {
  description = "The Service Discovery Service ARN."
  value       = coalescelist(aws_service_discovery_service.sds.*.arn, [null])[0]
}