# tests/canary_tests.tftest.hcl

variables {
  bucket_name         = "test-canary-bucket-example"
  environment         = "dev"
  name_prefix         = "canary-test"
  vpc_id              = "vpc-12345678"
  subnet_ids          = ["subnet-12345678", "subnet-87654321"]
  security_group_ids  = ["sg-12345678"]
  target_ips          = ["10.0.1.10", "10.0.1.11"]
  allowed_ports       = ["443", "8443"]
  denied_ports        = ["25", "3306"]
  start_scan          = 1
  scan_end            = 500
  alert_on_open_ports = false
}

mock_provider "aws" {}

run "s3_security_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.canary_bucket.force_destroy == true
    error_message = "Canary bucket should allow force_destroy for cleanup."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.canary_bucket_block.block_public_acls,
      aws_s3_bucket_public_access_block.canary_bucket_block.block_public_policy,
      aws_s3_bucket_public_access_block.canary_bucket_block.ignore_public_acls,
      aws_s3_bucket_public_access_block.canary_bucket_block.restrict_public_buckets
    ])
    error_message = "S3 bucket public access block settings are not fully enabled."
  }

  assert {
    condition     = aws_s3_bucket_versioning.canary_bucket.versioning_configuration[0].status == "Enabled"
    error_message = "Bucket versioning must be enabled."
  }
}

run "s3_encryption_and_lifecycle" {
  command = plan

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.canary_bucket_encryption.rule :
      anytrue([
        for enc in rule.apply_server_side_encryption_by_default :
        enc.sse_algorithm == "aws:kms"
      ])
    ])
    error_message = "Bucket encryption must use KMS."
  }

  assert {
    condition     = aws_kms_key.canary_bucket_cmk.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled."
  }

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.canary_bucket.rule :
      anytrue([
        for exp in rule.expiration :
        exp.days == 30
      ])
    ])
    error_message = "Artifacts should expire after 30 days."
  }

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.canary_bucket.rule :
      anytrue([
        for exp in rule.noncurrent_version_expiration :
        exp.noncurrent_days == 7
      ])
    ])
    error_message = "Non-current object versions should expire after 7 days."
  }

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.canary_bucket.rule :
      anytrue([
        for abort in rule.abort_incomplete_multipart_upload :
        abort.days_after_initiation == 7
      ])
    ])
    error_message = "Incomplete multipart uploads should be aborted after 7 days."
  }
}

run "iam_and_canary_config" {
  command = plan

  assert {
    condition = (
      strcontains(aws_iam_role.canary_role.assume_role_policy, "lambda.amazonaws.com") &&
      strcontains(aws_iam_role.canary_role.assume_role_policy, "synthetics.amazonaws.com")
    )
    error_message = "Canary role trust policy must allow Lambda and Synthetics."
  }

  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.schedule[0].expression == "rate(15 minutes)"
    error_message = "Canary schedule must run every 15 minutes."
  }

  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.handler == "connectivity_check.handler"
    error_message = "Unexpected canary handler."
  }

  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables["CONNECT_TIMEOUT_MS"] == "3000"
    error_message = "Canary connect timeout must be 3000ms."
  }

  assert {
    condition = contains(
      keys(aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables),
      "DEST_IP"
    )
    error_message = "DEST_IP is missing from environment_variables."
  }

  assert {
    condition = lookup(
      aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables,
      "DEST_IP",
      "10.0.1.10,10.0.1.11"
    ) == "10.0.1.10,10.0.1.11"
    error_message = "DEST_IP env var not rendered correctly."
  }
  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables["ALLOW_PORTS"] == "443,8443"
    error_message = "Allowed ports env var not rendered correctly."
  }

  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables["DENY_PORTS"] == "25,3306"
    error_message = "Denied ports env var not rendered correctly."
  }

  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables["ALERT_ON_OPEN_PORTS"] == "false"
    error_message = "Alert on open ports env var must be rendered as a string boolean."
  }
}

run "alerts_and_slack_forwarder_config" {
  command = plan

  assert {
    condition     = aws_sns_topic.canary_alerts.name == "dev-canary-alerts"
    error_message = "SNS topic name should include environment prefix."
  }

  assert {
    condition     = aws_sqs_queue.slack_forwarder_dlq.message_retention_seconds == 1209600
    error_message = "Slack forwarder DLQ retention must be 14 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.slack_forwarder.retention_in_days == 365
    error_message = "Slack forwarder log group retention must be 365 days."
  }

  assert {
    condition     = aws_lambda_function.slack_forwarder.handler == "slack_forwarder.lambda_handler"
    error_message = "Slack forwarder handler is incorrect."
  }

  assert {
    condition     = aws_lambda_function.slack_forwarder.runtime == "python3.11"
    error_message = "Slack forwarder runtime must be python3.11."
  }

  assert {
    condition     = aws_lambda_function.slack_forwarder.timeout == 10
    error_message = "Slack forwarder timeout must be 10 seconds."
  }

  assert {
    condition     = aws_lambda_function.slack_forwarder.memory_size == 128
    error_message = "Slack forwarder memory size must be 128 MB."
  }

  assert {
    condition     = aws_lambda_function.slack_forwarder.reserved_concurrent_executions == 2
    error_message = "Slack forwarder reserved concurrency must be 2."
  }

  assert {
    condition = contains(
      keys(aws_lambda_function.slack_forwarder.environment[0].variables),
      "SLACK_WEBHOOK_URL"
    )
    error_message = "SLACK_WEBHOOK_URL should be set when slack_secret_arn is empty."
  }

  assert {
    condition = !contains(
      keys(aws_lambda_function.slack_forwarder.environment[0].variables),
      "SLACK_SECRET_ARN"
    )
    error_message = "SLACK_SECRET_ARN must not be set when slack_secret_arn is empty."
  }

  assert {
    condition     = aws_lambda_permission.allow_sns.principal == "sns.amazonaws.com"
    error_message = "Lambda invoke permission must be scoped to SNS principal."
  }

  assert {
    condition     = aws_lambda_permission.allow_sns.action == "lambda:InvokeFunction"
    error_message = "Lambda invoke permission action must be lambda:InvokeFunction."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.canary_failed.metric_name == "Failed"
    error_message = "Canary failure alarm must monitor Failed metric."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.canary_failed.comparison_operator == "GreaterThanThreshold"
    error_message = "Canary failure alarm comparison operator is incorrect."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.canary_failed.threshold == 0
    error_message = "Canary failure alarm threshold must be 0."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.canary_failed.treat_missing_data == "notBreaching"
    error_message = "Canary failure alarm should treat missing data as notBreaching."
  }
}
