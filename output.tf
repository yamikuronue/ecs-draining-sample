output "ecs_instance_asg_name" {
  description = "Auto Scaling Group Name for ECS Instances"
  value = aws_autoscalingplans_scaling_plan.ecs_instance_asg.id
}

output "sns_topic_for_asg" {
  description = "Topic used by ASG to send notifications when instance state is changing"
  value = aws_sns_topic.asgsns_topic.id
}

