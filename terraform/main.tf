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

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

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

resource "aws_security_group" "app_runner" {
  name        = "${local.name_prefix}-apprunner-sg"
  description = "Security group used by the App Runner VPC connector"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-apprunner-sg"
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
  description = "Allow PostgreSQL only from App Runner and SSM host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_runner.id]
    description     = "App Runner access on 5432"
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

resource "aws_db_subnet_group" "rds" {
  name       = "${local.name_prefix}-rds-subnets"
  subnet_ids = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
  })
}

resource "aws_db_instance" "postgres" {
  identifier              = "${local.name_prefix}-postgres"
  allocated_storage       = var.db_allocated_storage
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  db_name                 = var.db_name
  username                = var.db_username
  manage_master_user_password = true
  master_user_secret_kms_key_id = aws_kms_key.secrets.arn
  port                    = 5432
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  multi_az                = true
  storage_encrypted       = true
  publicly_accessible     = false
  backup_retention_period = 1
  skip_final_snapshot     = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-postgres"
  })
}

locals {
  db_master_secret_arn = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

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

data "aws_iam_policy_document" "apprunner_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com", "tasks.apprunner.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "apprunner_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [local.db_master_secret_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.secrets.arn]
  }
}

resource "aws_iam_role" "apprunner_service" {
  name               = "${local.name_prefix}-apprunner-role"
  assume_role_policy = data.aws_iam_policy_document.apprunner_assume.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-apprunner-role"
  })
}

resource "aws_iam_role_policy" "apprunner_secrets" {
  name   = "${local.name_prefix}-apprunner-secrets"
  role   = aws_iam_role.apprunner_service.id
  policy = data.aws_iam_policy_document.apprunner_secrets.json
}

resource "aws_apprunner_vpc_connector" "this" {
  vpc_connector_name = "${local.name_prefix}-connector"
  subnets            = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
  security_groups    = [aws_security_group.app_runner.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-apprunner-connector"
  })
}

resource "aws_apprunner_service" "this" {
  service_name     = var.app_runner_service_name

  source_configuration {
    auto_deployments_enabled = false

    image_repository {
      image_identifier      = var.app_runner_image_identifier
      image_repository_type = var.app_runner_image_repository_type

      image_configuration {
        port = var.app_runner_port
        runtime_environment_secrets = {
          (var.app_runner_secret_env_name) = local.db_master_secret_arn
        }
      }
    }
  }

  instance_configuration {
    instance_role_arn = aws_iam_role.apprunner_service.arn
  }

  network_configuration {
    egress_configuration {
      egress_type       = "VPC"
      vpc_connector_arn = aws_apprunner_vpc_connector.this.arn
    }

    ingress_configuration {
      is_publicly_accessible = true
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-app-runner"
  })
}
