# Packer AWS Infrastructure

This directory contains a consolidated Terraform configuration that provisions a complete AWS infrastructure for building and deploying AMIs using Packer within a CI/CD pipeline.

## Architecture Overview

This infrastructure includes:

- **VPC Setup**: Complete network infrastructure with public/private subnets, NAT gateways, and security groups
- **Application Load Balancer**: ALB with target groups for distributing traffic
- **Auto Scaling Group**: EC2 instances running your application with auto-scaling capabilities
- **CodePipeline & CodeBuild**: CI/CD pipeline that triggers Packer builds from GitHub
- **IAM Roles & Policies**: Proper permissions for all services
- **CloudWatch**: Logging and monitoring for the infrastructure

## Directory Structure

```
packer-consolidated/
├── main.tf              # Terraform providers and configuration
├── vpc.tf               # VPC, subnets, NAT gateways, security groups
├── iam.tf               # IAM roles and policies
├── alb.tf               # Application Load Balancer configuration
├── asg.tf               # Auto Scaling Group and launch templates
├── codepipeline.tf      # CodePipeline and CodeBuild configuration
├── data.tf              # Data sources
├── variables.tf         # Variable definitions
├── outputs.tf           # Output values
├── terraform.tfvars     # Variable values
├── user_data.sh         # EC2 instance initialization script
└── README.md           # This file
```

## Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Terraform installed** (version >= 1.0)
3. **GitHub repository** with your application code
4. **EC2 Key Pair** (optional, for SSH access)

## Configuration

### Required Updates

Before deploying, update the following in `terraform.tfvars`:

1. **GitHub Repository**: Update `github_repository` with your actual repository (format: `owner/repo`)
2. **Key Pair**: Set `key_pair_name` if you want SSH access to instances
3. **Region**: Adjust `aws_region` and `packer_source_ami` if using a different region

### Key Variables

- `use_packer_ami`: Set to `false` initially, then `true` after building your first AMI
- `packer_source_ami`: Base AMI for Packer builds (Amazon Linux 2)
- `github_repository`: Your GitHub repository for source code

## Deployment Steps

### 1. Initialize Terraform

```bash
cd packer-consolidated
terraform init
```

### 2. Plan Deployment

```bash
terraform plan
```

### 3. Deploy Infrastructure

```bash
terraform apply
```

### 4. Configure CodeStar Connection

After deployment, you need to complete the GitHub connection:

1. Go to AWS Console → Developer Tools → CodeStar Connections
2. Find the connection created by Terraform
3. Click "Update pending connection" and authorize GitHub access

### 5. Setup Your Application Repository

Your GitHub repository should contain:

- `buildspec.yml`: CodeBuild specification for Packer
- Packer templates (`.pkr.hcl` files)
- Application source code

## Sample Repository Structure

Create a separate repository with this structure:

```
your-app-repo/
├── buildspec.yml           # CodeBuild build specification
├── packer/
│   ├── app.pkr.hcl         # Packer template
│   └── scripts/
│       └── install-app.sh  # Application installation script
├── src/                    # Your application source code
├── package.json           # Node.js dependencies (if applicable)
└── README.md              # Application documentation
```

## Sample Files for Your Repository

### buildspec.yml

```yaml
version: 0.2

phases:
  install:
    runtime-versions:
      golang: 1.19
    commands:
      - echo Installing Packer
      - wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
      - unzip packer_1.9.4_linux_amd64.zip
      - mv packer /usr/local/bin/
      - packer version

  pre_build:
    commands:
      - echo Pre-build phase started on `date`
      - echo Validating Packer template
      - cd packer
      - packer validate app.pkr.hcl

  build:
    commands:
      - echo Build phase started on `date`
      - echo Building AMI with Packer
      - packer build app.pkr.hcl

  post_build:
    commands:
      - echo Build phase completed on `date`
      - echo AMI build completed successfully
```

### packer/app.pkr.hcl

```hcl
packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "project_name" {
  type    = string
  default = "${PROJECT_NAME}"
}

variable "environment" {
  type    = string
  default = "${ENVIRONMENT}"
}

variable "region" {
  type    = string
  default = "${AWS_DEFAULT_REGION}"
}

variable "vpc_id" {
  type    = string
  default = "${VPC_ID}"
}

variable "subnet_id" {
  type    = string
  default = "${SUBNET_ID}"
}

variable "security_group_id" {
  type    = string
  default = "${SECURITY_GROUP_ID}"
}

variable "instance_profile" {
  type    = string
  default = "${INSTANCE_PROFILE}"
}

source "amazon-ebs" "app" {
  ami_name      = "${var.project_name}-${var.environment}-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.region
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id
  security_group_id = var.security_group_id
  
  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }
  
  ssh_username = "ec2-user"
  iam_instance_profile = var.instance_profile
  
  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    BuildTool   = "Packer"
    BuiltBy     = "CodeBuild"
  }
}

build {
  name = "app-build"
  sources = [
    "source.amazon-ebs.app"
  ]

  provisioner "file" {
    source      = "../src"
    destination = "/tmp/"
  }

  provisioner "shell" {
    script = "scripts/install-app.sh"
  }
}
```

## Usage

### Initial Deployment

1. Deploy with `use_packer_ami = false` to use the base AMI
2. Trigger a pipeline build to create your first custom AMI
3. Update `use_packer_ami = true` and run `terraform apply` to use the custom AMI

### Ongoing Operations

- Push changes to your GitHub repository to trigger automatic builds
- Monitor builds in AWS CodePipeline console
- View application logs in CloudWatch
- Access your application via the ALB DNS name (found in Terraform outputs)

## Monitoring

- **CloudWatch Logs**: Application and system logs
- **CloudWatch Metrics**: CPU, memory, and disk utilization
- **Auto Scaling**: Automatic scaling based on CPU utilization

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: Ensure you don't have important data in the S3 bucket before destroying.

## Troubleshooting

### Common Issues

1. **CodeStar Connection**: Ensure GitHub connection is properly authorized
2. **AMI Not Found**: Check that `use_packer_ami` is set correctly
3. **Permissions**: Verify AWS credentials have necessary permissions
4. **VPC Limits**: Ensure you haven't reached VPC or subnet limits in your region

### Logs to Check

- CodeBuild logs in AWS console
- CloudWatch logs for application issues
- EC2 instance system logs for boot issues

## Security Considerations

- Security groups are configured with minimal required access
- IAM roles follow principle of least privilege
- S3 bucket has encryption enabled and public access blocked
- Private subnets are used for EC2 instances