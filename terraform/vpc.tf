# =============================================================================
# vpc.tf — VPC, subnets, Internet Gateway, NAT Gateway, route tables
#
# Layout
# ──────
# VPC  10.0.0.0/16
# ├── Public subnet A  (us-east-1a)  10.0.1.0/24   ← ALB, NAT GW
# ├── Public subnet B  (us-east-1b)  10.0.2.0/24   ← ALB (second AZ)
# ├── Private subnet A (us-east-1a)  10.0.11.0/24  ← ECS tasks
# └── Private subnet B (us-east-1b)  10.0.12.0/24  ← ECS tasks
#
# Traffic flow (inbound)
#   Internet → IGW → ALB (public subnets) → ECS tasks (private subnets)
#
# Traffic flow (outbound from tasks)
#   ECS tasks → NAT GW (public subnet) → IGW → Internet
#   (needed for DockerHub image pulls and AWS API calls)
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true  # required for ECS service discovery & ECR pulls
  enable_dns_hostnames = true  # required for ECS exec and SSM endpoints

  tags = { Name = "${local.name_prefix}-vpc" }
}

# -----------------------------------------------------------------------------
# Internet Gateway — attached to the VPC; gives public subnets internet access
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# -----------------------------------------------------------------------------
# Public subnets — one per AZ
# Resources here have a public IP and a route to the IGW.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true # ALB ENIs need public IPs

  tags = { Name = "${local.name_prefix}-public-${local.azs[count.index]}" }
}

# Route table for public subnets — default route via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# NAT Gateway — deployed in the FIRST public subnet only.
# Cost note: a single NAT GW saves money in dev/staging.
# For production with strict HA requirements, deploy one per AZ:
#   count = length(local.azs)
# and reference aws_subnet.public[count.index].id below.
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip" }

  # EIP must be created after the IGW exists
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # first public subnet

  tags       = { Name = "${local.name_prefix}-nat-gw" }
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Private subnets — one per AZ
# No inbound internet access. Outbound goes via NAT GW.
# ECS Fargate tasks run here.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # tasks must NOT have public IPs

  tags = { Name = "${local.name_prefix}-private-${local.azs[count.index]}" }
}

# Route table for private subnets — default route via NAT GW
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt-private" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
