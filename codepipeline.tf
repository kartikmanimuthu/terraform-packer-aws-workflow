# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket        = "${var.project_name}-packer-pipeline-artifacts-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-packer-pipeline-artifacts"
    Environment = var.environment
    BuildTool   = "Packer"
  }
}

resource "aws_s3_bucket_versioning" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Group for CodeBuild
resource "aws_cloudwatch_log_group" "packer_app" {
  name              = "/aws/ec2/${var.project_name}/packer-app"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-packer-logs"
    Environment = var.environment
    BuildTool   = "Packer"
  }
}

# CodeBuild project for deployment (updating launch template)
resource "aws_codebuild_project" "deploy_update" {
  count        = var.deployment_phase == "complete" && var.enable_auto_ami_update ? 1 : 0
  name         = "${var.project_name}-deploy-update"
  description  = "Update launch template with new AMI and trigger instance refresh"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }

    environment_variable {
      name  = "ENVIRONMENT"
      value = var.environment
    }

    environment_variable {
      name  = "LAUNCH_TEMPLATE_ID"
      value = var.deployment_phase == "complete" ? aws_launch_template.packer_app[0].id : ""
    }

    environment_variable {
      name  = "ASG_NAME"
      value = var.deployment_phase == "complete" ? aws_autoscaling_group.packer_app[0].name : ""
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "codedeploy-buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.packer_app.name
      stream_name = "deploy"
    }
  }

  tags = {
    Name        = "${var.project_name}-deploy-update"
    Environment = var.environment
    BuildTool   = "Terraform"
  }
}

# CodeBuild project for Packer
resource "aws_codebuild_project" "packer_build" {
  name         = "${var.project_name}-packer-build"
  description  = "Build AMI using Packer"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }

    environment_variable {
      name  = "ENVIRONMENT"
      value = var.environment
    }

    environment_variable {
      name  = "VPC_ID"
      value = aws_vpc.main.id
    }

    environment_variable {
      name  = "SUBNET_ID"
      value = aws_subnet.public[0].id
    }

    environment_variable {
      name  = "SECURITY_GROUP_ID"
      value = aws_security_group.packer.id
    }

    environment_variable {
      name  = "INSTANCE_PROFILE"
      value = aws_iam_instance_profile.packer_profile.name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "codebuild-buildspec.yml"
  }

  vpc_config {
    vpc_id = aws_vpc.main.id

    subnets = aws_subnet.private[*].id

    security_group_ids = [
      aws_security_group.packer.id,
    ]
  }

  tags = {
    Name        = "${var.project_name}-packer-build"
    Environment = var.environment
    BuildTool   = "Packer"
  }
}

# CodeStar Connection for GitHub
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github"
  provider_type = "GitHub"
}

# CodePipeline
resource "aws_codepipeline" "packer_pipeline" {
  name     = "${var.project_name}-packer-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.github_repository # This needs to be set in variables
        BranchName       = "master"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.packer_build.name
      }
    }
  }

  dynamic "stage" {
    for_each = var.deployment_phase == "complete" && var.enable_auto_ami_update ? [1] : []
    content {
      name = "Deploy"

      action {
        name            = "UpdateLaunchTemplateAndRefresh"
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        input_artifacts = ["build_output"]

        configuration = {
          ProjectName = aws_codebuild_project.deploy_update[0].name
        }
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-packer-pipeline"
    Environment = var.environment
    BuildTool   = "Packer"
  }
}

# CloudWatch Event Rule to trigger pipeline on repository changes
resource "aws_cloudwatch_event_rule" "github_push" {
  name        = "${var.project_name}-github-push"
  description = "Trigger pipeline on GitHub push"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = ["master"]
    }
  })

  tags = {
    Name        = "${var.project_name}-github-push-rule"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule      = aws_cloudwatch_event_rule.github_push.name
  target_id = "TriggerPipeline"
  arn       = aws_codepipeline.packer_pipeline.arn
  role_arn  = aws_iam_role.codepipeline_role.arn
}
