variable "project_name" {
  description = "Branch-scoped project name used as the prefix for every resource."
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "ssh_public_key" {
  description = "Public half of the platform-managed project keypair, registered as an EC2 key pair."
  type        = string
}

variable "db_password" {
  description = "Master password for the PostgreSQL RDS instance."
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "Address space for the dedicated VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet hosting the application instance."
  type        = string
  default     = "10.20.1.0/24"
}

variable "db_subnet_cidrs" {
  description = "Private subnets for the RDS subnet group (two AZs are required by RDS)."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for the application host."
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "employees"
}

variable "db_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "employees"
}

variable "app_port" {
  description = "Port the application container listens on (loopback only)."
  type        = number
  default     = 8080
}

variable "log_retention_days" {
  description = "CloudWatch log group retention."
  type        = number
  default     = 14
}
