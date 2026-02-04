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
  description = "Comma-separated list of target IPs/DNS (fallback when EC2 not created)"
  type        = string
  default     = ""
}

variable "allowed_ports" {
  description = "List of allowed ports"
  type        = list(number)
  default     = []
}

variable "denied_ports" {
  description = "List of denied ports"
  type        = list(number)
  default     = []
}

# Ports are numbers
variable "start_scan" {
  description = "Port to start scanning from"
  type        = number
  default     = 1
}

variable "scan_end" {
  description = "Port to stop scanning at"
  type        = number
  default     = 1024
}

variable "alert_on_open_ports" {
  description = "Fail canary if any unexpected open ports are found during scan"
  type        = bool
  default     = false
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