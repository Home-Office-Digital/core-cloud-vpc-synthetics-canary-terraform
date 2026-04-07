# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# KMS key for encrypted SNS canary alerts
resource "aws_kms_key" "sns_canary_cmk" {
  description             = "CMK for encrypting SNS topic: ${var.environment}-canary-alerts"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAdminsFullControl"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchAlarmsToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSNSServiceToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.tags
}

# KMS key for CloudWatch Logs + SQS DLQ + Lambda env encryption
resource "aws_kms_key" "cw_logs_cmk" {
  description             = "CMK for CloudWatch Logs + Slack forwarder DLQ (${var.environment})"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAdminsFullControl"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsUse"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSqsUse"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLambdaUse"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
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

resource "aws_kms_alias" "sns_canary_alias" {
  name          = "alias/${var.environment}-sns-canary"
  target_key_id = aws_kms_key.sns_canary_cmk.key_id
}

# SNS Topic (encrypted)
resource "aws_sns_topic" "canary_alerts" {
  name              = "${var.environment}-canary-alerts"
  kms_master_key_id = aws_kms_key.sns_canary_cmk.arn
  tags              = local.tags
}

data "aws_iam_policy_document" "canary_alerts_topic_policy" {
  statement {
    sid    = "AllowPublishFromCloudWatch"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.canary_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:cloudwatch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alarm:*"
      ]
    }
  }
}

resource "aws_sns_topic_policy" "canary_alerts" {
  arn    = aws_sns_topic.canary_alerts.arn
  policy = data.aws_iam_policy_document.canary_alerts_topic_policy.json
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

resource "aws_iam_role_policy_attachment" "slack_forwarder_vpc_access" {
  role       = aws_iam_role.slack_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

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

resource "aws_signer_signing_profile" "slack_forwarder" {
  name_prefix = local.signer_name_prefix
  platform_id = "AWSLambda-SHA384-ECDSA"
  tags        = local.tags
}

resource "aws_lambda_code_signing_config" "slack_forwarder" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.slack_forwarder.arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }

  tags = local.tags
}

resource "aws_sqs_queue" "slack_forwarder_dlq" {
  name                      = "${var.environment}-slack-forwarder-dlq"
  message_retention_seconds = 1209600
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
  name              = "/aws/lambda/${local.slack_forwarder_name}"
  kms_key_id        = aws_kms_key.cw_logs_cmk.arn
  retention_in_days = 365
  tags              = local.tags
}

resource "aws_lambda_function" "slack_forwarder" {
  filename         = data.archive_file.slack_zip.output_path
  source_code_hash = data.archive_file.slack_zip.output_base64sha256

  function_name                  = local.slack_forwarder_name
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

  tags = local.tags

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.slack_forwarder_dlq.arn
  }
}

# SNS -> Lambda subscription
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
  ok_actions    = [aws_sns_topic.canary_alerts.arn]
  tags          = local.tags
}