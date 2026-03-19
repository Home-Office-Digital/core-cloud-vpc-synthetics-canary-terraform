variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}
variable "bucket_name" {
  description = "Name of the S3 bucket for Canary artifacts"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for naming resources"
  type        = string
}

variable "environment" {
  description = "Environment tag"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the Canary will run"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Canary"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the Canary"
  type        = list(string)
}

variable "target_ips" {
  description = "Comma-separated list of target IPs"
  type        = list(string)

  validation {
    condition     = length(var.target_ips) > 0
    error_message = "target_ips must contain at least one IP address."
  }
}

variable "allowed_ports" {
  description = "Comma-separated list of allowed ports"
  type        = list(string)
}

variable "denied_ports" {
  description = "Comma-separated list of denied ports"
  type        = list(string)
}

variable "start_scan" {
  description = "port numbers to start scanning from"
  type        = number

  validation {
    condition     = var.start_scan >= 1 && var.start_scan <= 65535
    error_message = "start_scan must be between 1 and 65535."
  }
}

variable "scan_end" {
  description = "port numbers to stop scanning"
  type        = number

  validation {
    condition     = var.scan_end >= 1 && var.scan_end <= 65535
    error_message = "scan_end must be between 1 and 65535."
  }
}

variable "alert_on_open_ports" {
  description = "alert_on_open_ports"
  type        = bool
}
variable "slack_webhook_url" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Slack webhook URL (use slack_secret_arn instead for production)"
}

variable "slack_secret_arn" {
  type        = string
  default     = ""
  description = "Secrets Manager ARN that stores Slack webhook"
}