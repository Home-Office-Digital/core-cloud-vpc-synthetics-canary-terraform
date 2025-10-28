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
  type        = string
}

variable "allowed_ports" {
  description = "Comma-separated list of allowed ports"
  type        = string
}

variable "denied_ports" {
  description = "Comma-separated list of denied ports"
  type        = string
}
