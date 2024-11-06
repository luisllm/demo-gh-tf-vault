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

resource "aws_subnet" "vault_subnet" {
  vpc_id                  = aws_vpc.vault_vpc.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-vault-subnet"
  }
}

resource "aws_route_table_association" "vault_rta" {
  subnet_id      = aws_subnet.vault_subnet.id
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

  ingress {
    from_port   = 22
    to_port     = 22
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

data "aws_iam_policy_document" "vault-kms-unseal" {
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
}

resource "aws_iam_role" "vault-kms-unseal-role" {
  name               = "${var.environment}-vault-kms-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "vault-kms-unseal-policy" {
  name   = "${var.environment}-vault-kms-policy"
  role   = aws_iam_role.vault-kms-unseal-role.id
  policy = data.aws_iam_policy_document.vault-kms-unseal.json
}

resource "aws_iam_instance_profile" "vault-kms-unseal" {
  name = "${var.environment}-vault-kms-unseal-instance-profile"
  role = aws_iam_role.vault-kms-unseal-role.name
}

data "template_file" "vault" {
  template = file("userdata.tftpl")

  vars = {
    kms_key    = aws_kms_key.vault.id
    aws_region = var.region
  }
}

resource "aws_instance" "vault_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.vault_subnet.id
  vpc_security_group_ids = [aws_security_group.vault_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vault-kms-unseal.id
  #user_data              = file("userdata.tftpl")
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

