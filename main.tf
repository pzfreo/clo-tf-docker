# main.tf
variable "awsprops" {
    type = map(string)
    default = {
    region = "eu-west-1"
    instance_type = "t3.micro"
    keyname = "pzf2"
  }
}
variable "student" {
  type = string
  default = "oxclo01"
}

provider "aws" {
  region = lookup(var.awsprops, "region")
}

terraform {
  required_version = ">= 0.12.0"
}

data "aws_vpc" "default" {
  default = true
}


data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

### EC2

module "dev_ssh_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = format("dev_ssh_sg_%s",var.student)
  description = format("Security group for dev_ssh_sg %s", var.student)
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]
}

module "ec2_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = format("ec2_sg_%s",var.student)
  description = format("Security group for ec2_sg %s", var.student)
  vpc_id      = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "https-443-tcp", "all-icmp"]
  egress_rules        = ["all-all"]
}


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

resource "aws_iam_instance_profile" "ec2_profile_clo_tfdc" {
  name = format("ec2_role_clo_tfdc_%s",var.student) 
  role = aws_iam_role.ec2_role_clo_tfdc.name
}


resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = lookup(var.awsprops, "instance_type")

  key_name = lookup(var.awsprops, "keyname")

  root_block_device {
    volume_size = 8
  }

  user_data = <<-EOF
    #!/bin/bash
    set -ex
    sudo apt update 
    sudo apt install docker.io -y
    sudo service docker start
    sudo usermod -a -G docker ubuntu
    sudo apt install python3-pip -y
    sudo pip3 install docker-compose
    # sudo curl -L https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    # sudo chmod +x /usr/local/bin/docker-compose
    git clone https://github.com/pzfreo/clo-tf-docker.git
    cd clo-tf-docker
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

