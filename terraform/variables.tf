variable "region" {
  description = "The AWS region where resources will be created."
  type        = string
  default     = "eu-west-1"
  validation {
    condition     = can(regex("^([a-z]{2}-[a-z]+-[0-9])$", var.region))
    error_message = "The region must follow the AWS format (e.g., us-west-1)."
  }
}

variable "instance_type" {
  description = "The EC2 instance type to use (e.g., t3.micro)."
  type        = string
  default     = "t3.micro"
  validation {
    condition     = contains(["t2.micro", "t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "The instance type must be one of the following: t2.micro, t3.micro, t3.small, or t3.medium."
  }
}

variable "environment" {
  description = "The environment being deployed. Possible options are 'production' and 'staging'"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging"], var.environment)
    error_message = "The environment should be 'production' or 'staging'"
  }
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrsubnet(var.vpc_cidr_block, 8, 0))
    error_message = "The VPC CIDR block must be a valid CIDR notation (e.g., 10.0.0.0/16)."
  }
}

variable "subnet_cidr_block" {
  description = "The CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  validation {
    condition     = can(cidrsubnet(var.subnet_cidr_block, 8, 0))
    error_message = "The subnet CIDR block must be a valid CIDR notation (e.g., 10.0.1.0/24)."
  }
}

variable "ami_name_filter" {
  description = "The filter for the AMI name"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "ami_owner" {
  description = "The owner ID for the AMI (Canonical for Ubuntu)"
  type        = string
  default     = "099720109477"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.ami_owner))
    error_message = "The AMI owner ID must be a 12-digit number (e.g., 099720109477)."
  }
}

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks that are allowed to access the security group on port 3000."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = alltrue([for cidr in var.ingress_cidr_blocks : can(cidrsubnet(cidr, 8, 0))])
    error_message = "Each value in ingress_cidr_blocks must be a valid CIDR notation (e.g., 0.0.0.0/0, 10.0.0.0/16)."
  }
}
