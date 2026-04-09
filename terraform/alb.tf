# =============================================================================
# alb.tf — Application Load Balancer, Target Group, Listener, Security Groups
#
# The ALB sits in the public subnets and is the ONLY entry point from the
# internet. It forwards HTTP :80 traffic to healthy ECS tasks on port 8080
# in the private subnets.
# =============================================================================

# -----------------------------------------------------------------------------
# Security group: ALB
# Allows inbound HTTP from anywhere; allows outbound to ECS tasks only.
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "Allow inbound HTTP from the internet to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward traffic to ECS tasks"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    # Scoped to the VPC CIDR; only private-subnet tasks will actually receive it
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${local.name_prefix}-sg-alb" }
}

# -----------------------------------------------------------------------------
# Security group: ECS tasks
# Accepts traffic ONLY from the ALB security group. No direct internet access.
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-sg-ecs-tasks"
  description = "Allow inbound traffic from the ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (for DockerHub pulls via NAT, AWS APIs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-ecs-tasks" }
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# Deployed across both public subnets for high availability.
# -----------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false            # internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Access logs (optional — uncomment and set bucket name to enable)
  # access_logs {
  #   bucket  = "my-alb-access-logs"
  #   prefix  = local.name_prefix
  #   enabled = true
  # }

  tags = { Name = "${local.name_prefix}-alb" }
}

# -----------------------------------------------------------------------------
# Target Group
# ALB routes requests to this group; ECS registers/deregisters tasks here.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate tasks use IP targets, not instance IDs

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = var.health_check_interval
    timeout             = 5
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  # Allow in-flight requests to complete when a task is deregistered
  deregistration_delay = 30

  tags = { Name = "${local.name_prefix}-tg" }
}

# -----------------------------------------------------------------------------
# Listener — port 80 → forward to target group
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
