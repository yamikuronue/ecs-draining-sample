variable ecs_cluster_name {
  description = "Specifies the ECS Cluster Name with which the resources would be associated"
  type = string
  default = "demoCluster"
}

variable key_name {
  description = "REQUIRED -  Specifies the name of an existing Amazon EC2 key pair to enable SSH access to the EC2 instances in your cluster."
  type = string
}

variable ecs_ami_id {
  description = "REQUIRED - Default ECS Optimized AMI for us-east-1 region. Please change it to reflect your regions' latest ECS AMI-ID"
  type = string
  default = "ami-0b74aeb97fba885ea"
}

variable ecs_instance_type {
  description = "Specifies the EC2 instance type for your container instances. Defaults to t2.medium"
  type = string
  default = "m5.large"
}

variable vpc_id {
  description = "Optional - Specifies the ID of an existing VPC in which to launch your container instances. If you specify a VPC ID, you must specify a list of existing subnets in that VPC. If you do not specify a VPC ID, a new VPC is created with atleast 1 subnet."
  type = string
  default = ""
}

variable subnet_ids {
  description = "Optional - Specifies the list of existing VPC Subnet Ids where ECS instances will run"
  default = []
}

variable security_group_id {
  description = "Optional - Specifies the Security Group Id of an existing Security Group. Leave blank to have a new Security Group created"
  type = string
  default = ""
}

variable vpc_cidr {
  description = "Optional - Specifies the CIDR Block of VPC"
  type = string
  default = "10.0.0.0/16"
}

variable subnet_cidr1 {
  description = "Specifies the CIDR Block of Subnet 1"
  type = string
  default = "10.0.0.0/24"
}

variable subnet_cidr2 {
  description = "Specifies the CIDR Block of Subnet 2"
  type = string
  default = "10.0.1.0/24"
}

variable subnet_cidr3 {
  description = "Specifies the CIDR Block of Subnet 3"
  type = string
  default = "10.0.2.0/24"
}

variable iam_role_instance_profile {
  description = "Specifies the Name or the Amazon Resource Name (ARN) of the instance profile associated with the IAM role for the instance"
  type = string
  default = "ecsInstanceRole"
}

variable security_ingress_from_port {
  description = "Optional - Specifies the Start of Security Group port to open on ECS instances - defaults to port 0"
  type = string
  default = "80"
}

variable security_ingress_to_port {
  description = "Optional - Specifies the End of Security Group port to open on ECS instances - defaults to port 65535"
  type = string
  default = "80"
}

variable security_ingress_cidr_ip {
  description = "Optional - Specifies the CIDR/IP range for Security Ports - defaults to 0.0.0.0/0"
  type = list(string)
  default = ["0.0.0.0/0"]
}

variable vpc_availability_zones {
  description = "Specifies a list of 3 VPC Availability Zones for the creation of new subnets. These zones must have the available status."
  type = list(string)
  default = ["us-west-2b","us-west-2c","us-west-2a"]
}

variable ebs_volume_size {
  description = "Optional - Specifies the Size in GBs, of the newly created Amazon Elastic Block Store (Amazon EBS) volume"
  type = string
  default = "22"
}

variable ebs_volume_type {
  description = "Optional - Specifies the Type of (Amazon EBS) volume"
  type = string
  default = "gp2"
}

