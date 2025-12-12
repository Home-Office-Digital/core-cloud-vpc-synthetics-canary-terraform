
# SNS Topic for Canary Alerts
resource "aws_sns_topic" "canary_alerts" {
  name              = "${var.environment}-canary-alerts"
  kms_master_key_id = "alias/aws/sns" # Enable SSE with AWS-managed KMS key for SNS
  tags = {
    Environment = var.environment
  }

}


# Lambda IAM Role
resource "aws_iam_role" "slack_lambda_role" {
  name = "${var.environment}-slack-forwarder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Secrets Manager Access 
resource "aws_iam_role_policy" "slack_secret_policy" {
  count = var.slack_secret_arn != "" ? 1 : 0

  name = "${var.environment}-slack-secret-policy"
  role = aws_iam_role.slack_lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue"],
      Resource = var.slack_secret_arn
    }]
  })
}

# Lambda Packaging
data "archive_file" "slack_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/slack_forwarder.py"
  output_path = "${path.module}/build/slack_forwarder.zip"
}

# Lambda Function

resource "aws_lambda_function" "slack_forwarder" {
  filename      = data.archive_file.slack_zip.output_path
  function_name = "${var.environment}-slack-forwarder"
  handler       = "slack_forwarder.lambda_handler"
  role          = aws_iam_role.slack_lambda_role.arn
  runtime       = "python3.11"
  timeout       = 10
  memory_size   = 128

  environment {
    variables = var.slack_secret_arn != "" ? {
      SLACK_SECRET_ARN = var.slack_secret_arn
      } : {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  source_code_hash = filebase64sha256(data.archive_file.slack_zip.output_path)
}

# SNS -> Lambda Subscription
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.canary_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_forwarder.arn
}

resource "aws_lambda_permission" "allow_sns" {
  function_name = aws_lambda_function.slack_forwarder.function_name
  action        = "lambda:InvokeFunction"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.canary_alerts.arn
  statement_id  = "AllowSNSInvoke"
}

# CloudWatch Alarm for Canary
resource "aws_cloudwatch_metric_alarm" "canary_failed" {
  alarm_name        = "${var.environment}-vpc-canary-failed"
  alarm_description = "Triggers Slack alert when the VPC connectivity canary fails"

  namespace           = "CloudWatchSynthetics"
  metric_name         = "Failed"
  period              = 60
  statistic           = "Sum"
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    CanaryName = aws_synthetics_canary.vpc_connectivity.name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.canary_alerts.arn]
}
