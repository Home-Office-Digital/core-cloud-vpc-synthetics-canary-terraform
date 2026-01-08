terraform {
  backend "s3" {}
}

locals {
  tags = {
    Environment = var.environment
    CostCentre  = "canary-testing"
    Owner       = "networktest"
    Application = "canary"
  }
}
resource "aws_s3_bucket" "canary_bucket" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = local.tags
}
resource "aws_s3_bucket_public_access_block" "canary_bucket_block" {
  bucket = aws_s3_bucket.canary_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_kms_key" "canary_bucket_cmk" {
  description             = "CMK for S3 canary bucket (${var.environment})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "canary_bucket_cmk_alias" {
  name          = "alias/${var.environment}-canary-bucket"
  target_key_id = aws_kms_key.canary_bucket_cmk.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "canary_bucket_encryption" {
  bucket = aws_s3_bucket.canary_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.canary_bucket_cmk.arn
    }
  }
}
resource "aws_s3_bucket_versioning" "canary_bucket" {
  bucket = aws_s3_bucket.canary_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "canary_bucket" {
  bucket = aws_s3_bucket.canary_bucket.id

  rule {
    id     = "expire-canary-artifacts"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_iam_role" "canary_role" {
  name = "${var.environment}-canary-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = [
          "lambda.amazonaws.com",
          "synthetics.amazonaws.com"
        ]
      },
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "canary_policy" {
  role       = aws_iam_role.canary_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchSyntheticsFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.canary_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "canary_vpc_policy" {
  name = "${var.environment}-canary-vpc-policy"
  role = aws_iam_role.canary_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "canary_s3_access" {
  name = "${var.environment}-canary-s3-access"
  role = aws_iam_role.canary_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.canary_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.canary_bucket.bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_object" "canary_script" {
  bucket = aws_s3_bucket.canary_bucket.bucket
  key    = "connectivity_check.js.zip"
  source = "${path.module}/connectivity_check.js.zip"
  etag   = filemd5("${path.module}/connectivity_check.js.zip")
  tags   = local.tags
}

resource "aws_synthetics_canary" "vpc_connectivity" {
  name                 = "${lower(var.environment)}-vpc-connectivity"
  artifact_s3_location = "s3://${aws_s3_bucket.canary_bucket.bucket}/"
  execution_role_arn   = aws_iam_role.canary_role.arn
  runtime_version      = "syn-nodejs-puppeteer-12.0"
  start_canary         = true
  handler              = "connectivity_check.handler"
  s3_bucket            = aws_s3_bucket.canary_bucket.bucket
  s3_key               = aws_s3_object.canary_script.key

  schedule {
    expression = "rate(15 minutes)"
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  run_config {
    environment_variables = {

      DEST_IP             = join(",", var.target_ips)
      ALLOW_PORTS         = join(",", var.allowed_ports)
      DENY_PORTS          = join(",", var.denied_ports)
      SCAN_START          = var.start_scan
      SCAN_END            = var.scan_end
      ALERT_ON_OPEN_PORTS = var.alert_on_open_ports
      CONNECT_TIMEOUT_MS  = "3000"
    }
  }

  tags = local.tags
}
