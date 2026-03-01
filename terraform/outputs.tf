output "vpc_id" {
  description = "ID of the VPC hosting the private subnets"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets shared by RDS, App Runner connector, and the SSM host"
  value       = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
}

output "rds_endpoint" {
  description = "Connection endpoint for the PostgreSQL instance"
  value       = aws_db_instance.postgres.address
}

output "app_runner_service_url" {
  description = "Public URL where the App Runner service is exposed"
  value       = aws_apprunner_service.this.service_url
}

output "app_runner_secret_arn" {
  description = "Secrets Manager ARN referenced by App Runner"
  value       = local.db_master_secret_arn
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
