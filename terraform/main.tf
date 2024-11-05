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

resource "aws_vpc" "gitops_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.environment}-gitops-vpc"
  }
}

resource "aws_internet_gateway" "gitops_igw" {
  vpc_id = aws_vpc.gitops_vpc.id

  tags = {
    Name = "${var.environment}-gitops-igw"
  }
}

resource "aws_route_table" "gitops_rt" {
  vpc_id = aws_vpc.gitops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gitops_igw.id
  }

  tags = {
    Name = "${var.environment}-gitops-rt"
  }
}

resource "aws_subnet" "gitops_subnet" {
  vpc_id                  = aws_vpc.gitops_vpc.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-gitops-subnet"
  }
}

resource "aws_route_table_association" "gitops_rta" {
  subnet_id      = aws_subnet.gitops_subnet.id
  route_table_id = aws_route_table.gitops_rt.id
}

resource "aws_security_group" "gitops_sg" {
  name        = "${var.environment}_gitops_sg"
  description = "Allow port 3000"
  vpc_id      = aws_vpc.gitops_vpc.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-gitops-sg"
  }
}

# Create an Elastic IP
resource "aws_eip" "grafana_eip" {
  domain = "vpc"
}

resource "aws_instance" "grafana_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.gitops_subnet.id
  vpc_security_group_ids = [aws_security_group.gitops_sg.id]
  user_data              = file("userdata.tftpl")

  tags = {
    Name = "${var.environment}-grafana-server"
  }
}

# Associate the Elastic IP with the Grafana server
# I created this EIP so that when I manually stop the EC2 for cost purposes, then the IP doesn't change
resource "aws_eip_association" "grafana_eip_assoc" {
  instance_id   = aws_instance.grafana_server.id
  allocation_id = aws_eip.grafana_eip.id
}

# For the Grafana health check I used a scheduled GHA instead of implementing it with TF
# check "grafana_health_check" {
#   data "http" "test" {
#     url = "http://${aws_instance.grafana_server.public_ip}:3000"
#     retry {
#       attempts = 5
#     }
#   }
#   assert {
#     condition     = data.http.test.status_code == 200
#     error_message = "Grafana is inaccessible on port 3000."
#   }
# }