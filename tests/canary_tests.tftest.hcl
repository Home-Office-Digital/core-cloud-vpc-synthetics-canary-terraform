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
  start_scan          = "1"
  scan_end            = "500"
  alert_on_open_ports = "false"
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
    condition     = aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables["ALLOW_PORTS"] == "443,8443"
    error_message = "Allowed ports env var not rendered correctly."
  }

  assert {
    condition     = aws_synthetics_canary.vpc_connectivity.run_config[0].environment_variables["DENY_PORTS"] == "25,3306"
    error_message = "Denied ports env var not rendered correctly."
  }
}