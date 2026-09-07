# ---------------------------------------------------------------------------
# PostgreSQL RDS.
#
# Single-AZ db.t3.micro in the private subnets, reachable only from the
# application security group. Multi-AZ is listed as an optional enhancement:
# it roughly doubles the cost and was not requested.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-db-subnets"
  }
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log statements slower than 1s
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 3
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:30-Mon:05:30"

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  performance_insights_enabled = false
  enabled_cloudwatch_logs_exports = [
    "postgresql",
  ]

  tags = {
    Name = "${var.project_name}-db"
  }
}
