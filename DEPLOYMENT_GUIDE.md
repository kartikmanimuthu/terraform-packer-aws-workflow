# Deployment Guide: Packer vs EC2 Image Builder POC

This guide provides step-by-step instructions for deploying the complete POC infrastructure comparing Packer and EC2 Image Builder workflows.

## 📋 Prerequisites

### Tools Required
- AWS CLI v2 configured with appropriate permissions
- Terraform >= 1.0
- Git
- Packer >= 1.9.0 (for Packer workflow only)

### AWS Permissions Required
Your AWS user/role needs the following permissions:
- EC2 (full access for instances, AMIs, security groups)
- VPC (full access)
- IAM (create roles and policies)
- Application Load Balancer
- Auto Scaling Groups
- CodePipeline and CodeBuild
- Image Builder (for Image Builder workflow)
- S3 (for artifacts and logs)
- CloudWatch (logs and metrics)
- SNS (for notifications)

## 🔧 Setup Instructions

### Step 1: Repository Setup

1. **Create a Bitbucket/GitHub repository** for your sample application:
   ```bash
   # Copy the sample application
   cp -r sample-app/* /path/to/your/new/repo/
   cd /path/to/your/new/repo/
   
   # Initialize git repository
   git init
   git add .
   git commit -m "Initial commit: Sample Node.js application"
   
   # Add remote and push
   git remote add origin https://bitbucket.org/your-username/sample-node-app.git
   git push -u origin main
   ```

2. **Update repository URLs** in the Terraform configurations:
   - Edit `E2E/packer/packer-template.pkr.hcl`: Update the git clone URL
   - Edit `E2E/packer/codepipeline.tf`: Update GitHub/Bitbucket source configuration
   - Edit `E2E/ec2_image_builder/codepipeline.tf`: Update source configuration
   - Edit `E2E/ec2_image_builder/imagebuilder.tf`: Update git clone URL in components

3. **Store authentication credentials**:
   ```bash
   # For GitHub
   aws secretsmanager create-secret \
     --name github-token \
     --description "GitHub personal access token" \
     --secret-string '{"token":"your_github_token"}'
   
   # For Bitbucket (if using)
   aws secretsmanager create-secret \
     --name bitbucket-credentials \
     --description "Bitbucket app password" \
     --secret-string '{"username":"your_username","password":"your_app_password"}'
   ```

### Step 2: Deploy Common Infrastructure

```bash
cd E2E/common

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the common infrastructure
terraform apply

# Note the outputs - you'll need these for the next steps
terraform output
```

**Common Infrastructure Includes:**
- VPC with public/private subnets
- NAT Gateways and routing
- Security Groups
- IAM Roles and Policies
- Application Load Balancer
- Target Groups

### Step 3A: Deploy Packer Workflow

```bash
cd ../packer

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region = "us-west-2"
project_name = "packer-imagebuilder-poc"
environment = "dev"
bitbucket_repo_url = "https://your-username@bitbucket.org/your-username/sample-node-app.git"
instance_type = "t3.micro"
key_pair_name = "your-key-pair"  # Optional
EOF

# Plan the deployment
terraform plan -var-file=terraform.tfvars

# Apply the Packer workflow
terraform apply -var-file=terraform.tfvars
```

### Step 3B: Deploy EC2 Image Builder Workflow

```bash
cd ../ec2_image_builder

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region = "us-west-2"
project_name = "packer-imagebuilder-poc"
environment = "dev"
bitbucket_repo_url = "https://your-username@bitbucket.org/your-username/sample-node-app.git"
instance_type = "t3.micro"
key_pair_name = "your-key-pair"  # Optional
EOF

# Plan the deployment
terraform plan -var-file=terraform.tfvars

# Apply the Image Builder workflow
terraform apply -var-file=terraform.tfvars
```

## 🚀 Testing the Deployment

### Manual Pipeline Trigger

#### For Packer:
```bash
# Start the CodePipeline
aws codepipeline start-pipeline-execution \
  --name packer-imagebuilder-poc-packer-pipeline \
  --region us-west-2
```

#### For Image Builder:
```bash
# Start the CodePipeline
aws codepipeline start-pipeline-execution \
  --name packer-imagebuilder-poc-imagebuilder-pipeline \
  --region us-west-2

# Or manually trigger Image Builder pipeline
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn $(terraform output -raw image_pipeline_arn) \
  --region us-west-2
```

### Verify Deployment

1. **Check Load Balancer**:
   ```bash
   # Get ALB DNS name
   ALB_DNS=$(cd ../common && terraform output -raw alb_dns_name)
   
   # Test health endpoint
   curl http://$ALB_DNS/health
   
   # Test application endpoint
   curl http://$ALB_DNS/
   ```

2. **Monitor Build Progress**:
   - AWS Console → CodePipeline → Your pipeline
   - AWS Console → CodeBuild → Build projects
   - AWS Console → Image Builder → Image pipelines (for Image Builder)

3. **Check Auto Scaling Group**:
   ```bash
   # List ASG instances
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names packer-imagebuilder-poc-packer-asg \
     --region us-west-2
   ```

## 📊 Monitoring and Troubleshooting

### CloudWatch Logs
- Application logs: `/aws/ec2/packer-imagebuilder-poc/packer-app` or `/aws/ec2/packer-imagebuilder-poc/imagebuilder-app`
- CodeBuild logs: `/aws/codebuild/packer-imagebuilder-poc-*`
- Image Builder logs: Check S3 bucket for logs

### Common Issues

1. **Build Timeouts**:
   - Increase CodeBuild timeout in `codepipeline.tf`
   - Check network connectivity from build environment

2. **Permission Errors**:
   - Verify IAM roles have required permissions
   - Check security group configurations

3. **AMI Not Found**:
   - Ensure Image Builder pipeline completed successfully
   - Check AMI sharing permissions
   - Verify AMI name filters in data sources

4. **Health Check Failures**:
   - Verify application starts correctly
   - Check security group allows traffic on port 3000
   - Verify target group health check configuration

### Useful Commands

```bash
# Check CodePipeline status
aws codepipeline get-pipeline-state \
  --name packer-imagebuilder-poc-packer-pipeline

# Check Image Builder execution status
aws imagebuilder list-image-build-versions \
  --image-version-arn "arn:aws:imagebuilder:region:account:image/recipe-name"

# Check ASG health
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names your-asg-name

# View recent CloudWatch logs
aws logs tail /aws/ec2/your-project/app --follow
```

## 🧹 Cleanup

To avoid ongoing costs, clean up resources in reverse order:

```bash
# Cleanup Packer workflow
cd E2E/packer
terraform destroy -var-file=terraform.tfvars

# Cleanup Image Builder workflow  
cd ../ec2_image_builder
terraform destroy -var-file=terraform.tfvars

# Cleanup common infrastructure
cd ../common
terraform destroy

# Delete S3 buckets (if not auto-deleted)
aws s3 rb s3://your-bucket-name --force
```

## 💡 Tips for Production

1. **State Management**: Use remote state (S3 + DynamoDB)
2. **Secrets**: Use AWS Secrets Manager or Parameter Store
3. **Monitoring**: Set up comprehensive CloudWatch dashboards
4. **Networking**: Use private subnets for application instances
5. **Security**: Implement least-privilege IAM policies
6. **Backup**: Enable AMI backup and retention policies
7. **Cost Optimization**: Use appropriate instance types and Auto Scaling policies

---

For questions or issues, check the troubleshooting section above or review AWS service documentation.