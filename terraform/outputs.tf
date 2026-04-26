output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (ECS tasks and RDS)"
  value       = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB)"
  value       = [aws_subnet.public_primary.id, aws_subnet.public_secondary.id]
}

output "rds_endpoint" {
  description = "Connection endpoint for the PostgreSQL instance"
  value       = aws_db_instance.postgres.address
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for the RDS master user credentials"
  value       = local.db_master_secret_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application container image"
  value       = aws_ecr_repository.app.repository_url
}

output "kms_key_arn" {
  description = "KMS key ARN securing the Secrets Manager secret"
  value       = aws_kms_key.secrets.arn
}

output "ssm_ec2_instance_id" {
  description = "Instance ID of the Session Manager helper EC2 instance"
  value       = aws_instance.ssm_worker.id
}

output "ssm_ec2_private_ip" {
  description = "Private IP of the Session Manager helper EC2 instance"
  value       = aws_instance.ssm_worker.private_ip
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}
