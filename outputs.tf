# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "packer_security_group_id" {
  description = "ID of the Packer security group"
  value       = aws_security_group.packer.id
}

output "packer_instance_profile" {
  description = "Name of the Packer instance profile"
  value       = aws_iam_instance_profile.packer_profile.name
}

# CodePipeline Outputs
output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.packer_pipeline.name
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.packer_build.name
}

output "s3_artifacts_bucket" {
  description = "Name of the S3 artifacts bucket"
  value       = aws_s3_bucket.codepipeline_artifacts.id
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar connection"
  value       = aws_codestarconnections_connection.github.arn
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = var.deployment_phase == "complete" ? aws_lb.packer_app[0].dns_name : null
}

# Auto Scaling Group Outputs
output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = var.deployment_phase == "complete" ? aws_autoscaling_group.packer_app[0].name : null
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = var.deployment_phase == "complete" ? aws_launch_template.packer_app[0].id : null
}
