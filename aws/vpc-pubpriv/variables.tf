variable "environment" {
  description = "The Deployment environment"
  type = string
  default = "dev"
}

variable "vpc_cidr" {
  description = "The CIDR block of the vpc"
  type = string
  default = "10.0.0.0/16"
}

variable "public_subnets_cidr" {
  type = list
  description = "The CIDR block for the public subnet"
  default = ["10.0.0.0/24"] 
}

variable "private_subnets_cidr" {
  type        = list
  description = "The CIDR block for the private subnet"
  default = ["10.0.10.0/24"]
}

variable "region" {
  type = string
  description = "The region to launch the bastion host"
  default = "us-east-1"
}

variable "availability_zones" {
  type  = list
  description = "The az that the resources will be launched"
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
