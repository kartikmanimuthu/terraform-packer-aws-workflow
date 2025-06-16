# Project Configuration
aws_region   = "ap-south-1"
project_name = "packer-imagebuilder-poc"
environment  = "dev"

# Deployment Configuration
deployment_phase       = "complete" # Set to "complete" after base infrastructure is ready
enable_auto_ami_update = true
instance_refresh_preferences = {
  min_healthy_percentage = 90
  instance_warmup        = 300
}

# Network Configuration
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

# EC2 Configuration
instance_type = "t3.micro"
key_pair_name = "" # Leave empty if no key pair needed

# Auto Scaling Configuration (used when deployment_phase = "complete")
min_size         = 1
max_size         = 3
desired_capacity = 2

# Packer Configuration
use_packer_ami = true # Set to true after first AMI is built

# GitHub Repository Configuration (UPDATE THIS!)
github_repository = "kartikmanimuthu/sample-webservice" # TODO: Update with your repo


