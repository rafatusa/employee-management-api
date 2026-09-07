# ---------------------------------------------------------------------------
# Application host: Ubuntu 22.04 EC2 instance with a static Elastic IP.
#
# The AMI is resolved from Canonical's official owner id rather than hardcoded:
# AMI ids are region-specific and are replaced on every Canonical release.
# Ubuntu implies SSH_USER=ubuntu, which is what the platform derives.
# ---------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# The platform generates and stores one keypair per project; terraform registers
# its public half. authorized_keys is seeded at launch by cloud-init from this
# key pair — it is the only injection path.
resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.project_name}-key"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.main.key_name
  iam_instance_profile   = aws_iam_instance_profile.app.name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  # Bootstrap only: real configuration is Chef's job in the configure stage.
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    apt-get update -y
    apt-get install -y python3 curl ca-certificates
  EOF

  # IAM instance profile creation races propagation; without this the first
  # apply intermittently fails and passes on retry.
  depends_on = [aws_iam_instance_profile.app]

  tags = {
    Name = "${var.project_name}-app"
  }
}

# The verify and validation stages resolve the host from this EIP, not from the
# instance's ephemeral public IP, so the address survives instance replacement.
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-eip"
  }
}
