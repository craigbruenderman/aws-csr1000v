
# Credentials from ~/.aws/credentials
provider "aws" {
  profile = "cbts"
  region = "us-east-1"
}

data "aws_availability_zones" "all" {}

# Create Transit VPC
resource "aws_vpc" "transit_vpc" {
  cidr_block = "${var.vpc_cidr_block}"
  tags = {
    Name = "Craig's Transit VPC"
  }
}
output "transit_vpc_id" {
  value = "${aws_vpc.transit_vpc.id}"
}

# Add Virtual Private Gateway
resource "aws_vpn_gateway" "vpn_gw" {
  vpc_id = "${aws_vpc.transit_vpc.id}"
  tags = {
    Name = "Transit VPC Private Gateway"
  }
}

# Add Internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.transit_vpc.id}"
  tags = {
    Name = "IGW for Craig's Transit VPC"
  }
}

resource "aws_default_route_table" "pub_rt" {
  default_route_table_id = "${aws_vpc.transit_vpc.default_route_table_id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }
  tags = {
    Name = "Craig's Transit VPC Public Table"
  }
}

# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = "${aws_vpc.transit_vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block = "${var.public_cidr}"
  tags = {
    Name = "Craig's Transit VPC Public Subnet"
  }
}

# Associate public subnet with its route table
resource "aws_route_table_association" "pub_sub_ass" {
  subnet_id      = "${aws_subnet.public_subnet.id}"
  route_table_id = "${aws_default_route_table.pub_rt.id}"
}
 
# Create private route table 1
resource "aws_route_table" "priv_rt1" {
  vpc_id = "${aws_vpc.transit_vpc.id}"
    tags = {
    Name = "Velocloud Private RT 1 - Management Facing"
  }
}

# And private subnet 1
resource "aws_subnet" "priv1_subnet" {
  vpc_id     = "${aws_vpc.transit_vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block = "${var.priv1_cidr}"
  tags = {
    Name = "Velocloud Private Subnet 1"
  }
}

# Associate private_subnet subnet with its route table
resource "aws_route_table_association" "priv1_sub_ass" {
  subnet_id      = "${aws_subnet.priv1_subnet.id}"
  route_table_id = "${aws_route_table.priv_rt1.id}"
}


# Create private route table 2
resource "aws_route_table" "priv_rt2" {
  vpc_id = "${aws_vpc.transit_vpc.id}"
  depends_on = ["aws_network_interface.vce_lan"]
  route {
    cidr_block = "0.0.0.0/0"
    network_interface_id = "${aws_network_interface.vce_lan.id}"
  }
  tags = {
    Name = "Velocloud Private RT 2 - LAN Facing"
  }
}

# And private subnet 2
resource "aws_subnet" "priv2_subnet" {
  vpc_id     = "${aws_vpc.transit_vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block = "${var.priv2_cidr}"
  tags = {
    Name = "Velocloud Private Subnet 2"
  }
}


# Associate private_subnet subnet with its route table
resource "aws_route_table_association" "priv2_sub_ass" {
  subnet_id      = "${aws_subnet.priv2_subnet.id}"
  route_table_id = "${aws_route_table.priv_rt2.id}"
}


# Create security group
resource "aws_security_group" "allow_velocloud" {
  name        = "allow_velocloud"
  description = "Allow "
  vpc_id      = "${aws_vpc.transit_vpc.id}"

  ingress {
		from_port = "${var.velocloud_port}"
		to_port = "${var.velocloud_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
		from_port = "8"
		to_port = "0"
    protocol = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
		from_port = "22"
		to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
     create_before_destroy = true
   }
   tags = {
     Name = "allow_all"
   }
}


data "template_file" "cloud-config" {
  template = <<YAML
#cloud-config
runcmd:
  - ip route replace default via 10.50.0.1 dev eth1 metric 1
  - ip route del default dev eth0
  - ip route del default dev eth2
velocloud:
  vce:
    vco: "vco160-usca1.velocloud.net"
    activation_code: "${var.velocloud_activation_code}"
    vco_ignore_cert_errors: false
YAML
}

output "userdata" {
  value = "${data.template_file.cloud-config.rendered}"
}

# Deploy vedge
resource "aws_instance" "velocloud-edge" {
  ami             = "ami-da7a56cc"
  instance_type   = "m4.xlarge"
  key_name        = "Craig"
  vpc_security_group_ids = ["${aws_security_group.allow_velocloud.id}"]
  subnet_id       = "${aws_subnet.priv1_subnet.id}"
  source_dest_check = false
  user_data       = "${base64encode(data.template_file.cloud-config.rendered)}"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "Velocloud Virtual Edge"
  }
}

output "vce-eth0-private-ip" {
  value = "${aws_instance.velocloud-edge.private_ip}"
}


# Create an ENI for eth1 Velocloud transport interface
resource "aws_network_interface" "transport" {
  subnet_id       = "${aws_subnet.public_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false
  attachment {
    instance     = "${aws_instance.velocloud-edge.id}"
    device_index = 1
  }
  tags {
    Name = "Velocloud Transport Interface (GE2 / eth1)"
  }
}


#Create an ENI for Velocloud LAN interface
resource "aws_network_interface" "vce_lan" {
  subnet_id       = "${aws_subnet.priv2_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false
  attachment {
    instance     = "${aws_instance.velocloud-edge.id}"
    device_index = 2
  }
  tags {
    Name = "Velocloud LAN Interface (GE3 / eth2)"
  }
}


# Create EIP for Velocloud transport interface
resource "aws_eip" "transport" {
  vpc      = true
  network_interface = "${aws_network_interface.transport.id}"
  tags {
    Name = "Velocloud Transport Int GE3"
  }
}

# Let's have that public IP
output "vce_eip" {
  value = "${aws_eip.transport.public_ip}"
}

resource "aws_instance" "Linux-01" {
  ami             = "ami-02da3a138888ced85"
  instance_type   = "t1.micro"
  key_name        = "Craig"
  vpc_security_group_ids = ["${aws_security_group.allow_velocloud.id}"]
  subnet_id       = "${aws_subnet.priv2_subnet.id}"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "Velocloud Linux Test Workload"
  }
}

output "test-box-ip" {
  value = "${aws_instance.Linux-01.private_ip}"
}
