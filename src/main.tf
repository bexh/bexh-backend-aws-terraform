terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "bexh"

    workspaces {
      name = "bexh-backend-aws-terraform"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

module "bexh_app" {
  source = "./modules/bexh_app"

  region = data.aws_region.current.name
  whitelisted_ips = var.whitelisted_ips
  env_name = var.env_name
  log_level = var.log_level
  account_id = data.aws_caller_identity.current.account_id
  bexh_api_lambda_s3_version = var.bexh_api_lambda_s3_version
  es_domain = var.es_domain
  es_subnets = var.es_subnets
  vpc = var.vpc
  vpc_cidr = var.vpc_cidr
  bexh_email_lambda_s3_version = var.bexh_email_lambda_s3_version
  twilio_api_key = var.twilio_api_key
  base_url = var.base_url
  bexh_email = var.bexh_email
  bexh_bet_submit_lambda_s3_version = var.bexh_bet_submit_lambda_s3_version
  connector_image_tag = var.connector_image_tag
  connector_instance_count = var.connector_instance_count

  bets_kinesis_stream_arn = module.bexh_exchange.outgoing_bets.arn
  events_kinesis_stream_arn = module.bexh_exchange.outgoing_events.arn
  make_bets_kinesis_stream_name = module.bexh_exchange.incoming_bets.name
}

module "bexh_exchange" {
  source = "./modules/bexh_exchange"

  region = data.aws_region.current.name
  whitelisted_ips = var.whitelisted_ips
  env_name = var.env_name
  log_level = var.log_level
  account_id = data.aws_caller_identity.current.account_id
  vpc = var.vpc
  es_subnets = var.es_subnets
  event_connector_image_tag = var.event_connector_image_tag
  trade_executor_image_tag = var.trade_executor_image_tag
  event_connector_instance_count = var.event_connector_instance_count
  trade_executor_instance_count = var.trade_executor_instance_count
  incoming_bets_shard_count = var.incoming_bets_shard_count
  outgoing_events_shard_count = var.outgoing_events_shard_count
  outgoing_bets_shard_count = var.outgoing_bets_shard_count
}
