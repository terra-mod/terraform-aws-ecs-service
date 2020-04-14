# AWS ECS Service

This module creates an ECS Service in an existing ECS Cluster.

##### Load Balancing
This module supports the use of ALBs and NLBs by accepting the ARN of a Load Balancer Listener
and creating the target group for the service. In order to use Load Balancing, set the `load_balancer_target_groups` variable
with the list of Target Group ARNs that the ECS Service should register with.

##### Service Discovery
Service Discovery is supported by creating a Service Discovery Service via this module and allowing the configuration of the 
DNS settings for the service. In order to use Service Discovery, the `enable_service_discovery` input variable must be set 
to `true` and the ID of an existing Service Discovery Namespace must be passed in. There are several service discovery 
input variables that be adjusted to change the behavior Service Discovery.

##### Auto Scaling
This module supports Auto Scaling via a Target Tracking Policy that can be either set against CPU or Memory utilization. In order
to use Auto Scaling, the `enable_auto_scaling` input variable must be set to `true`. There are multiple auto scaling input
variables that be set to adjust the task scaling.

**Note**: In order to tag ECS Service resources, you must have opted in to the new ARN and Resource ID settings for ECS - if not
the ECS Service will fail to create. If you have not opted in, you can set the `ecs_service_tagging_enabled` input variable
to `false` - which will not tag the ECS Service.

##### Usage

    data aws_vpc _ {
      id = "vpc-abc123"
    }
    
    data aws_subnet_ids private {
      vpc_id = data.aws_vpc._.id
    
      filter {
        name   = "tag:Tier"
        values = ["Private"]
      }
    }
    
    resource aws_cloudwatch_log_group log_group {
      name = "my-example-log-group"
    
      tags = local.tags
    }

    resource aws_ecs_cluster cluster {
        name = "my-example-cluster"
        
        capacity_providers = ["FARGATE"]
    }
    
    module container {
      source = "terraform-aws-container-defintion"
      
      image = "nginx"
    }

    module service {
      source = "terraform-aws-ecs-service"
    
      vpc_id = data.aws_vpc._.id
    
      name         = "my-example-service"
      cluster_name = data.aws_ecs_cluster._.cluster_name
    
      task_definition = jsonencode([module.container.definition])
      task_cpu        = 1024
      task_memory     = 2048
    
      networking_subnets          = data.aws_subnet_ids.private.ids
    
      enable_service_discovery              = true
      service_discovery_namespace_id        = aws_service_discovery_private_dns_namespace.namespace.id
      service_discovery_ingress_cidr_blocks = [data.aws_vpc._.cidr_block]
    
      ingress_protocol         = "TCP"
      ingress_target_container = "nginx"
      ingress_target_port      = 80
    
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.log_group.arn
    
      ecs_service_tagging_enabled = false
    }

