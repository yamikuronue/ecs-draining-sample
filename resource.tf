resource "aws_ecs_cluster" "my_cluster" {
  name = var.ecs_cluster_name
  capacity_providers = [aws_ecs_capacity_provider.demoCapacity.name]
}

resource "aws_vpc" "vpc" {
  count = local.CreateSubnet1 ? 1 : 0
  cidr_block = var.vpc_cidr
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
}

resource "aws_subnet" "pub_subnet_az1" {
  count = local.CreateSubnet1 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  cidr_block = var.subnet_cidr1
  availability_zone = element(var.vpc_availability_zones, 0)
}

resource "aws_subnet" "pub_subnet_az2" {
  count = local.CreateSubnet2 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  cidr_block = var.subnet_cidr2
  availability_zone = element(var.vpc_availability_zones, 1)
}

resource "aws_subnet" "pub_subnet_az3" {
  count = local.CreateSubnet3 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  cidr_block = var.subnet_cidr3
  availability_zone = element(var.vpc_availability_zones, 2)
}

resource "aws_internet_gateway" "internet_gateway" {
  count = local.CreateSubnet1 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
}

resource "aws_route_table" "route_via_igw" {
  count = local.CreateSubnet1 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
}

resource "aws_route" "public_route_via_igw" {
  count = local.CreateSubnet1 ? 1 : 0
  route_table_id = aws_route_table.route_via_igw[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.internet_gateway[0].id
}

resource "aws_route_table_association" "pub_subnet1_route_table_association" {
  count = local.CreateSubnet1 ? 1 : 0
  subnet_id = aws_subnet.pub_subnet_az1[0].id
  route_table_id = aws_route_table.route_via_igw[0].id
}

resource "aws_route_table_association" "pub_subnet2_route_table_association" {
  count = local.CreateSubnet2 ? 1 : 0
  subnet_id = aws_subnet.pub_subnet_az2[0].id
  route_table_id = aws_route_table.route_via_igw[0].id
}

resource "aws_route_table_association" "pub_subnet3_route_table_association" {
  count = local.CreateSubnet3 ? 1 : 0
  subnet_id = aws_subnet.pub_subnet_az3[0].id
  route_table_id = aws_route_table.route_via_igw[0].id
}

resource "aws_security_group" "ecs_security_group" {
  count = local.CreateNewSecurityGroup ? 1 : 0
  description = "ECS Allowed Ports"
  vpc_id = local.CreateSubnet1 ? aws_vpc.vpc[0].id : var.vpc_id
  ingress {
    protocol = "tcp"
    from_port = var.security_ingress_from_port
    to_port = var.security_ingress_to_port
    cidr_blocks = var.security_ingress_cidr_ip
  }

  egress {
     from_port   = 0
     to_port     = 0
     protocol    = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }
}

resource "aws_launch_template" "ecs_instance_lt" {
  name = "ecs_instance_demo"

  block_device_mappings {
    device_name = "/dev/sdm"

    ebs {
      volume_type = "gp2"
      volume_size = 20
    }
  }

  ebs_optimized = true

  iam_instance_profile {
    name = var.iam_role_instance_profile
  }

  image_id = var.ecs_ami_id

  instance_type = var.ecs_instance_type

  key_name = local.CreateEC2LCWithKeyPair ? var.key_name : null

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [local.CreateNewSecurityGroup ? aws_security_group.ecs_security_group[0].id : var.security_group_id]
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode("#!/bin/bash\necho ECS_CLUSTER=${var.ecs_cluster_name} >> /etc/ecs/ecs.config")
}

resource "aws_autoscaling_group" "ecs_instance_asg" {
  vpc_zone_identifier = local.CreateSubnet1 ? local.CreateSubnet2 ? local.CreateSubnet3 ? [aws_subnet.pub_subnet_az1[0].id, aws_subnet.pub_subnet_az2[0].id, aws_subnet.pub_subnet_az3[0].id] : [aws_subnet.pub_subnet_az1[0].id, aws_subnet.pub_subnet_az2[0].id] : [aws_subnet.pub_subnet_az1[0].id] : var.subnet_ids
  desired_capacity   = 3
  max_size           = 6
  min_size           = 1

  launch_template {
    id = aws_launch_template.ecs_instance_lt.id
    version = aws_launch_template.ecs_instance_lt.latest_version
  }
}

resource "aws_ecs_capacity_provider" "demoCapacity" {
  name = "demoCapacity"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_instance_asg.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 3
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 10
    }
  }
}

resource "aws_autoscaling_lifecycle_hook" "ecs_instance_asg_lifecycle_hook" {
  name                   = "foobar"
  autoscaling_group_name = aws_autoscaling_group.ecs_instance_asg.name
  default_result         = "CONTINUE"
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"

  notification_target_arn = aws_sns_topic.asgsns_topic.id
  role_arn = aws_iam_role.sns_lambda_role.arn
}

resource "aws_ecs_task_definition" "taskdefinition" {
  family = "sample_td_family"
  container_definitions = jsonencode([
    {
      Name = "ecs-sample-app"
      MountPoints = [
        {
          SourceVolume = "my-vol"
          ContainerPath = "/var/www/my-vol"
        }
      ]
      Image = "amazon/amazon-ecs-sample"
      Cpu = 10
      PortMappings = [
        {
          ContainerPort = 80
          HostPort = 80
        }
      ]
      EntryPoint = [
        "/usr/sbin/apache2",
        "-D",
        "FOREGROUND"
      ]
      Memory = 500
      Essential = true
    },
    {
      Name = "busybox"
      Image = "busybox"
      Cpu = 10
      EntryPoint = [
        "sh",
        "-c"
      ]
      Memory = 500
      Command = [
        "/bin/sh -c \"while true; do /bin/date > /var/www/my-vol/date; sleep 1; done\""
      ]
      Essential = false
      VolumesFrom = [
        {
          SourceContainer = "ecs-sample-app"
        }
      ]
    }
  ])
  volume {
      host_path = "/var/lib/docker/vfs/dir/"
      name = "my-vol"
  }
}

resource "aws_ecs_service" "demo_service" {
  name = "demo_service"
  cluster = aws_ecs_cluster.my_cluster.arn
  deployment_maximum_percent = 100
  deployment_minimum_healthy_percent = 50
  desired_count = 2
  task_definition = aws_ecs_task_definition.taskdefinition.arn
}

resource "aws_iam_role" "ecs_service_role" {
  assume_role_policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ecs.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
  path = "/"
  inline_policy {
    name = "ecs-service"

    policy = jsonencode({
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "elasticloadbalancing:Describe*",
              "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
              "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
              "ec2:Describe*",
              "ec2:AuthorizeSecurityGroupIngress"
            ]
            Resource = "*"
          }
        ]
      })
    }
}

resource "aws_iam_role" "sns_lambda_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "autoscaling.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
  ]
  path = "/"
}

resource "aws_iam_role" "lambda_execution_role" {
  inline_policy {
    name = "lambda-inline"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "autoscaling:CompleteLifecycleAction",
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "ecs:ListContainerInstances",
              "ecs:DescribeContainerInstances",
              "ecs:UpdateContainerInstancesState",
              "sns:Publish"
            ]
            Resource = "*"
          }
        ]
    })
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
  ]

  path = "/"
}

resource "aws_sns_topic" "asgsns_topic" {
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.asgsns_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.lambda_function_for_asg.arn
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/lambda_function_payload.zip"
}

resource "aws_lambda_function" "lambda_function_for_asg" {
  function_name = "lambda_function_for_asg"
  description = "Gracefully drain ECS tasks from EC2 instances before the instances are terminated by autoscaling."
  handler = "index.lambda_handler"
  role = aws_iam_role.lambda_execution_role.arn
  runtime = "python3.9"
  memory_size = 128
  timeout = 60
  filename      = "${path.module}/lambda_function_payload.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}

resource "aws_lambda_permission" "lambda_invoke_permission" {
  function_name = aws_lambda_function.lambda_function_for_asg.arn
  action = "lambda:InvokeFunction"
  principal = "sns.amazonaws.com"
  source_arn = aws_sns_topic.asgsns_topic.id
}

resource "aws_sns_topic_subscription" "lambda_subscription_to_sns_topic" {
  endpoint = aws_lambda_function.lambda_function_for_asg.arn
  protocol = "lambda"
  topic_arn = aws_sns_topic.asgsns_topic.id
}
