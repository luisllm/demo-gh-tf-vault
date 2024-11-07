data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_owner]
}

resource "aws_vpc" "vault_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.environment}-vault-vpc"
  }
}

resource "aws_internet_gateway" "vault_igw" {
  vpc_id = aws_vpc.vault_vpc.id

  tags = {
    Name = "${var.environment}-vault-igw"
  }
}

resource "aws_route_table" "vault_rt" {
  vpc_id = aws_vpc.vault_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vault_igw.id
  }

  tags = {
    Name = "${var.environment}-vault-rt"
  }
}

resource "aws_subnet" "vault_subnet_a" {
  vpc_id                  = aws_vpc.vault_vpc.id
  cidr_block              = var.subnet_a_cidr_block
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-vault-subnet-a"
  }
}

resource "aws_subnet" "vault_subnet_b" {
  vpc_id                  = aws_vpc.vault_vpc.id
  cidr_block              = var.subnet_b_cidr_block
  availability_zone       = "eu-west-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-vault-subnet-b"
  }
}

resource "aws_route_table_association" "vault_rta_a" {
  subnet_id      = aws_subnet.vault_subnet_a.id
  route_table_id = aws_route_table.vault_rt.id
}

resource "aws_route_table_association" "vault_rta_b" {
  subnet_id      = aws_subnet.vault_subnet_b.id
  route_table_id = aws_route_table.vault_rt.id
}

resource "aws_security_group" "vault_sg" {
  name        = "${var.environment}_vault_sg"
  description = "Allow port 8200"
  vpc_id      = aws_vpc.vault_vpc.id

  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  # SSH access for EC2 Instance Connect IP range in eu-west-1
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.202.216.48/29"] # EC2 Instance Connect IP range for eu-west-1
  }

  # Allow inbound access to Vault from the dummy security group
  ingress {
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    security_groups = [aws_security_group.dummy_ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-vault-sg"
  }
}

# Create an Elastic IP
resource "aws_eip" "vault_eip" {
  domain = "vpc"
}

# KMS Key that will be used to unseal Vault automatically
resource "aws_kms_key" "vault" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10

  tags = {
    Name = "${var.environment}-vault-kms-unseal"
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vault-policy" {
  statement {
    sid       = "VaultKMSUnseal"
    effect    = "Allow"
    resources = [aws_kms_key.vault.arn]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
  }

  # Permissions needed so that we can create ParameterStore params for Vault init and the root token
  # after initializating Vault
  statement {
    sid    = "ParameterStorePermissions"
    effect = "Allow"
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/vault/*"
    ]
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:DeleteParameter"
    ]
  }

  # Permissions needed to test Vault generating dynamic AWS credentials
  statement {
    sid       = "PermitAccessForAWSSecretsEngineAssumedRole"
    effect    = "Allow"
    resources = ["arn:aws:iam::632758144135:role/${var.environment}-vault-s3-access-role"]
    actions = [
      "sts:AssumeRole"
    ]
  }
}

resource "aws_iam_role" "vault-role" {
  name               = "${var.environment}-vault-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "vault-role-policy" {
  name   = "${var.environment}-vault-policy"
  role   = aws_iam_role.vault-role.id
  policy = data.aws_iam_policy_document.vault-policy.json
}

resource "aws_iam_instance_profile" "vault-instance-profile" {
  name = "${var.environment}-vault-instance-profile"
  role = aws_iam_role.vault-role.name
}

data "template_file" "vault" {
  template = file("vault_ec2_userdata.tftpl")

  vars = {
    kms_key     = aws_kms_key.vault.id
    aws_region  = var.region
    environment = var.environment
  }
}

resource "aws_instance" "vault_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.vault_subnet_a.id
  vpc_security_group_ids = [aws_security_group.vault_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vault-instance-profile.id
  user_data              = data.template_file.vault.rendered

  tags = {
    Name = "${var.environment}-vault"
  }
}

# Associate the Elastic IP with the vault server
# I created this EIP so that when I manually stop the EC2 for cost purposes, then the IP doesn't change
resource "aws_eip_association" "vault_eip_assoc" {
  instance_id   = aws_instance.vault_server.id
  allocation_id = aws_eip.vault_eip.id
}


#######################################################################
# IAM Role dummy for testing Vault dynamic AWS credentials generation #
#######################################################################

# IAM Role to Access S3
resource "aws_iam_role" "vault_s3_access_role" {
  name = "${var.environment}-vault-s3-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::632758144135:root"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-vault-s3-access-role"
  }
}

# Attach the AmazonS3FullAccess managed policy to the role
resource "aws_iam_role_policy_attachment" "vault_s3_access_policy" {
  role       = aws_iam_role.vault_s3_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}


#########################
# EC2 dummy for testing #
#########################
resource "aws_iam_role" "dummy_role" {
  name = "${var.environment}-dummy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-dummy-role"
  }
}

resource "aws_iam_instance_profile" "dummy_instance_profile" {
  name = "${var.environment}-dummy-instance-profile"
  role = aws_iam_role.dummy_role.name
}

resource "aws_security_group" "dummy_ec2_sg" {
  name        = "${var.environment}_dummy_ec2_sg"
  description = "Security group for dummy EC2 inqstance to allow SSH and Vault access"
  vpc_id      = aws_vpc.vault_vpc.id

  # SSH access for EC2 Instance Connect IP range in eu-west-1
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.202.216.48/29"] # EC2 Instance Connect IP range for eu-west-1
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-dummy-ec2-sg"
  }
}

data "template_file" "dummy" {
  template = file("dummy_ec2_userdata.tftpl")

  vars = {
    vault_server_private_ip = aws_instance.vault_server.private_ip
  }
}

resource "aws_instance" "vault_test_instance" {
  ami                    = data.aws_ami.ubuntu.id # Replace with your AMI data source
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.vault_subnet_a.id
  vpc_security_group_ids = [aws_security_group.dummy_ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.dummy_instance_profile.id
  user_data              = data.template_file.dummy.rendered

  tags = {
    Name = "${var.environment}-vault-test-instance"
  }
}
