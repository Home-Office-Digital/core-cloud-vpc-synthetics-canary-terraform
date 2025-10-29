VPC Connectivity Terraform Module
This Terraform module deploys EC2 instances in one or more destination VPCs and a CloudWatch Synthetics canary in a source VPC to test connectivity. It supports tagging for environment tracking and SNS notifications for canary failures.

🚀 Features

Deploys EC2 instances in multiple destination VPCs
Deploys a CloudWatch Synthetics canary in a source VPC
Canary tests connectivity to destination EC2 instances using private IPs
Supports allowed and denied port scanning
Tags all resources with environment metadata
Creates a CloudWatch alarm for canary failures
Sends notifications via SNS when failures occur


🔧 Inputs



















































































NameDescriptionTypeRequiredsource_vpc_idVPC ID where the canary is deployedstring✅source_subnet_idSubnet ID in the source VPC for the canarystring✅destination_vpcsList of destination VPCs with subnet IDslist(object)✅ami_idAMI ID for EC2 instancesstring✅instance_typeEC2 instance typestring✅allowed_portsComma-separated list of allowed portsstring✅denied_portsComma-separated list of denied portsstring✅environmentEnvironment tag value (e.g., dev, prod)string✅sns_topic_arnARN of the SNS topic for alarm notificationsstring✅artifact_s3_locationS3 path for canary artifactsstring✅code_s3_bucketS3 bucket containing the canary script ZIPstring✅code_s3_keyS3 key for the canary script ZIPstring✅

📤 Outputs





















NameDescriptioncanary_nameName of the deployed canarycanary_role_arnARN of the IAM role used by the canarydestination_instance_idsList of EC2 instance IDs in destination VPCs