variable "region" {
  type = string
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

variable "vpc" {
  type        = string
  description = "VPC ID where to launch ElasticSearch cluster"
}

variable "whitelisted_ips" {
  type        = list(string)
  description = "whitelisted ips"
}

variable "es_subnets" {
  type        = list(string)
  description = "List of VPC Subnet IDs to create ElasticSearch Endpoints in"
}

variable "event_connector_image_tag" {
  type        = string
  description = "tag of bexh event connector from ecr image"
}

variable "trade_executor_image_tag" {
  type        = string
  description = "tag of bexh trade executor from ecr image"
}

variable "event_connector_instance_count" {
  type        = number
  description = "number of ecs instances"
}

variable "trade_executor_instance_count" {
  type        = number
  description = "number of ecs instances"
}

variable "incoming_bets_shard_count" {
  type        = number
  description = "number of shards for bets coming into the exchange"
}

variable "outgoing_events_shard_count" {
  type        = number
  description = "number of shards of shards for events going out of the exchange"
}

variable "outgoing_bets_shard_count" {
  type        = number
  description = "number of shards for bets going out of the exchange"
}
