# =============================================================================
# variables.tf — all tuneable inputs for the SimpleTimeService deployment
# =============================================================================

# -----------------------------------------------------------------------------
# AWS region
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy all resources in."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for the two public subnets (one per AZ).
    The ALB and NAT Gateway live here.
  EOT
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for the two private subnets (one per AZ).
    ECS Fargate tasks run here; they have no inbound internet access.
  EOT
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# -----------------------------------------------------------------------------
# Container image
# -----------------------------------------------------------------------------
variable "container_image" {
  description = <<-EOT
    Fully-qualified Docker image reference for SimpleTimeService.
    Format: <registry>/<repo>:<tag>
    Example: "yourdockerhubuser/simpletimeservice:latest"
  EOT
  type    = string
  default = "yourdockerhubuser/simpletimeservice:latest"
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 8080
}

# -----------------------------------------------------------------------------
# ECS task sizing
# Each Fargate task is an isolated micro-VM; CPU and memory are hard limits.
#
# Valid CPU / memory combinations (AWS Fargate):
#   256 CPU  →  512 MB, 1024 MB, 2048 MB
#   512 CPU  →  1024–4096 MB (in 1024 MB steps)
#   1024 CPU →  2048–8192 MB (in 1024 MB steps)
#   2048 CPU →  4096–16384 MB
#   4096 CPU →  8192–30720 MB
#
# SimpleTimeService is a lightweight JSON API; 256/512 is plenty.
# Increase if you add sidecar containers (e.g. Fluent Bit).
# -----------------------------------------------------------------------------
variable "task_cpu" {
  description = "CPU units for each ECS Fargate task (1 vCPU = 1024 units)."
  type        = number
  default     = 256 # 0.25 vCPU
}

variable "task_memory" {
  description = "Memory (MB) for each ECS Fargate task."
  type        = number
  default     = 512
}

# -----------------------------------------------------------------------------
# ECS service capacity
# -----------------------------------------------------------------------------
variable "desired_count" {
  description = "Number of ECS tasks to run simultaneously (desired steady state)."
  type        = number
  default     = 2 # across 2 AZs for high availability
}

variable "min_capacity" {
  description = "Minimum number of tasks; auto-scaling will not go below this."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks; auto-scaling will not exceed this."
  type        = number
  default     = 10
}

# Auto-scaling thresholds
variable "scale_out_cpu_threshold" {
  description = "Average CPU % across the service that triggers a scale-OUT event."
  type        = number
  default     = 60
}

variable "scale_in_cpu_threshold" {
  description = "Average CPU % across the service that triggers a scale-IN event."
  type        = number
  default     = 20
}

# -----------------------------------------------------------------------------
# ALB health check
# -----------------------------------------------------------------------------
variable "health_check_path" {
  description = "HTTP path the ALB uses to health-check the tasks."
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Seconds between ALB health checks."
  type        = number
  default     = 30
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes before a task is marked healthy."
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures before a task is marked unhealthy."
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# Tagging
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Value applied to the 'Project' tag on every resource."
  type        = string
  default     = "SimpleTimeService"
}

variable "environment" {
  description = "Deployment environment tag (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}
