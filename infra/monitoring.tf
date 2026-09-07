# ---------------------------------------------------------------------------
# CloudWatch log groups.
#
# Created here (rather than letting the agent create them implicitly) so that
# retention is explicit and teardown removes them with the rest of the stack.
# The names match the collect_list in the Chef-managed agent configuration.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.project_name}/application"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-application-logs"
  }
}

resource "aws_cloudwatch_log_group" "nginx_access" {
  name              = "/${var.project_name}/nginx/access"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-nginx-access-logs"
  }
}

resource "aws_cloudwatch_log_group" "nginx_error" {
  name              = "/${var.project_name}/nginx/error"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-nginx-error-logs"
  }
}

# Surfaces a stopped/impaired instance without paging anyone: no SNS topic is
# wired at this tier, the alarm is visible in the console and via the API.
resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "${var.project_name}-instance-status"
  alarm_description   = "EC2 status check failed for the application host"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  tags = {
    Name = "${var.project_name}-instance-status"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-db-cpu"
  alarm_description   = "RDS CPU sustained above 80 percent"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  tags = {
    Name = "${var.project_name}-db-cpu"
  }
}
