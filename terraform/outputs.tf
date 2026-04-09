# =============================================================================
# outputs.tf — values printed after `terraform apply`
# =============================================================================

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer. Open this in a browser."
  value       = "http://${aws_lb.main.dns_name}/"
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer (useful for debugging)."
  value       = aws_lb.main.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group where container logs are shipped."
  value       = aws_cloudwatch_log_group.app.name
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets where ECS tasks run."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets where the ALB lives."
  value       = aws_subnet.public[*].id
}
