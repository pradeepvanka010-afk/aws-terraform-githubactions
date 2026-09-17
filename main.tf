terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "githubactions-terraform-aws"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }

}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}


# Create Cluster VPC
resource "aws_vpc" "cluster_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "cluster-vpc"
  }
}

# Create Public Subnet
resource "aws_subnet" "cluster_public_subnet" {
  vpc_id            = aws_vpc.cluster_vpc.id
  cidr_block        = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"
  tags = {
    Name = "cluster-public-subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "cluster_igw" {
  vpc_id = aws_vpc.cluster_vpc.id
  tags = {
    Name = "cluster-igw"
  }
}

# Create a Route Table
resource "aws_route_table" "cluster_rtb" {
  vpc_id = aws_vpc.cluster_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster_igw.id
  }

  tags = {
    Name = "cluster-rtb"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "cluster_subnet_assoc" {
  subnet_id      = aws_subnet.cluster_public_subnet.id
  route_table_id = aws_route_table.cluster_rtb.id
}

# End of VPC Setup

# Create a Security Group
resource "aws_security_group" "cluster_sg" {
  vpc_id = aws_vpc.cluster_vpc.id
  tags = {
    Name = "cluster-sg"
  }
}

# Create Ingress Rules
resource "aws_vpc_security_group_ingress_rule" "ssh_ingress" {
  security_group_id = aws_security_group.cluster_sg.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Create Egress Rules
resource "aws_vpc_security_group_egress_rule" "all_egress" {
  security_group_id = aws_security_group.cluster_sg.id
  from_port         = 0
  to_port           = 0
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# EC2 Instances
resource "aws_instance" "cluster_instance" {
  count                       = 1

  ami                         = "ami-01a00762f46d584a1" # Ubuntu
  instance_type               = "t3.micro"

  subnet_id                   = aws_subnet.cluster_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.cluster_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.cluster_key.key_name

  # Root Volume (Default Storage)
  root_block_device {
    volume_size = 50  # Size in GB
    volume_type = "gp3"
  }

  # Additional EBS Volume
  ebs_block_device {
    device_name           = "/dev/xvdb"
    volume_size           = 100  # Size in GB
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "cluster-instance"
  }
}

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cluster_key" {
  key_name   = "cluster-key-pair"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "local_cluster_key" {
  content         = tls_private_key.pk.private_key_pem
  filename        = "./cluster-key-pair.pem"
  file_permission = "0400"
}