# ---------------------------------------------------------------------------
# Instance role.
#
# The host needs to ship logs and metrics to CloudWatch and pull the
# application image from ECR. Rather than placing credentials on the instance,
# it assumes this role through its instance profile. SSM managed-instance
# access is included so the operations console can reach the box without
# depending on the SSH path.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.project_name}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-app-role"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped explicitly to this project's log groups rather than a wildcard.
data "aws_iam_policy_document" "app_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = [
      "${aws_cloudwatch_log_group.application.arn}:*",
      "${aws_cloudwatch_log_group.nginx_access.arn}:*",
      "${aws_cloudwatch_log_group.nginx_error.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "app_logs" {
  name   = "${var.project_name}-app-logs"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_logs.json
}

# ---------------------------------------------------------------------------
# ECR pull access.
#
# GetAuthorizationToken is account-wide by API design (it takes no resource),
# so it must be granted on "*". The layer/manifest reads that actually expose
# image content are scoped to THIS project's repository only.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "app_ecr_pull" {
  statement {
    sid       = "GetAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PullThisRepositoryOnly"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "app_ecr_pull" {
  name   = "${var.project_name}-app-ecr-pull"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_ecr_pull.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-profile"
  role = aws_iam_role.app.name
}
