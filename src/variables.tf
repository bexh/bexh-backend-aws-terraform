variable "whitelisted_ips" {
  type    = list(string)
  default = ["107.5.201.132/32", "70.88.232.46/32", "97.70.144.117/32", "68.56.130.250/32"]
}

variable "bexh_api_lambda_s3_version" {
  type    = string
}

variable "bexh_email_lambda_s3_version" {
  type = string
}

variable "bexh_bet_submit_lambda_s3_version" {
  type = string
  default = ""
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
}

variable "es_subnets" {
  type        = list(string)
  description = "List of VPC Subnet IDs to create ElasticSearch Endpoints in"
  default     = ["subnet-52377c0e"]
}

variable "kibana_access" {
  type        = bool
  description = "Enables kibana on ES"
  default     = true
}

variable "twilio_api_key" {
  type = string
}

variable "base_url" {
  type = string
  description = "Base url where website is hosted given the env"
  default = "localhost:3000"
}

variable "bexh_email" {
  type = string
  description = "Sender email address for mailer lambda"
  default = "bexh.dev@gmail.com"
}
