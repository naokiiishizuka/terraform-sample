provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = var.ssm_ami_ssm_parameter_name
}

locals {
  primary_az   = element(data.aws_availability_zones.available.names, 0)
  secondary_az = element(data.aws_availability_zones.available.names, 1)
  name_prefix  = var.project_name
  tags = merge(var.tags, {
    Project = var.project_name
  })
  ssm_ami_id = coalesce(var.ssm_ami_id, data.aws_ssm_parameter.al2023_ami.value)
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------

resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager secrets (${local.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-secrets-kms"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.id
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.secrets.arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-app-repo"
  })
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# --- Private subnets (ECS tasks, RDS) ---

resource "aws_subnet" "private_primary" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs.primary
  availability_zone       = local.primary_az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-a"
  })
}

resource "aws_subnet" "private_secondary" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs.secondary
  availability_zone       = local.secondary_az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-c"
  })
}

# --- Public subnets (ALB) ---

resource "aws_subnet" "public_primary" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs.primary
  availability_zone       = local.primary_az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-a"
  })
}

resource "aws_subnet" "public_secondary" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs.secondary
  availability_zone       = local.secondary_az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-c"
  })
}

# --- Internet Gateway ---

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# --- Route tables ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public_primary" {
  subnet_id      = aws_subnet.public_primary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_secondary" {
  subnet_id      = aws_subnet.public_secondary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private_primary" {
  subnet_id      = aws_subnet.private_primary.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_secondary" {
  subnet_id      = aws_subnet.private_secondary.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Allow inbound from ALB to ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = var.ecs_container_port
    to_port         = var.ecs_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "ALB to ECS task"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-tasks-sg"
  })
}

resource "aws_security_group" "ssm_instance" {
  name        = "${local.name_prefix}-ssm-ec2-sg"
  description = "Session Manager EC2 host"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ssm-ec2-sg"
  })
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-endpoint-sg"
  description = "Allow HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-endpoint-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Allow PostgreSQL only from ECS tasks and SSM host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
    description     = "ECS tasks access on 5432"
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ssm_instance.id]
    description     = "SSM EC2 access on 5432"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "rds" {
  name       = "${local.name_prefix}-rds-subnets"
  subnet_ids = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
  })
}

resource "aws_db_instance" "postgres" {
  identifier                    = "${local.name_prefix}-postgres"
  allocated_storage             = var.db_allocated_storage
  engine                        = "postgres"
  engine_version                = var.db_engine_version
  instance_class                = var.db_instance_class
  db_name                       = var.db_name
  username                      = var.db_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.secrets.arn
  port                          = 5432
  vpc_security_group_ids        = [aws_security_group.rds.id]
  db_subnet_group_name          = aws_db_subnet_group.rds.name
  multi_az                      = true
  storage_encrypted             = true
  publicly_accessible           = false
  backup_retention_period       = 1
  skip_final_snapshot           = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-postgres"
  })
}

locals {
  db_master_secret_arn = aws_db_instance.postgres.master_user_secret[0].secret_arn
  ecs_image_identifier = coalesce(var.ecs_image_identifier, "${aws_ecr_repository.app.repository_url}:${var.ecs_image_tag}")
}

# ---------------------------------------------------------------------------
# SSM EC2 (DB access helper)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ssm_instance" {
  name = "${local.name_prefix}-ssm-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ssm-ec2-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance" {
  name = "${local.name_prefix}-ssm-ec2-profile"
  role = aws_iam_role.ssm_instance.name
}

resource "aws_instance" "ssm_worker" {
  ami                         = local.ssm_ami_id
  instance_type               = var.ssm_instance_type
  subnet_id                   = aws_subnet.private_primary.id
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance.name
  vpc_security_group_ids      = [aws_security_group.ssm_instance.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ssm-worker"
  })
}

# ---------------------------------------------------------------------------
# VPC Endpoints
# ---------------------------------------------------------------------------

# SSM (for EC2 Session Manager)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-ssm"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-ssmmessages"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-ec2messages"
  })
}

# ECR (for ECS Fargate image pull from private subnets)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-ecr-api"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-ecr-dkr"
  })
}

# S3 Gateway endpoint (for ECR layer pulls via S3)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-s3"
  })
}

# Secrets Manager (for ECS task secret injection)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-secretsmanager"
  })
}

# CloudWatch Logs (for ECS task log delivery)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpce-logs"
  })
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_primary.id, aws_subnet.public_secondary.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.ecs_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------------------
# ECS
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30

  tags = local.tags
}

# IAM: Task Execution Role (ECR pull + Secrets Manager + CloudWatch Logs)
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-exec-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.name_prefix}-ecs-exec-secrets"
  role = aws_iam_role.ecs_task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [local.db_master_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.secrets.arn]
      }
    ]
  })
}

# IAM: Task Role (application-level permissions)
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-task-role"
  })
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "app"
    image = local.ecs_image_identifier
    portMappings = [{
      containerPort = var.ecs_container_port
      protocol      = "tcp"
    }]
    secrets = [{
      name      = var.ecs_secret_env_name
      valueFrom = local.db_master_secret_arn
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-task-def"
  })
}

resource "aws_ecs_service" "app" {
  name            = var.ecs_service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.ecs_container_port
  }

  depends_on = [aws_lb_listener.http]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-service"
  })
}
