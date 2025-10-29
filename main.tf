provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "canary_bucket" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name        = "CanaryBucket"
    Environment = var.environment
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
          "ec2:DeleteNetworkInterface"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_object" "canary_script" {
  bucket = aws_s3_bucket.canary_bucket.bucket
  key    = "scripts/connectivity_check.py.zip"
  source = "${path.module}/scripts/connectivity_check.py.zip"
  etag   = filemd5("${path.module}/scripts/connectivity_check.py.zip")
}

resource "aws_synthetics_canary" "vpc_connectivity" {
  name                 = "${lower(var.environment)}-vpc-connectivity"
  artifact_s3_location = "s3://${aws_s3_bucket.canary_bucket.bucket}/"
  execution_role_arn   = aws_iam_role.canary_role.arn
  runtime_version      = "syn-python-selenium-7.0"
  start_canary         = true
  handler              = "canary_script.handler"
  s3_bucket            = aws_s3_bucket.canary_bucket.bucket
  s3_key               = aws_s3_object.canary_script.key

  schedule {
    expression = "rate(5 minutes)"
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  run_config {
    environment_variables = {

      TARGET_IPS    = join(",", var.target_ips)
      ALLOWED_PORTS = join(",", var.allowed_ports)
      DENIED_PORTS  = join(",", var.denied_ports)

    }
  }

  tags = {
    Name        = "VPCConnectivityCanary"
    Environment = var.environment
  }
}
