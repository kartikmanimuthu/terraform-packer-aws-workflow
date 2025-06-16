# Application Load Balancer
resource "aws_lb" "packer_app" {
  count              = var.deployment_phase == "complete" ? 1 : 0
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

# Target Group
resource "aws_lb_target_group" "packer_app" {
  count    = var.deployment_phase == "complete" ? 1 : 0
  name     = "${var.project_name}-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
  }
}

# ALB Listener
resource "aws_lb_listener" "packer_app" {
  count             = var.deployment_phase == "complete" ? 1 : 0
  load_balancer_arn = aws_lb.packer_app[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.packer_app[0].arn
  }

  tags = {
    Name        = "${var.project_name}-listener"
    Environment = var.environment
  }
}

# Key Pair for instances
resource "aws_key_pair" "packer_app" {
  count      = var.deployment_phase == "complete" ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.packer_app[0].public_key_openssh

  tags = {
    Name        = "${var.project_name}-key"
    Environment = var.environment
  }
}

# Private key for key pair
resource "tls_private_key" "packer_app" {
  count     = var.deployment_phase == "complete" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}
