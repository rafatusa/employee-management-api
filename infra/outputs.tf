# ---------------------------------------------------------------------------
# Outputs consumed by the configure, verify and validation stages.
#
# Every stage that needs one of these re-runs `terraform init` with the same
# backend flags and reads it with `terraform output -raw`. They are deliberately
# NOT threaded between jobs: values derived from the project name are masked by
# GitHub and silently dropped from job outputs.
# ---------------------------------------------------------------------------

output "instance_public_ip" {
  description = "Elastic IP of the application host — the public entrypoint."
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance id of the application host."
  value       = aws_instance.app.id
}

output "db_address" {
  description = "RDS endpoint hostname (no port)."
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "RDS port."
  value       = aws_db_instance.postgres.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "PostgreSQL master username."
  value       = aws_db_instance.postgres.username
}

output "vpc_id" {
  description = "Id of the dedicated VPC."
  value       = aws_vpc.main.id
}

output "ecr_repository_url" {
  description = "ECR repository URI the instance pulls the application image from."
  value       = aws_ecr_repository.app.repository_url
}

output "application_url" {
  description = "Base URL of the deployed API."
  value       = "http://${aws_eip.app.public_ip}"
}
