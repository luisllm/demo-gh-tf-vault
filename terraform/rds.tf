# Security Group for RDS to allow access from the dummy EC2 instance
resource "aws_security_group" "rds_sg" {
  name        = "${var.environment}_rds_sg"
  description = "Security group for RDS MySQL instance to allow access from the dummy EC2"
  vpc_id      = aws_vpc.vault_vpc.id

  # Allow MySQL access from the dummy EC2 security group
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.dummy_ec2_sg.id]
  }

  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-rds-sg"
  }
}

# RDS Subnet Group with Multiple Subnets for AZ Coverage
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.environment}-rds-subnet-group"
  subnet_ids = [aws_subnet.vault_subnet_a.id, aws_subnet.vault_subnet_b.id]

  tags = {
    Name = "${var.environment}-rds-subnet-group"
  }
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier             = "${var.environment}-mysql-db"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "mysql"
  engine_version         = "8.0"
  username               = "admin"
  password               = "admin123"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  multi_az               = false # Ensures single-AZ deployment

  tags = {
    Name = "${var.environment}-mysql-db"
  }
}
