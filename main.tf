# main.tf

# Set your student id / AWS name here. It will be appended to all the resources that are createdo 
variable "student" {
  type = string
  default = "oxclo01"
}

# Other properties can be set here
variable "awsprops" {
    type = map(string)
    default = {
    region = "eu-west-1"
    instance_type = "t3.micro"
    dc-repository = "https://github.com/pzfreo/clo-tf-docker.git"
  }
}

# set the AWS region to use 
provider "aws" {
  region = lookup(var.awsprops, "region")
}

terraform {
  required_version = ">= 0.12.0"
}

# Use AWS VPC
data "aws_vpc" "default" {
  default = true
}

# Use the default AWS subnet
data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

### EC2

# create a security group to allow SSH
# Ideally this would be modified to only allow specific IP addresses

module "dev_ssh_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = format("dev_ssh_sg_%s",var.student)
  description = format("Security group for dev_ssh_sg %s", var.student)
  vpc_id      = data.aws_vpc.default.id

# You can change this to your public IP if needed
# ingress_cidr_blocks = ["214.83.74.111/32"]

# Allow SSH from anywhere IPv4
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]
}

# Create a security group to enable web access to the server

module "ec2_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = format("ec2_sg_%s",var.student)
  description = format("Security group for ec2_sg %s", var.student)
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "https-443-tcp", "all-icmp"]
  egress_rules        = ["all-all"]
}


# Use the most recent Ubuntu VM

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


# create a IAM role to allow the EC2 instance permission to act on your behalf

resource "aws_iam_role" "ec2_role_clo_tfdc" {
  name        = format("ec2_role_clo_tfdc_%s",var.student)

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

# Create an instance profile using the IAM role
resource "aws_iam_instance_profile" "ec2_profile_clo_tfdc" {
  name = format("ec2_role_clo_tfdc_%s",var.student) 
  role = aws_iam_role.ec2_role_clo_tfdc.name
}


# Create an AWS EC2 Instance

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = lookup(var.awsprops, "instance_type")

  key_name = var.student

  root_block_device {
    volume_size = 8
  }

  # Use the following User Data to install docker and docker compose, clone the repository 
  user_data = <<-EOF
    #!/bin/bash
    set -ex
    sudo apt update 
    sudo apt install docker.io -y
    sudo service docker start
    sudo usermod -a -G docker ubuntu
    sudo apt install python3-pip -y
    sudo pip3 install docker-compose
    cd /home/ubuntu
    git clone ${lookup(var.awsprops, "dc-repository")} dc
    cd dc
    docker-compose up --build
  EOF


  vpc_security_group_ids = [
    module.ec2_sg.security_group_id,
    module.dev_ssh_sg.security_group_id
    
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile_clo_tfdc.name

  tags = {
    Name = format("%s-tf",var.student)
  }


  monitoring              = true
  disable_api_termination = false
  ebs_optimized           = true
}

