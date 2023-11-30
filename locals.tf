locals {
  CreateEC2LCWithKeyPair = !(var.key_name == "")
  CreateNewSecurityGroup = var.security_group_id == ""
  CreateNewVpc = var.vpc_id == ""

  CreateSubnet1 = alltrue([!(var.subnet_cidr1 == ""),local.CreateNewVpc])
  CreateSubnet2 = alltrue([!(var.subnet_cidr2 == ""),local.CreateSubnet1])  
  CreateSubnet3 = alltrue([!(var.subnet_cidr3 == ""),local.CreateSubnet2])
  
  CreateEbsVolume = alltrue([!(var.ebs_volume_size == "0"),!(var.ebs_volume_type == "")])
  stack_name = "ecs"
}

