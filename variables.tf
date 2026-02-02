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
}

variable "slack_secret_arn" {
  type        = string
  default     = ""
  description = "Secrets Manager ARN that stores Slack webhook"
}

# EC2 Instance 

variable "dest_vpc_id" {
  description = "VPC ID to create the EC2 instance "
  type        = string
}

variable "dest_subnet_id" {
  description = "Existing Subnet ID to create the EC2 instance"
  type        = string
}

variable "allowed_https_cidr" {
  description = "CIDR allowed to access HTTPS (443)"
  type        = list(string)
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}