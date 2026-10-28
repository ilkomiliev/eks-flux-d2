resource "aws_vpc" "eks" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "eks" {
  vpc_id = aws_vpc.eks.id

  tags = {
    Name = "${local.cluster_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks.id
  }

  tags = {
    Name = "${local.cluster_name}-public"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.eks.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.eks.cidr_block, 4, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${local.cluster_name}-public-${local.azs[count.index]}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.cluster_name}-alb"
  description = "Restrict the public ALB to the current workstation IP"
  vpc_id      = aws_vpc.eks.id

  ingress {
    description = "HTTP from workstation"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.client_cidr]
  }

  ingress {
    description = "HTTPS from workstation"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.client_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.cluster_name}-alb"
  }
}