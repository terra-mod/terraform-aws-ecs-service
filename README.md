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

Requires Terraform >= 0.12

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cloudwatch\_log\_group\_arn | If the service is expected to log to CloudWatch logs, specify the Log Group ARN. This is used to create the necessary IAM policy granting permission to write to that Log Group. | `string` | n/a | yes |
| cluster\_name | The name of the Cluster the Service will be associated with. | `string` | n/a | yes |
| create\_load\_balancer | Create an Internet facing load balancer to attach to the service. | `bool` | `false` | no |
| deployment\_maximum\_percent | upper limit (% of desired\_count) of # of running tasks during a deployment. | `number` | `200` | no |
| deployment\_minimum\_healthy\_percent | lower limit (% of desired\_count) of # of running tasks during a deployment. | `number` | `100` | no |
| desired\_count | The desired task count for the Service. When Auto Scaling is enabled, this works as just the initial value - subsequent changes to this value are ignored. | `number` | `1` | no |
| ecs\_service\_tagging\_enabled | The ability to tag ECS Services was recently released, but requires an account to opt-in. If your account has not opted in, adding tags to the Service will fail. | `bool` | `true` | no |
| enable\_auto\_scaling | Whether or not to include a Target Tracking Scaling Policy. Treat as a tinyint - use `1` for true, `0` for false. | `bool` | `false` | no |
| enable\_service\_discovery | Whether the service should be registered with Service Discovery. In order to use Service Disovery, an existing DNS Namespace must exist and be passed in. | `bool` | `false` | no |
| environment | The environment the service is running in. | `string` | n/a | yes |
| health\_check\_grace\_period\_seconds | Tasks behind a load balancer are being monitored by it. When a task is seen as unhealthy by the load balancer, the ECS     service will stop it. It can be an issue on Task startup if the ELB health checks marks the task as unhealthy before     it had time to warm up. The service would shut the task down prematurely.<br><br>    This property defaults to 2 minutes. If you frequently experience tasks being stopped just after being started you     may need to increase this value. | `number` | `120` | no |
| ingress\_protocol | The protocol to use for ingress through the load balancer. One of `HTTP`, `HTTPS`, or `TCP`. | `string` | `"TCP"` | no |
| ingress\_target\_container | The name of the target container the Load Balancer will try to reach. | `string` | n/a | yes |
| ingress\_target\_port | The port that the Load Balancer should use as a target. | `number` | n/a | yes |
| launch\_type | The launch type on which to run your service. The valid values are `EC2` and `FARGATE`. This module defaults to `FARGATE`. | `string` | `"FARGATE"` | no |
| load\_balancer\_security\_groups | Security Group for the load balancer to be created | `list` | `[]` | no |
| load\_balancer\_subnets | Subntes for the load balancer to be created | `list` | `[]` | no |
| load\_balancer\_target\_groups | A list of Target Group ARNs that the ECS Service should register with. | `list(string)` | `[]` | no |
| name | The name of the service. | `string` | n/a | yes |
| networking\_assign\_public\_ip | Assign a public IP address to the ENI (Fargate launch type only). Valid values are `true` or `false`. Default `false`. | `bool` | `false` | no |
| networking\_subnets | The subnets for the Service. | `list(string)` | n/a | yes |
| scaling\_cooldown | The amount of time in seconds that must pass before another scaling event can happen. | `number` | `60` | no |
| scaling\_max\_capacity | The maximum number of tasks that should be running for the ECS Service. Defaults to 10. | `number` | `10` | no |
| scaling\_metric | The scaling metric to use (`ECSServiceAverageCPUUtilization` or `ECSServiceAverageMemoryUtilization`). Defaults to `ECSServiceAverageCPUUtilization`. | `string` | `"ECSServiceAverageCPUUtilization"` | no |
| scaling\_min\_capacity | The minimum number of tasks that should be running for the ECS Service. Defaults to 2 in production, 1 otherwise. | `number` | `1` | no |
| scaling\_threshold | The desired value for the `scaling_metric`. Defaults to 70%. | `number` | `70` | no |
| secrets\_policy\_arns | The ARNs of IAM Policies that grants the Service access to one or more SecretsManager Secrets. | `list(string)` | `[]` | no |
| security\_group\_allowed\_security\_groups | A list of Security Group IDs that should be allowed ingress on the `ingress_target_port`. | `set(string)` | `[]` | no |
| security\_group\_cidr\_blocks | The CIDR Blocks that should be used to limit ingress to the Service. | `set(string)` | `[]` | no |
| service\_discovery\_container\_name | The container name value, already specified in the task definition, to be used for your service discovery service. | `string` | n/a | yes |
| service\_discovery\_container\_port | The port value, already specified in the task definition, to be used for your service discovery service. | `number` | n/a | yes |
| service\_discovery\_dns\_record\_type | The type of the resource, which indicates the value that Amazon Route 53 returns in response to DNS queries. One of `A` or `SRV`. | `string` | `"A"` | no |
| service\_discovery\_dns\_ttl | The amount of time, in seconds, that you want DNS resolvers to cache the settings for this resource record set. | `number` | `10` | no |
| service\_discovery\_failure\_threshold | The number of 30-second intervals that you want service discovery to wait before it changes the health status of a service instance. Maximum value of 10. | `number` | `1` | no |
| service\_discovery\_namespace\_id | The ID of the namespace to use for DNS configuration. | `string` | n/a | yes |
| service\_discovery\_port | The port value used if your Service Discovery service specified an SRV record. | `number` | n/a | yes |
| service\_discovery\_routing\_policy | The routing policy that you want to apply to all records that Route 53 creates when you register an instance and specify the service. One of `MULTIVALUE` or `WEIGHTED`. | `string` | `"MULTIVALUE"` | no |
| tags | Any additional tags that should be added to taggable resources created by this module. | `map(string)` | `{}` | no |
| target\_group\_port | Target group port associated to the created balancer and the service | `number` | `80` | no |
| target\_group\_protocol | Target group protocol associated to the created balancer and the service | `string` | `"HTTP"` | no |
| target\_group\_target\_type | Target group target\_type associated to the created balancer and the service | `string` | `"ip"` | no |
| target\_group\_vpc\_id | Target group vpc\_id associated to the created balancer and the service | `string` | n/a | yes |
| task\_cpu | The number of cpu units to reserve for the task. | `number` | `256` | no |
| task\_definition | A JSON encoded list of task definitions to define the containers for this service. If registering with a load balancer, make sure at least one container within is named the same as the service. | `string` | n/a | yes |
| task\_memory | The number of MiB of memory to reserve for the task. | `number` | `1024` | no |
| task\_network\_mode | The Docker networking mode to use for the containers in the task. The valid values are `none`, `bridge`, `awsvpc`, and `host`. | `string` | `"awsvpc"` | no |
| task\_requires\_compatibilities | A set of launch types required by the task. The valid values are `EC2` and `FARGATE.` | `list(string)` | <pre>[<br>  "FARGATE"<br>]</pre> | no |
| vpc\_id | The ID of the VPC. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| ecs\_iam\_role\_id | The ID for the IAM Role attached to the Service. |
| security\_group\_id | The ID of the Security Group generated for the Service |
| service\_discovery\_service\_arn | The Service Discovery Service ARN. |

