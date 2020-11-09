terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "bexh"

    workspaces {
      name = "bexh-backend-aws-terraform"
    }
  }
}

module "bexh_app" {
  source = "./modules/bexh_app"

  whitelisted_ips = var.whitelisted_ips
  env_name = var.env_name
  log_level = var.log_level
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
}
