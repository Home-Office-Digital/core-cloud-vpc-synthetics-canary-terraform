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
  type        = string
}

variable "scan_end" {
  description = "port numbers to stop scanning"
  type        = string
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

  validation {
    condition     = var.slack_webhook_url == "" || can(regex("^https://", var.slack_webhook_url))
    error_message = "slack_webhook_url must be an https URL when provided."
  }
}

variable "slack_secret_arn" {
  type        = string
  default     = ""
  description = "Secrets Manager ARN that stores Slack webhook"

  validation {
    condition     = var.slack_secret_arn != "" || var.slack_webhook_url != ""
    error_message = "Set either slack_webhook_url or slack_secret_arn so Slack notifications can be sent."
  }
}