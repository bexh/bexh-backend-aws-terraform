variable "region" {
    type = string
}

variable "env_name" {
  type    = string
}

variable "log_level" {
  type    = string
}

variable "account_id" {
    type = string
}

variable "vpc" {
  type        = string
  description = "VPC ID where to launch ElasticSearch cluster"
}

variable "es_subnets" {
  type        = list(string)
  description = "List of VPC Subnet IDs to create ElasticSearch Endpoints in"
}

variable "event_connector_image_tag" {
  type = string
  description = "tag of bexh event connector from ecr image"
}

variable "trade_executor_image_tag" {
  type = string
  description = "tag of bexh trade executor from ecr image"
}
