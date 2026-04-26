variable "aws_region" {
  description = "AWS region to deploy all resources into"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Base name used for tagging and resource names"
  type        = string
  default     = "terraform-sample"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (ECS tasks and RDS)"
  type = object({
    primary   = string
    secondary = string
  })
  default = {
    primary   = "10.0.1.0/24"
    secondary = "10.0.2.0/24"
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (ALB)"
  type = object({
    primary   = string
    secondary = string
  })
  default = {
    primary   = "10.0.10.0/24"
    secondary = "10.0.11.0/24"
  }
}

variable "db_name" {
  description = "Name of the initial PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the PostgreSQL instance"
  type        = string
  default     = "appuser"
}

variable "db_allocated_storage" {
  description = "Allocated storage (in GB) for the PostgreSQL instance"
  type        = number
  default     = 20
}

variable "db_instance_class" {
  description = "Instance class for the PostgreSQL instance"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Engine version for the PostgreSQL instance"
  type        = string
  default     = "18.3"
}

variable "ecs_service_name" {
  description = "Name for the ECS service"
  type        = string
  default     = "sample-public-api"
}

variable "ecs_image_identifier" {
  description = "Full image URI for the ECS task. Defaults to the managed ECR repository with ecs_image_tag."
  type        = string
  default     = null
}

variable "ecs_image_tag" {
  description = "Container image tag to deploy from the ECR repository (used when ecs_image_identifier is null)"
  type        = string
  default     = "latest"
}

variable "ecs_container_port" {
  description = "Port exposed by the application container"
  type        = number
  default     = 8000
}

variable "ecs_cpu" {
  description = "CPU units for the ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Memory (MiB) for the ECS task"
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of ECS task instances"
  type        = number
  default     = 2
}

variable "ecs_secret_env_name" {
  description = "Environment variable name injected into the container for the Secrets Manager ARN"
  type        = string
  default     = "DB_CREDENTIALS_SECRET_ARN"
}

variable "ssm_instance_type" {
  description = "Instance type for the Session Manager helper EC2 instance"
  type        = string
  default     = "t3.micro"
}

variable "ssm_ami_id" {
  description = "Optional override AMI ID for the Session Manager helper EC2 instance"
  type        = string
  default     = null
}

variable "ssm_ami_ssm_parameter_name" {
  description = "SSM parameter that stores the default AMI ID when ssm_ami_id is null"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
  }
}
