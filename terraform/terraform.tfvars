# =============================================================================
# terraform.tfvars — override defaults for your specific deployment
#
# !! NEVER commit real credentials or secrets to this file !!
# AWS authentication is handled via the AWS CLI / environment variables
# (see README for instructions).
# =============================================================================

aws_region = "us-east-1"

# ── Container ────────────────────────────────────────────────────────────────
# Replace with your actual DockerHub image after pushing:
#   docker build -t <your-dockerhub-user>/simpletimeservice:latest ./app
#   docker push <your-dockerhub-user>/simpletimeservice:latest
container_image = "<dockerhub-username>/simpletimeservice:latest"
container_port  = 8080

# ── Task sizing ──────────────────────────────────────────────────────────────
# 256 CPU units = 0.25 vCPU; 512 MB RAM.
# Sufficient for this lightweight JSON API.
task_cpu    = 256
task_memory = 512

# ── Service capacity ─────────────────────────────────────────────────────────
# 2 tasks spread across 2 AZs for high availability.
# Auto-scaling keeps between min_capacity and max_capacity.
desired_count = 2
min_capacity  = 2
max_capacity  = 10

# Scale out when average CPU across the service exceeds 60%.
scale_out_cpu_threshold = 60
# Scale in when average CPU drops below 20% (saves cost).
scale_in_cpu_threshold  = 20

# ── Networking ───────────────────────────────────────────────────────────────
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# ── Tags ─────────────────────────────────────────────────────────────────────
project_name = "SimpleTimeService"
environment  = "dev"
