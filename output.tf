output ecs_iam_role_id {
  description = "The ID for the IAM Role attached to the Service."
  value       = aws_iam_role.ecs_execution_role.id
}

output security_group_id {
  description = "The ID of the Security Group generated for the Service"
  value       = aws_security_group.security_group.id
}

output service_discovery_service_arn {
  description = "The Service Discovery Service ARN."
  value       = coalescelist(aws_service_discovery_service.sds.*.arn, [null])[0]
}