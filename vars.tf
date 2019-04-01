variable "velocloud_port" {
  description = "The port the edge will use"
  default = 2426
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_cidr" {
  default = "10.0.0.0/24"
}

variable "priv1_cidr" {
  default = "10.0.100.0/24"
}

variable "priv2_cidr" {
  default = "10.0.200.0/24"
}