VPC Connectivity Terraform Module
This Terraform module deploys CloudWatch Synthetics canary in a source VPC to test connectivity.

🚀 Features

- Deploys a CloudWatch Synthetics canary in a source VPC
- Canary tests connectivity to destination EC2 instances using private IPs
- Supports allowed and denied port scanning

### Prerequisites
Before using this module, ensure you have the following:

- AWS credentials configured.
- Terraform installed.
- A working knowledge of Terraform.

## Getting Started

1. **Define the Module**

Initially, it's essential to define a Terraform module, which is organized as a distinct directory encompassing Terraform configuration files. Within this module directory, input variables and output values must be defined in the variables.tf and outputs.tf files, respectively. The following illustrates an example directory structure:


```plaintext
synthetics/
|-- main.tf
|-- variables.tf
|-- outputs.tf
```


2. **Define Input Variables**

Inside the `variables.tf` or in `*.tfvars` file, you should define values for the variables that the module requires.

3. **Use the Module in Your Main Configuration**
In your main Terraform configuration file (e.g., main.tf), you can use the module. Specify the source of the module, and version, For Example

```hcl
module "synthetic-monitoring" {
  source            = "sourcefuse/arc-synthetic-monitoring/aws"
  version           = "0.0.1"
  sns_topic_name    = var.sns_topic_name
  endpoint          = var.endpoint
  kms_key_alias     = var.kms_key_alias
  canaries_with_vpc = local.canaries_with_vpc
  bucket_name       = var.bucket_name
  tags              = module.tags.tags
}
```

4. **Output Values**

Inside the `outputs.tf` file of the module, you can define output values that can be referenced in the main configuration. For example:

```hcl
output "canary_role_arn" {
  value = aws_iam_role.canary_role.arn
}
```

## Usage

```hcl
module "vpc_connectivity_canary" {
  source = "./modules/canary"

  region            = "eu-west-2"
  bucket_name       = "vpc-connectivity-canary-bucket"
  environment       = "dev"
  subnet_ids        = ["subnet-0123456789abcdef0"]
  security_group_ids = ["sg-0123456789abcdef0"]

  target_ips        = ["10.0.1.10", "10.0.2.20"]
  allowed_ports     = ["443", "80"]
  denied_ports      = ["22", "3306"]
}
```