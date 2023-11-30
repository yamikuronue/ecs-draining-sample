resource "aws_ecs_cluster" "my_cluster" {
  name = var.ecs_cluster_name
}

resource "aws_vpc" "vpc" {
  count = locals.CreateSubnet1 ? 1 : 0
  cidr_block = var.vpc_cidr
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
}

resource "aws_subnet" "pub_subnet_az1" {
  count = locals.CreateSubnet1 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].arn
  cidr_block = var.subnet_cidr1
  availability_zone = element(var.vpc_availability_zones, 0)
}

resource "aws_subnet" "pub_subnet_az2" {
  count = locals.CreateSubnet2 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].arn
  cidr_block = var.subnet_cidr2
  availability_zone = element(var.vpc_availability_zones, 1)
}

resource "aws_subnet" "pub_subnet_az3" {
  count = locals.CreateSubnet3 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].arn
  cidr_block = var.subnet_cidr3
  availability_zone = element(var.vpc_availability_zones, 2)
}

resource "aws_internet_gateway" "internet_gateway" {
  count = locals.CreateSubnet1 ? 1 : 0
}

resource "aws_vpn_gateway_attachment" "attach_gateway" {
  count = locals.CreateSubnet1 ? 1 : 0
  vpc_id = aws_internet_gateway.internet_gateway[0].id
}

resource "aws_route_table" "route_via_igw" {
  count = locals.CreateSubnet1 ? 1 : 0
  vpc_id = aws_vpc.vpc[0].arn
}

resource "aws_route" "public_route_via_igw" {
  count = locals.CreateSubnet1 ? 1 : 0
  route_table_id = aws_route_table.route_via_igw[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.internet_gateway[0].id
}

resource "aws_route_table_association" "pub_subnet1_route_table_association" {
  count = locals.CreateSubnet1 ? 1 : 0
  subnet_id = aws_subnet.pub_subnet_az1[0].id
  route_table_id = aws_route_table.route_via_igw[0].id
}

resource "aws_route_table_association" "pub_subnet2_route_table_association" {
  count = locals.CreateSubnet2 ? 1 : 0
  subnet_id = aws_subnet.pub_subnet_az2[0].id
  route_table_id = aws_route_table.route_via_igw[0].id
}

resource "aws_route_table_association" "pub_subnet3_route_table_association" {
  count = locals.CreateSubnet3 ? 1 : 0
  subnet_id = aws_subnet.pub_subnet_az3[0].id
  route_table_id = aws_route_table.route_via_igw[0].id
}

resource "aws_security_group" "ecs_security_group" {
  count = locals.CreateNewSecurityGroup ? 1 : 0
  description = "ECS Allowed Ports"
  vpc_id = local.CreateSubnet1 ? aws_vpc.vpc[0].arn : var.vpc_id
  ingress {
    protocol = "tcp"
    from_port = var.security_ingress_from_port
    to_port = var.security_ingress_to_port
    cidr_blocks = var.security_ingress_cidr_ip
  }
}

resource "aws_launch_configuration" "ecs_instance_lc" {
  image_id = var.ecs_ami_id
  instance_type = var.ecs_instance_type
  associate_public_ip_address = true
  iam_instance_profile = var.iam_role_instance_profile
  key_name = local.CreateEC2LCWithKeyPair ? var.key_name : null
  security_groups = [
    local.CreateNewSecurityGroup ? aws_security_group.ecs_security_group[0].arn : var.security_group_id
  ]
  ebs_block_device = [
    {
      device_name = "/dev/sdm"
      volume_type="gp2"
      volume_size=20
      iops="200"
    }
  ]
  user_data = base64encode("#!/bin/bash
echo ECS_CLUSTER=${var.ecs_cluster_name} >> /etc/ecs/ecs.config
")
}

resource "aws_autoscaling_group" "ecs_instance_asg" {
  availability_zones = local.CreateSubnet1 ? local.CreateSubnet2 ? local.CreateSubnet3 ? [
  "${aws_subnet.pub_subnet_az1[0].id}, ${aws_subnet.pub_subnet_az2[0].id}, ${aws_subnet.pub_subnet_az3[0].id}"] : [
  "${aws_subnet.pub_subnet_az1[0].id}, ${aws_subnet.pub_subnet_az2[0].id}"
  ] : [
    "${aws_subnet.pub_subnet_az1[0].id}"
  ] : var.subnet_ids
  desired_capacity   = 3
  max_size           = 3
  min_size           = 0

  launch_configuration = aws_launch_configuration.ecs_instance_lc.arn
}

resource "aws_autoscalingplans_scaling_plan" "ecs_instance_asg_plan" {

  name = aws_launch_configuration.ecs_instance_lc.id
  min_capacity = "0"
  max_capacity = "3"
  predictive_scaling_max_capacity_behavior = "3"
}

resource "aws_autoscaling_lifecycle_hook" "ecs_instance_asg_lifecycle_hook" {
  name                   = "foobar"
  autoscaling_group_name = aws_autoscaling_group.ecs_instance_asg.name
  default_result         = "CONTINUE"
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATE"

  notification_target_arn = aws_sns_topic.asgsns_topic.id
}

resource "aws_ecs_task_definition" "taskdefinition" {
  container_definitions = [
    {
      Name = "ecs-sample-app"
      MountPoints = [
        {
          SourceVolume = "my-vol"
          ContainerPath = "/var/www/my-vol"
        }
      ]
      Image = "amazon/amazon-ecs-sample"
      Cpu = "10"
      PortMappings = [
        {
          ContainerPort = "80"
          HostPort = "80"
        }
      ]
      EntryPoint = [
        "/usr/sbin/apache2",
        "-D",
        "FOREGROUND"
      ]
      Memory = "500"
      Essential = "true"
    },
    {
      Name = "busybox"
      Image = "busybox"
      Cpu = "10"
      EntryPoint = [
        "sh",
        "-c"
      ]
      Memory = "500"
      Command = [
        "/bin/sh -c "while true; do /bin/date > /var/www/my-vol/date; sleep 1; done""
      ]
      Essential = "false"
      VolumesFrom = [
        {
          SourceContainer = "ecs-sample-app"
        }
      ]
    }
  ]
  volume = [
    {
      host_path = {
        SourcePath = "/var/lib/docker/vfs/dir/"
      }
      name = "my-vol"
    }
  ]
}

resource "aws_ecs_service" "demo_service" {
  cluster = aws_ecs_cluster.my_cluster.arn
  deployment_maximum_percent = 100
  deployment_minimum_healthy_percent = 50
  desired_count = 2
  task_definition = aws_ecs_task_definition.taskdefinition.arn
}

resource "aws_iam_role" "ecs_service_role" {
  assume_role_policy = {
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
  }
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "ecs-service"
      PolicyDocument = {
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
      }
    }
  ]
}

resource "aws_iam_role" "sns_lambda_role" {
  assume_role_policy = {
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
  }
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
  ]
  path = "/"
}

resource "aws_iam_role" "lambda_execution_role" {
  force_detach_policies = [
    {
      PolicyName = "lambda-inline"
      PolicyDocument = {
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
      }
    }
  ]
  assume_role_policy = {
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
  }
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

resource "aws_lambda_function" "lambda_function_for_asg" {
  description = "Gracefully drain ECS tasks from EC2 instances before the instances are terminated by autoscaling."
  handler = "index.lambda_handler"
  role = aws_iam_role.lambda_execution_role.arn
  runtime = "python3.6"
  memory_size = 128
  timeout = 60
  code_signing_config_arn = {
    ZipFile = "import json
import time
import boto3

CLUSTER = '${var.ecs_cluster_name}'
REGION = '${data.aws_region.current.name}'

ECS = boto3.client('ecs', region_name=REGION)
ASG = boto3.client('autoscaling', region_name=REGION)
SNS = boto3.client('sns', region_name=REGION)

def find_ecs_instance_info(instance_id):
    paginator = ECS.get_paginator('list_container_instances')
    for list_resp in paginator.paginate(cluster=CLUSTER):
        arns = list_resp['containerInstanceArns']
        desc_resp = ECS.describe_container_instances(cluster=CLUSTER,
                                                     containerInstances=arns)
        for container_instance in desc_resp['containerInstances']:
            if container_instance['ec2InstanceId'] != instance_id:
                continue

            print('Found instance: id=%s, arn=%s, status=%s, runningTasksCount=%s' %
                  (instance_id, container_instance['containerInstanceArn'],
                   container_instance['status'], container_instance['runningTasksCount']))

            return (container_instance['containerInstanceArn'],
                    container_instance['status'], container_instance['runningTasksCount'])

    return None, None, 0

def instance_has_running_tasks(instance_id):
    (instance_arn, container_status, running_tasks) = find_ecs_instance_info(instance_id)
    if instance_arn is None:
        print('Could not find instance ID %s. Letting autoscaling kill the instance.' %
              (instance_id))
        return False

    if container_status != 'DRAINING':
        print('Setting container instance %s (%s) to DRAINING' %
              (instance_id, instance_arn))
        ECS.update_container_instances_state(cluster=CLUSTER,
                                             containerInstances=[instance_arn],
                                             status='DRAINING')

    return running_tasks > 0

def lambda_handler(event, context):
    msg = json.loads(event['Records'][0]['Sns']['Message'])

    if 'LifecycleTransition' not in msg.keys() or \
       msg['LifecycleTransition'].find('autoscaling:EC2_INSTANCE_TERMINATING') == -1:
        print('Exiting since the lifecycle transition is not EC2_INSTANCE_TERMINATING.')
        return

    if instance_has_running_tasks(msg['EC2InstanceId']):
        print('Tasks are still running on instance %s; posting msg to SNS topic %s' %
              (msg['EC2InstanceId'], event['Records'][0]['Sns']['TopicArn']))
        time.sleep(5)
        sns_resp = SNS.publish(TopicArn=event['Records'][0]['Sns']['TopicArn'],
                               Message=json.dumps(msg),
                               Subject='Publishing SNS msg to invoke Lambda again.')
        print('Posted msg %s to SNS topic.' % (sns_resp['MessageId']))
    else:
        print('No tasks are running on instance %s; setting lifecycle to complete' %
              (msg['EC2InstanceId']))

        ASG.complete_lifecycle_action(LifecycleHookName=msg['LifecycleHookName'],
                                      AutoScalingGroupName=msg['AutoScalingGroupName'],
                                      LifecycleActionResult='CONTINUE',
                                      InstanceId=msg['EC2InstanceId'])
"
  }
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

resource "aws_autoscaling_lifecycle_hook" "asg_terminate_hook" {
  autoscaling_group_name = aws_autoscalingplans_scaling_plan.ecs_instance_asg.id
  default_result = "ABANDON"
  heartbeat_timeout = "900"
  lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = aws_sns_topic.asgsns_topic.id
  role_arn = aws_iam_role.sns_lambda_role.arn
}

