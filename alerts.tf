# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = {
    Environment = var.environment
    CostCentre  = "canary-testing"
    Owner       = "networktest"
    Application = "canary"
  }
}
resource "aws_kms_key" "sns_canary_cmk" {
  description             = "CMK for encrypting SNS topic: ${var.environment}-canary-alerts"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Account root admin
      {
        Sid    = "AllowAccountAdminsFullControl"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # CloudWatch Alarms (required)
      {
        Sid    = "AllowCloudWatchToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },

      # SNS service (required)
      {
        Sid    = "AllowSNSToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}
resource "aws_kms_alias" "cw_logs_alias" {
  name          = "alias/${var.environment}-cwlogs-slack-forwarder"
  target_key_id = aws_kms_key.cw_logs_cmk.key_id
}

# KMS Alias
resource "aws_kms_alias" "sns_canary_alias" {
  name          = "alias/${var.environment}-sns-canary"
  target_key_id = aws_kms_key.sns_canary_cmk.key_id
}

# SNS Topic (encrypted)
resource "aws_sns_topic" "canary_alerts" {
  name              = "${var.environment}-canary-alerts"
  kms_master_key_id = aws_kms_alias.sns_canary_alias.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublishFromCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.canary_alerts.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.tags
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
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Secrets Manager access 
resource "aws_iam_role_policy" "slack_secret_policy" {
  count = var.slack_secret_arn != "" ? 1 : 0

  name = "${var.environment}-slack-secret-policy"
  role = aws_iam_role.slack_lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.slack_secret_arn
    }]
  })
}

# Lambda packaging
data "archive_file" "slack_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/slack_forwarder.py"
  output_path = "${path.module}/build/slack_forwarder.zip"
}

# Lambda function
resource "aws_signer_signing_profile" "slack_forwarder" {
  name_prefix = "${var.environment}-slack-forwarder-"
  platform_id = "AWSLambda-SHA384-ECDSA"
  tags        = local.tags
}

resource "aws_lambda_code_signing_config" "slack_forwarder" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.slack_forwarder.arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }

  tags = local.tags
}
resource "aws_sqs_queue" "slack_forwarder_dlq" {
  name                      = "${var.environment}-slack-forwarder-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = aws_kms_key.cw_logs_cmk.arn
  tags                      = local.tags
}
resource "aws_iam_role_policy" "slack_forwarder_dlq_send" {
  name = "${var.environment}-slack-forwarder-dlq-send"
  role = aws_iam_role.slack_lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.slack_forwarder_dlq.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "slack_forwarder" {
  name              = "/aws/lambda/${aws_lambda_function.slack_forwarder.function_name}"
  kms_key_id        = aws_kms_key.cw_logs_cmk.arn
  retention_in_days = 365
  tags              = local.tags
}

resource "aws_lambda_function" "slack_forwarder" {
  filename                       = data.archive_file.slack_zip.output_path
  function_name                  = "${var.environment}-slack-forwarder"
  handler                        = "slack_forwarder.lambda_handler"
  role                           = aws_iam_role.slack_lambda_role.arn
  kms_key_arn                    = aws_kms_key.cw_logs_cmk.arn
  runtime                        = "python3.11"
  timeout                        = 10
  memory_size                    = 128
  reserved_concurrent_executions = 2
  code_signing_config_arn        = aws_lambda_code_signing_config.slack_forwarder.arn

  environment {
    variables = var.slack_secret_arn != "" ? {
      SLACK_SECRET_ARN = var.slack_secret_arn
      } : {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  source_code_hash = fileexists(data.archive_file.slack_zip.output_path) ? filebase64sha256(data.archive_file.slack_zip.output_path) : null
  tags             = local.tags
  depends_on       = [aws_cloudwatch_log_group.slack_forwarder]

  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = aws_sqs_queue.slack_forwarder_dlq.arn
  }
}

# SNS → Lambda subscription
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.canary_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_forwarder.arn

  depends_on = [aws_lambda_permission.allow_sns]
}

resource "aws_lambda_permission" "allow_sns" {
  function_name = aws_lambda_function.slack_forwarder.function_name
  action        = "lambda:InvokeFunction"
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.canary_alerts.arn
  statement_id  = "AllowSNSInvoke"
}

# CloudWatch Canary Alarm
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
  tags          = local.tags
}