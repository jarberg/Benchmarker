variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "benchmarker"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.30.101.0/24", "10.30.102.0/24", "10.30.103.0/24"]
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "db_username" {
  type    = string
  default = "benchmarker"
}

variable "db_name" {
  type    = string
  default = "benchmarker"
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "benchmarker"
    ManagedBy = "terraform"
  }
}
