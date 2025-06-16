# Get the most recent Amazon Linux 2 AMI as default fallback
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get the most recent AMI built by Packer
data "aws_ami" "packer_ami" {
  count       = var.use_packer_ami ? 1 : 0
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["${var.project_name}-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }


  filter {
    name   = "tag:Environment"
    values = [var.environment]
  }
}

# Launch Template using Packer-built AMI (only in complete phase)
resource "aws_launch_template" "packer_app" {
  count         = var.deployment_phase == "complete" ? 1 : 0
  name_prefix   = "${var.project_name}-packer-lt-"
  image_id      = var.use_packer_ami && length(data.aws_ami.packer_ami) > 0 ? data.aws_ami.packer_ami[0].id : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region          = var.aws_region
    project_name    = var.project_name
    environment     = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-packer-instance"
      Environment = var.environment
      BuildTool   = "Packer"
      LaunchedBy  = "AutoScalingGroup"
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-launch-template"
    Environment = var.environment
    BuildTool   = "Packer"
  }
}

# Auto Scaling Group (only in complete phase)
resource "aws_autoscaling_group" "packer_app" {
  count                     = var.deployment_phase == "complete" ? 1 : 0
  name                      = "${var.project_name}-packer-asg"
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = [aws_lb_target_group.packer_app[0].arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.packer_app[0].id
    version = "$Latest"
  }

  # Enable instance refresh for rolling deployments
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.instance_refresh_preferences.min_healthy_percentage
      instance_warmup       = var.instance_refresh_preferences.instance_warmup
      checkpoint_delay       = "600"
      checkpoint_percentages = [50, 100]
    }
    triggers = ["tag"]
  }

  # Protect from scale-in during deployments
  protect_from_scale_in = false

  # Wait for capacity timeout
  wait_for_capacity_timeout = "10m"

  tag {
    key                 = "Name"
    value               = "${var.project_name}-packer-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "BuildTool"
    value               = "Packer"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "CodeBuild"
    propagate_at_launch = false
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      desired_capacity,
      launch_template[0].version,
    ]
  }
}

# Auto Scaling Policies (only in complete phase)
resource "aws_autoscaling_policy" "scale_up" {
  count                  = var.deployment_phase == "complete" ? 1 : 0
  name                   = "${var.project_name}-packer-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.packer_app[0].name
}

resource "aws_autoscaling_policy" "scale_down" {
  count                  = var.deployment_phase == "complete" ? 1 : 0
  name                   = "${var.project_name}-packer-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.packer_app[0].name
}

# CloudWatch Alarms for Auto Scaling (only in complete phase)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count               = var.deployment_phase == "complete" ? 1 : 0
  alarm_name          = "${var.project_name}-packer-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.packer_app[0].name
  }

  tags = {
    Name        = "${var.project_name}-high-cpu-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  count               = var.deployment_phase == "complete" ? 1 : 0
  alarm_name          = "${var.project_name}-packer-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.packer_app[0].name
  }

  tags = {
    Name        = "${var.project_name}-low-cpu-alarm"
    Environment = var.environment
  }
}
