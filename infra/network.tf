# ---------------------------------------------------------------------------
# Dedicated VPC.
#
# A dedicated VPC (rather than the default one) was an explicit requirement.
# The account probe showed 3 of 5 VPCs in use, so there is headroom.
#
# There is deliberately NO NAT gateway: the application instance sits in the
# public subnet with an Elastic IP, and the DB subnets need no egress. A NAT
# gateway would add roughly $33/month for no functional gain at this tier.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
    Tier = "public"
  }
}

# RDS requires a subnet group spanning at least two availability zones, even
# for a single-AZ instance.
resource "aws_subnet" "database" {
  count = length(var.db_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-db-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# The database subnets have no route to the internet gateway — the VPC's
# implicit local route is all they need.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-db-rt"
  }
}

# COUNT MUST COME FROM THE VARIABLE, NOT FROM aws_subnet.database.
#
# `count = length(aws_subnet.database)` reads a RESOURCE attribute, which on a
# first apply is unknown at plan time — terraform cannot know how many subnets
# will exist until it has created them, and refuses the plan with:
#
#   Error: Invalid count argument
#   The "count" value depends on resource attributes that cannot be determined
#   until apply
#
# var.db_subnet_cidrs is known at plan time and is the same length by
# construction (aws_subnet.database counts from it too), so indexing stays
# aligned.
resource "aws_route_table_association" "database" {
  count = length(var.db_subnet_cidrs)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ---------------------------------------------------------------------------
# Security groups — one per role, referencing each other rather than CIDRs.
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Public HTTP and administrative SSH for the application host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP served by Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for the Chef configure stage"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound for package, image and CloudWatch traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "database" {
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL reachable only from the application security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-db-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Declared as a standalone rule so the two security groups can reference each
# other without a cycle.
resource "aws_vpc_security_group_ingress_rule" "database_from_app" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the application host only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "database_egress" {
  security_group_id = aws_security_group.database.id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
