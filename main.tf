# Create VPC

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.environment}-vpc"
  }
}

# Create subnet
resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-subnet"
  }
}

# Create IGW
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.environment}-internet-gateway"
  }
}

# Create route table attached to VPC and IGW
resource "aws_default_route_table" "default_route" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

# Create Role IAM llamado demo-ec2-iam-role
resource "aws_iam_role" "ec2_iam_role" {
  name               = "${var.environment}-ec2-iam-role"
  assume_role_policy = var.ec2-trust-policy
}

# Create Role IAM EC2, it looks like duplicated from my side
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2_iam_role.id
}

# Create Role policy to assume s3 actions like listobjects, getobjects within buckets s3
resource "aws_iam_role_policy" "ec2_role_policy" {
  name   = "${var.environment}-ec2-role-policy"
  role   = aws_iam_role.ec2_iam_role.id
  policy = var.ec2-s3-permissions
}

# Create bucket s3 called terraform1demo1s3bucket2023
resource "aws_s3_bucket" "s3" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name = "${var.environment}-s3-bucket"
  }
}

# Obtain User's Local Public IP launching command "curl -s http"....
data "external" "myipaddr" {
  program = ["bash", "-c", "curl -s 'https://ipinfo.io/json'"]
}

# Create EC2 Security Group and Security Rules
resource "aws_security_group" "jenkins_security_group" {
  name        = "${var.environment}-jenkins-security-group"
  description = "Apply to Jenkins EC2 instance"
  vpc_id      = aws_vpc.vpc.id

  #This part of code allows only to my ip access through ssh to the ec2-jenkins
  ingress {
    description = "Allow SSH from MY Public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.external.myipaddr.result.ip}/32"]
  }

  #This part of code allows only to my ip access all http traffic to the ec2-jenkins to consume web request
  ingress {
    description = "Allow access to Jenkis from My IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${data.external.myipaddr.result.ip}/32"]
  }
    #All traffic from EC2 is gonna be out and all internet to consume other servers and endpoints
  egress {
    description = "Allow All Outbound"
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-jenkins-security-group"
  }
}


# Create linux image latest
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
}

# Create SSH Key for EC2 connection
resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

# Create local file generic and later I map with ssh key generated previously
resource "local_file" "private_key_pem" {
  content         = tls_private_key.generated.private_key_pem
  filename        = "${var.ssh_key}.pem"
  file_permission = "0400"
}

# It's generating 2 private and public keys  
resource "aws_key_pair" "generated" {
  key_name   = var.ssh_key
  public_key = tls_private_key.generated.public_key_openssh  // right here it's only calling public part of all ssh key. The private no
}

# Create EC2 Instance
resource "aws_instance" "jenkins_server" {
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.generated.key_name
  subnet_id            = aws_subnet.subnet.id
  security_groups      = [aws_security_group.jenkins_security_group.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.id
  user_data            = var.ec2_user_data
  connection {
    user        = "ec2-user"
    private_key = tls_private_key.generated.private_key_pem
    host        = self.public_ip
  }

  tags = {
    Name = "${var.environment}-jenkins-server"
  }
}