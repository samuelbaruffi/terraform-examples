locals {
  instance-userdata-webserver = <<EOF
 #!/bin/bash
yum -y update

# install nginx
amazon-linux-extras install nginx1 -y

# start server
service nginx start       
EOF
 
 instance-userdata-database = <<EOF
#!/bin/bash

# Update all packages
yum -y update

# Install mysql client 
yum -y install mysql       
EOF
}


/*====
The VPC
======*/

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "vpc-${var.environment}"
    Environment = "${var.environment}"
  }
}

/*====
Subnets
======*/
/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name        = "${var.environment}-igw"
    Environment = "${var.environment}"
  }
}

/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.ig]
}

/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${element(aws_subnet.public_subnet.*.id, 0)}"
  depends_on    = [aws_internet_gateway.ig]

  tags = {
    Name        = "nat"
    Environment = "${var.environment}"
  }
}

/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  count                   = "${length(var.public_subnets_cidr)}"
  cidr_block              = "${element(var.public_subnets_cidr, count.index)}"
  availability_zone       = "${element(var.availability_zones, count.index)}"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-public-subnet"
    Environment = "${var.environment}"
  }
}

/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  count                   = "${length(var.private_subnets_cidr)}"
  cidr_block              = "${element(var.private_subnets_cidr, count.index)}"
  availability_zone       = "${element(var.availability_zones, count.index)}"
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-private-subnet"
    Environment = "${var.environment}"
  }
}

/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}

/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.nat.id}"
}

/* Route table associations */
resource "aws_route_table_association" "public" {
  count          = "${length(var.public_subnets_cidr)}"
  subnet_id      = "${element(aws_subnet.public_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private" {
  count          = "${length(var.private_subnets_cidr)}"
  subnet_id      = "${element(aws_subnet.private_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.private.id}"
}

/*====
VPCs Default Security Group
======*/
resource "aws_security_group" "default" {
  name        = "${var.environment}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = "${aws_vpc.vpc.id}"
  depends_on  = [aws_vpc.vpc]

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "${var.environment}"
  }
}

resource "aws_security_group_rule" "allowport80" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.default.id}"
}

resource "aws_security_group" "database" {
  name        = "${var.environment}-database-sg"
  description = "Database security group to allow inbound traffic on port 3306 MySQL"
  vpc_id      = "${aws_vpc.vpc.id}"
  depends_on  = [aws_vpc.vpc]

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "${var.environment}"
  }
}

resource "aws_security_group_rule" "allowport3306" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  source_security_group_id = "${aws_security_group.default.id}"
  security_group_id = "${aws_security_group.database.id}"
}

/*====
IAM Role for EC2
======*/
resource "aws_iam_role" "ssmcore_role" {
  name = "ssmcore_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "tag-value"
  }
}

resource "aws_iam_role_policy_attachment" "ssmcore_managed" {
  role       = aws_iam_role.ssmcore_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssmcore_instanceprofile" {
  name = "ssmcore_instanceprofile"
  role = "${aws_iam_role.ssmcore_role.name}"
}


/*====
EC2 Instances
======*/
resource "aws_instance" "database_private" {
  ami           = "ami-038f1ca1bd58a5790"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.database.id]
  subnet_id = "${element(aws_subnet.private_subnet.*.id, 1)}"
  associate_public_ip_address = "false"
  iam_instance_profile = "${aws_iam_instance_profile.ssmcore_instanceprofile.name}"
  user_data_base64 = "${base64encode(local.instance-userdata-database)}"

  tags = {
    Name = "Terraform-Database1_Private"
  }
}

resource "aws_instance" "webserver_public" {
  ami           = "ami-038f1ca1bd58a5790"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.default.id]
  subnet_id = "${element(aws_subnet.public_subnet.*.id, 1)}"
  associate_public_ip_address = "true"
  iam_instance_profile = "${aws_iam_instance_profile.ssmcore_instanceprofile.name}"
  user_data_base64 = "${base64encode(local.instance-userdata-webserver)}"

  tags = {
    Name = "Terraform-WebServer1_Public"
  }
}

