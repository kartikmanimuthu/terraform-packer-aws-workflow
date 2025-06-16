# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1"
}

variable "deployment_phase" {
  description = "Deployment phase - 'base' for infrastructure only, 'complete' for with ASG"
  type        = string
  default     = "complete"

  validation {
    condition     = contains(["base", "complete"], var.deployment_phase)
    error_message = "Deployment phase must be either 'base' or 'complete'."
  }
}

variable "enable_auto_ami_update" {
  description = "Enable automatic AMI updates in launch template via CodePipeline"
  type        = bool
  default     = true
}

variable "instance_refresh_preferences" {
  description = "Instance refresh preferences for rolling deployments"
  type = object({
    min_healthy_percentage = number
    instance_warmup        = number
  })
  default = {
    min_healthy_percentage = 90
    instance_warmup        = 300
  }
}

# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "packer-imagebuilder-poc"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name"
  type        = string
  default     = ""
}

# Auto Scaling Configuration
variable "min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2
}

# Packer Configuration
variable "use_packer_ami" {
  description = "Whether to use Packer-built AMI or source AMI"
  type        = bool
  default     = false
}

# GitHub Configuration
variable "github_repository" {
  description = "GitHub repository for source code (format: owner/repo)"
  type        = string
  default     = "your-github-username/sample-app"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}
