############################################
# FSI Demo Environment — Terraform
# Recreates: VPC, subnets, routing, SGs,
# bastion, Satellite, AAP, 3x RHEL8, 3x RHEL9
############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-2"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name to use for all instances"
  type        = string
  default     = "fsi-workshop-key"
}

variable "my_ip_cidr" {
  description = "Your workstation's public IP in CIDR form, e.g. 1.2.3.4/32. Used for bastion SSH access."
  type        = string
}

variable "rhel9_ami" {
  description = "RHEL 9 AMI ID for this region (look up fresh via AWS AMI catalog — search RHEL-9, owner Red Hat)"
  type        = string
}

variable "rhel8_ami" {
  description = "RHEL 8 AMI ID for this region"
  type        = string
}

############################
# VPC + Networking
############################

resource "aws_vpc" "fsi_demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # CRITICAL — must be true, caused hours of DNS-resolution debugging when left off
  tags = { Name = "fsi-demo-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.fsi_demo.id
  tags   = { Name = "fsi-demo-igw" }
}

resource "aws_subnet" "public_mgmt" {
  vpc_id                  = aws_vpc.fsi_demo.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
  tags                    = { Name = "public-mgmt" }
}

resource "aws_subnet" "private_controlplane" {
  vpc_id            = aws_vpc.fsi_demo.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "private-controlplane" }
}

resource "aws_subnet" "private_corebanking" {
  vpc_id            = aws_vpc.fsi_demo.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "private-corebanking" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "fsi-demo-natgw-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_mgmt.id
  tags          = { Name = "fsi-demo-natgw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.fsi_demo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "fsi-demo-rt-public" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.fsi_demo.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "fsi-demo-rt-private" }
}

resource "aws_route_table_association" "public_mgmt" {
  subnet_id      = aws_subnet.public_mgmt.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "controlplane" {
  subnet_id      = aws_subnet.private_controlplane.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "corebanking" {
  subnet_id      = aws_subnet.private_corebanking.id
  route_table_id = aws_route_table.private.id
}

############################
# Security Groups
############################

resource "aws_security_group" "bastion" {
  name        = "fsi-sg-bastion-mgmt"
  description = "for anything with a public IP / your entry point"
  vpc_id      = aws_vpc.fsi_demo.id

  ingress {
    description = "SSH from workstation"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  ingress {
    description = "HTTPS from workstation (tunnel access)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fsi-sg-bastion-mgmt" }
}

resource "aws_security_group" "controlplane" {
  name        = "fsi-sg-controlplane"
  description = "Satellite + AAP tier"
  vpc_id      = aws_vpc.fsi_demo.id

  ingress {
    description     = "From bastion"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    description = "Self"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }
  # CRITICAL — added after discovering clients must reach Satellite directly
  # for subscription-manager registration (curl to Satellite's :443), not just
  # AAP-initiated automation traffic which flows the other direction.
  ingress {
    description     = "From corebanking (client registration to Satellite)"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.corebanking.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fsi-sg-controlplane" }
}

resource "aws_security_group" "corebanking" {
  name        = "fsi-sg-corebanking"
  description = "RHEL 8/9 client fleet"
  vpc_id      = aws_vpc.fsi_demo.id

  ingress {
    description     = "From bastion"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }
  ingress {
    description     = "From controlplane (AAP automation)"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.controlplane.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "fsi-sg-corebanking" }
}

############################
# Bastion
############################

resource "aws_instance" "bastion" {
  ami                         = var.rhel9_ami
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_mgmt.id
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  tags                        = { Name = "fsi-bastion-01" }
}

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id
  tags     = { Name = "fsi-bastion-01-eip" }
}

############################
# Satellite
############################

resource "aws_instance" "satellite" {
  ami                    = var.rhel9_ami
  instance_type          = "m5.2xlarge"
  subnet_id              = aws_subnet.private_controlplane.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.controlplane.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  ebs_block_device {
    device_name = "/dev/sdb"
    volume_size = 300
    volume_type = "gp3"
  }

  tags = { Name = "fsi-mgmt-satellite-01" }
}

############################
# AAP
############################

resource "aws_instance" "aap" {
  ami                    = var.rhel9_ami
  instance_type          = "m5.xlarge"
  subnet_id              = aws_subnet.private_controlplane.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.controlplane.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  tags = { Name = "fsi-mgmt-aap-01" }
}

############################
# RHEL 8 client fleet (core-banking-payments)
############################

resource "aws_instance" "rhel8_clients" {
  count                   = 3
  ami                     = var.rhel8_ami
  instance_type           = "t3.medium"
  subnet_id               = aws_subnet.private_corebanking.id
  key_name                = var.key_pair_name
  vpc_security_group_ids  = [aws_security_group.corebanking.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "core-banking-payments-0${count.index + 1}" }
}

############################
# RHEL 9 client fleet (core-banking-ledger)
############################

resource "aws_instance" "rhel9_clients" {
  count                   = 3
  ami                     = var.rhel9_ami
  instance_type           = "t3.medium"
  subnet_id               = aws_subnet.private_corebanking.id
  key_name                = var.key_pair_name
  vpc_security_group_ids  = [aws_security_group.corebanking.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "core-banking-ledger-0${count.index + 1}" }
}

############################
# Outputs
############################

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "satellite_private_ip" {
  value = aws_instance.satellite.private_ip
}

output "aap_private_ip" {
  value = aws_instance.aap.private_ip
}

output "rhel8_client_ips" {
  value = aws_instance.rhel8_clients[*].private_ip
}

output "rhel9_client_ips" {
  value = aws_instance.rhel9_clients[*].private_ip
}
