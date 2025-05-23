variable "region" {
  description = "AWS region"
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.10.2.0/24", "10.10.4.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "jenkins_ami" {
  description = "AMI ID for Jenkins master and slave"
  default     = "ami-0af9569868786b23a"
}

variable "jenkins_master_instance_type" {
  default = "t3.medium"
}

variable "jenkins_slave_instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  description = "SSH key name for EC2 instances"
  default     = "mumbaipemkey"
}

variable "jenkins_slave_count" {
  default = 1
}

variable "jump_server_ami" {
  description = "AMI ID for the Jump Server"
  type        = string
  default     = "ami-0af9569868786b23a"
}

variable "jump_server_instance_type" {
  description = "Instance type for Jump Server"
  type        = string
  default     = "t3.micro"
}

variable "gitlab_ami" {
  description = "AMI ID for the Jump Server"
  type        = string
  default     = "ami-0af9569868786b23a"
}

variable "gitlab_instance_type" {
  description = "Instance type for Jump Server"
  type        = string
  default     = "t3.large"
}
