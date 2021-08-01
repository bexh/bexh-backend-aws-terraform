variable "whitelisted_ips" {
  type = list(string)
}

variable "env_name" {
  type = string
}

variable "log_level" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "bexh_api_lambda_s3_version" {
  type = string
}

variable "es_domain" {
  type        = string
  description = "ElasticSearch domain name"
}

variable "es_subnets" {
  type        = list(string)
  description = "List of VPC Subnet IDs to create ElasticSearch Endpoints in"
}

variable "vpc" {
  type        = string
  description = "VPC ID where to launch ElasticSearch cluster"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR to allow connections to ElasticSearch"
}

variable "bexh_email_lambda_s3_version" {
  type = string
}

variable "twilio_api_key" {
  type = string
}

variable "base_url" {
  type        = string
  description = "Base url where website is hosted given the env"
}

variable "bexh_email" {
  type        = string
  description = "Sender email address for mailer lambda"
}

variable "bexh_bet_submit_lambda_s3_version" {
  type = string
}

variable "connector_image_tag" {
  type        = string
  description = "tag of bexh connector from ecr image"
}

variable "connector_instance_count" {
  type        = number
  description = "number of ecs instances"
}

variable "bets_kinesis_stream_arn" {
  type        = string
  description = "arn of the kinesis stream of all outgoing bets"
}
