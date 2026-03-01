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
  description = "CIDR blocks for the two private subnets (one per AZ)"
  type = object({
    primary   = string
    secondary = string
  })
  default = {
    primary   = "10.0.1.0/24"
    secondary = "10.0.2.0/24"
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

variable "app_runner_service_name" {
  description = "Name for the App Runner service"
  type        = string
  default     = "sample-public-api"
}

variable "app_runner_image_identifier" {
  description = "Image identifier for the App Runner service"
  type        = string
  default     = "public.ecr.aws/aws-containers/hello-app-runner:latest"
}

variable "app_runner_image_repository_type" {
  description = "Repository type for the App Runner image (ECR or ECR_PUBLIC)"
  type        = string
  default     = "ECR_PUBLIC"
}

variable "app_runner_port" {
  description = "Port exposed by the application image"
  type        = number
  default     = 8000
}

variable "app_runner_secret_env_name" {
  description = "Environment variable name exposed to the App Runner runtime for the Secrets Manager ARN"
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
