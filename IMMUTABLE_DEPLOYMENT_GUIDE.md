# 🚀 Immutable Deployment Pipeline with Terraform & Packer

This guide provides step-by-step instructions for deploying an immutable infrastructure pipeline using Terraform and Packer for AWS.

## 📋 Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub Repo   │────│   CodePipeline   │────│   Packer Build  │
│  (Sample App)   │    │   (Triggered)    │    │    (AMI)        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │  Launch Template │    │ Instance Refresh │
                       │    (Updated)     │────│ (Rolling Deploy) │
                       └──────────────────┘    └─────────────────┘
```

## 🎯 Deployment Flow

1. **Base Infrastructure**: Deploy VPC, ALB, IAM, CodePipeline
2. **Sample Application**: Push code to trigger Packer AMI build  
3. **Automatic Update**: Pipeline updates launch template with new AMI
4. **Rolling Deployment**: Instance refresh replaces instances immutably

## 🏗️ Phase 1: Base Infrastructure Deployment

### Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform installed** (v1.0+)
3. **GitHub repository** for your sample application

### Step 1: Configure Variables

Edit `terraform.tfvars`:

```hcl
# Project Configuration
aws_region   = "ap-south-1"  # Your preferred region
project_name = "packer-imagebuilder-poc"
environment  = "dev"

# Deployment Configuration
deployment_phase = "base"  # Start with base infrastructure
enable_auto_ami_update = true

# GitHub Repository Configuration
github_repository = "your-github-username/your-sample-app-repo"  # UPDATE THIS!
```

### Step 2: Deploy Base Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan the base infrastructure
terraform plan

# Deploy base infrastructure (VPC, ALB, IAM, CodePipeline)
terraform apply
```

**What gets deployed in base phase:**
- ✅ VPC with public/private subnets
- ✅ Application Load Balancer
- ✅ IAM roles and policies
- ✅ CodePipeline and CodeBuild projects
- ✅ S3 bucket for artifacts
- ✅ CloudWatch log groups
- ❌ Launch Template (not created yet)
- ❌ Auto Scaling Group (not created yet)

### Step 3: Complete CodeStar Connection

1. Go to AWS Console → Developer Tools → CodePipeline
2. Find your pipeline: `{project_name}-packer-pipeline`
3. Click on the failed Source stage
4. Complete the GitHub authorization for CodeStar connection

## 📱 Phase 2: Sample Application Repository

### Step 1: Create Sample App Repository

Create a new GitHub repository with the following structure:

```
your-sample-app-repo/
├── package.json
├── server.js
├── buildspec.yml
├── deploy-buildspec.yml
├── packer-template.pkr.hcl
└── README.md
```

### Step 2: Add Application Files

**package.json:**
```json
{
  "name": "sample-app",
  "version": "1.0.0",
  "description": "Sample Node.js application for Packer deployment",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "test": "echo \"No tests specified\" && exit 0"
  },
  "dependencies": {
    "express": "^4.18.2",
    "morgan": "^1.10.0",
    "helmet": "^7.0.0",
    "cors": "^2.8.5"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
```

**server.js:** (Use the sample app from this repository)

**buildspec.yml:** (Copy from this repository)

**deploy-buildspec.yml:** (Copy from this repository)

**packer-template.pkr.hcl:** (Copy from this repository)

### Step 3: Test Pipeline

1. Push code to your GitHub repository
2. Monitor CodePipeline execution in AWS Console
3. Verify AMI creation in EC2 Console

## 🔄 Phase 3: Complete Deployment with Auto Scaling

### Step 1: Update Configuration

After successful AMI build, update `terraform.tfvars`:

```hcl
# Change deployment phase
deployment_phase = "complete"

# Enable Packer AMI usage
use_packer_ami = true
```

### Step 2: Deploy Auto Scaling Infrastructure

```bash
# Plan the complete infrastructure
terraform plan

# Deploy Auto Scaling Group and Launch Template
terraform apply
```

**What gets added in complete phase:**
- ✅ Launch Template with user data
- ✅ Auto Scaling Group with instance refresh
- ✅ CloudWatch alarms for scaling
- ✅ Deployment CodeBuild project
- ✅ Deploy stage in CodePipeline

## 🚀 Phase 4: Immutable Deployments

### How It Works

1. **Code Push**: Developer pushes code to GitHub
2. **Pipeline Trigger**: CodePipeline automatically starts
3. **Packer Build**: New AMI created with application changes
4. **Launch Template Update**: Pipeline updates template with new AMI ID
5. **Instance Refresh**: Rolling deployment replaces instances
6. **Health Checks**: ALB ensures only healthy instances receive traffic

### Monitoring Deployments

**CodePipeline Console:**
- Monitor build progress
- View logs for each stage
- Track deployment status

**Auto Scaling Console:**
- View instance refresh progress
- Monitor instance health
- Check rolling deployment status

**CloudWatch Logs:**
- Application logs: `/aws/ec2/{project_name}/packer-app`
- Build logs: CodeBuild log groups

### Example Deployment Flow

```bash
# Developer makes code changes
git add .
git commit -m "Update application feature"
git push origin main

# Pipeline automatically:
# 1. Pulls source from GitHub
# 2. Builds new AMI with Packer (5-10 minutes)
# 3. Updates launch template with new AMI
# 4. Starts instance refresh (2-5 minutes)
# 5. Replaces instances with zero downtime
```

## 🎛️ Configuration Options

### Instance Refresh Settings

```hcl
instance_refresh_preferences = {
  min_healthy_percentage = 90  # Keep 90% instances healthy during refresh
  instance_warmup       = 300 # Wait 5 minutes before considering instance healthy
}
```

### Auto Scaling Configuration

```hcl
min_size         = 1  # Minimum instances
max_size         = 3  # Maximum instances  
desired_capacity = 2  # Starting number of instances
```

### Packer Configuration

```hcl
use_packer_ami    = true                           # Use Packer-built AMIs
packer_source_ami = "ami-0c94855ba95b798c7"       # Base AMI for Packer
```

## 🔧 Troubleshooting

### Common Issues

**1. CodeStar Connection Failed**
```bash
# Check connection status
aws codestar-connections list-connections

# Update connection in AWS Console if needed
```

**2. Packer Build Failed**
```bash
# Check CodeBuild logs
aws logs get-log-events --log-group-name /aws/codebuild/{project-name}-packer-build
```

**3. Instance Refresh Stuck**
```bash
# Check refresh status
aws autoscaling describe-instance-refreshes --auto-scaling-group-name {asg-name}

# Cancel if needed
aws autoscaling cancel-instance-refresh --auto-scaling-group-name {asg-name}
```

**4. Launch Template Update Failed**
```bash
# Check deploy logs
aws logs get-log-events --log-group-name /aws/codebuild/{project-name}-deploy-update
```

### Debugging Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Check AWS resources
aws ec2 describe-launch-templates --launch-template-names {project-name}-packer-lt-*
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names {project-name}-packer-asg
aws ec2 describe-images --owners self --filters "Name=name,Values={project-name}-*"
```

## 🔒 Security Best Practices

1. **IAM Least Privilege**: Roles have minimal required permissions
2. **VPC Security**: Private subnets for EC2 instances
3. **ALB Security**: Public subnets with security groups
4. **S3 Encryption**: Pipeline artifacts encrypted at rest
5. **CloudWatch Logs**: Centralized logging for monitoring

## 📊 Monitoring & Observability

### Key Metrics to Monitor

1. **Pipeline Success Rate**: CodePipeline execution status
2. **Build Duration**: Packer AMI creation time
3. **Deployment Time**: Instance refresh completion time
4. **Application Health**: ALB target health checks
5. **Instance Metrics**: CPU, memory, disk utilization

### Alarms & Notifications

- High CPU utilization triggers scale-up
- Low CPU utilization triggers scale-down
- Failed deployments can trigger SNS notifications
- Health check failures alert on unhealthy instances

## 🎯 Next Steps

1. **Custom Metrics**: Add application-specific CloudWatch metrics
2. **Blue/Green Deployments**: Implement blue/green strategy for larger changes
3. **Multi-Environment**: Extend to staging/production environments
4. **Security Scanning**: Add vulnerability scanning to Packer builds
5. **Cost Optimization**: Implement automated instance scheduling

## 📚 Additional Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Packer Documentation](https://www.packer.io/docs)
- [AWS CodePipeline User Guide](https://docs.aws.amazon.com/codepipeline/)
- [Auto Scaling User Guide](https://docs.aws.amazon.com/autoscaling/ec2/userguide/)

---

**🎉 Congratulations!** You now have a fully automated immutable deployment pipeline that ensures zero-downtime deployments with infrastructure as code principles.
