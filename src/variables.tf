variable "whitelisted_ips" {
  type    = list(string)
  default = ["107.5.201.132/32", "70.88.232.46/32", "97.70.144.117/32", "68.56.130.250/32"]
}

variable "bexh_api_lambda_s3_version" {
  type    = string
  default = "9jUol62fQdOvh3_aSJR.S1C1GVFj.hIc"
}

variable "env_name" {
  type    = string
  default = "dev"
}

variable "log_level" {
  type    = string
  default = "INFO"
}

variable "vpc" {
  type        = string
  description = "VPC ID where to launch ElasticSearch cluster"
  default     = "vpc-131c8769"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR to allow connections to ElasticSearch"
  default     = "172.31.0.0/16"
}

variable "region" {
  type        = string
  description = "AWS region to use"
  default     = "us-east-1"
}

variable "es_domain" {
  type        = string
  description = "ElasticSearch domain name"
  default     = "bexh-autocomplete-dev"
}

variable "es_subnets" {
  type        = list(string)
  description = "List of VPC Subnet IDs to create ElasticSearch Endpoints in"
  default     = ["subnet-52377c0e"]
}
