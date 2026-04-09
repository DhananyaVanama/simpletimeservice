# =============================================================================
# ecs.tf — ECS Cluster, Task Definition, Service, IAM Roles,
#          Auto Scaling, and CloudWatch Logs
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# All container stdout/stderr is shipped here via the awslogs driver.
# Retention is set to 7 days to keep costs low for dev/staging.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7
  tags              = { Name = "${local.name_prefix}-logs" }
}

# =============================================================================
# IAM Roles
# =============================================================================

# -----------------------------------------------------------------------------
# ECS Task Execution Role
# Used by the ECS AGENT (not the app code) to:
#   • Pull the container image from DockerHub / ECR
#   • Ship logs to CloudWatch
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-ecs-execution-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# ECS Task Role
# Attached to the RUNNING CONTAINER. Grant additional AWS permissions here
# if your app code needs to call other AWS services (S3, DynamoDB, etc.).
# Currently empty — the app has no AWS API calls.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-ecs-task-role" }
}

# =============================================================================
# ECS Cluster
# =============================================================================
resource "aws_ecs_cluster" "main" {
  name = local.name_prefix

  # Enable Container Insights for CPU / memory / task-count metrics in
  # CloudWatch. Disable to save a few cents in dev.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name_prefix}-cluster" }
}

# =============================================================================
# ECS Task Definition
# Describes the container(s) in a single "task" (like a pod in Kubernetes).
# =============================================================================
resource "aws_ecs_task_definition" "app" {
  family = local.name_prefix

  # Fargate requires awsvpc networking and these compatibility flags
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  # CPU and memory apply to the ENTIRE task (all containers inside it combined)
  cpu    = var.task_cpu    # 256 = 0.25 vCPU
  memory = var.task_memory # 512 MB

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    # ── Main application container ──────────────────────────────────────────
    {
      name      = "app"
      image     = var.container_image
      essential = true # if this container stops, the whole task is stopped

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      # Hard resource limits for the container.
      # cpu is in CPU units (same scale as task_cpu).
      # memory is a hard ceiling; memoryReservation is a soft lower bound.
      cpu               = var.task_cpu
      memory            = var.task_memory
      memoryReservation = 256 # soft limit; scheduler uses this for placement

      # Container-level health check (secondary to the ALB health check)
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}/health')\""]
        interval    = 30  # seconds between checks
        timeout     = 5   # seconds before a check is considered failed
        retries     = 3   # failed checks before unhealthy
        startPeriod = 15  # grace period after container start
      }

      # Logging — all stdout/stderr goes to CloudWatch Logs
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Read-only root filesystem for defence-in-depth.
      # Uvicorn needs to write nothing to disk, so this is safe.
      readonlyRootFilesystem = true

      # Prevent privilege escalation inside the container
      privileged             = false
      user                   = "appuser"
    }
  ])

  tags = { Name = "${local.name_prefix}-task-def" }
}

# =============================================================================
# ECS Service
# Keeps desired_count tasks running at all times; replaces failed tasks;
# integrates with the ALB target group.
# =============================================================================
resource "aws_ecs_service" "app" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Spread tasks across private subnets (= AZs) and attach to ALB
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # ← critical: tasks stay in private subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # Rolling deployment settings:
  #   minimum_healthy_percent = 100 → never take a task down before a new one is up
  #   maximum_percent         = 200 → allow up to 2× tasks during a deployment
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Wait for ALB health checks to pass before marking a deployment complete
  health_check_grace_period_seconds = 60

  # Propagate task-level tags to the service and tasks for Cost Explorer
  propagate_tags = "SERVICE"

  # Tell Terraform not to fight auto-scaling on desired_count after initial deploy
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_execution,
  ]

  tags = { Name = "${local.name_prefix}-service" }
}

# =============================================================================
# Auto Scaling
# Scales the ECS service between min_capacity and max_capacity based on
# average CPU utilisation across all running tasks.
# =============================================================================

# Register the ECS service as an auto-scalable target
resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

# Scale OUT policy — add tasks when CPU is high
resource "aws_appautoscaling_policy" "scale_out" {
  name               = "${local.name_prefix}-scale-out"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60  # seconds to wait before another scale-out
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1 # add 1 task per alarm breach
    }
  }
}

# CloudWatch alarm that fires when average CPU > scale_out_cpu_threshold
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.scale_out_cpu_threshold

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_out.arn]
  tags          = { Name = "${local.name_prefix}-alarm-cpu-high" }
}

# Scale IN policy — remove tasks when CPU is low
resource "aws_appautoscaling_policy" "scale_in" {
  name               = "${local.name_prefix}-scale-in"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  policy_type        = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300 # wait 5 min before scaling in again
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1 # remove 1 task per alarm breach
    }
  }
}

# CloudWatch alarm that fires when average CPU < scale_in_cpu_threshold
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.name_prefix}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5 # require sustained low CPU before scaling in
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.scale_in_cpu_threshold

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_appautoscaling_policy.scale_in.arn]
  tags          = { Name = "${local.name_prefix}-alarm-cpu-low" }
}
