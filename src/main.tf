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

data "aws_secretsmanager_secret_version" "creds" {
  secret_id = "db-creds"
}

locals {
  db_creds = jsondecode(
    data.aws_secretsmanager_secret_version.creds.secret_string
  )
}

// region: rds

resource "aws_security_group" "rds_sg" {
  name        = "tcp-ip-whitelist"
  description = "RDS tcp ip whitelist"

  ingress {
    description = "TCP/IP for RDS with whitelisting"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.whitelisted_ips
  }

  ingress {
    description = "All inbound from sg"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  allocated_storage      = 5
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.17"
  instance_class         = "db.t2.micro"
  name                   = "BexhBackendDbMain"
  username               = local.db_creds.username
  password               = local.db_creds.password
  parameter_group_name   = "default.mysql8.0"
  publicly_accessible    = true
  skip_final_snapshot    = true
  vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
}

resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.this] #wait for the db to be ready
  triggers = {
    file_sha = "${sha1(file("file.sql"))}"
  }
  provisioner "local-exec" {
    command = "echo test"
  }
}

// region: api gateway + lambda

resource "aws_api_gateway_rest_api" "this" {
  name        = "BexhApi"
  description = "API Gateway for all things bexh"
}

resource "aws_api_gateway_resource" "bexh" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "bexh"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.bexh.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.bexh.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.bexh_api_proxy_post.invoke_arn
}

resource "aws_lambda_function" "bexh_api_proxy_post" {
  s3_bucket         = "bexh-lambda-deploy-develop-189266647936"
  s3_key            = "bexh-api-aws-lambda.zip"
  s3_object_version = var.bexh_api_lambda_s3_version
  function_name     = "bexh-api-proxy-post"
  role              = aws_iam_role.bexh_api_proxy_post_lambda_role.arn
  handler           = "main.src.service.handler"
  runtime           = "python3.8"
  timeout           = 60
  environment {
    variables = {
      ENV_NAME            = var.env_name
      LOG_LEVEL           = var.log_level
      TOKEN_TABLE_NAME    = aws_dynamodb_table.this.name
      MYSQL_HOST_URL      = aws_db_instance.this.address
      MYSQL_DATABASE_NAME = aws_db_instance.this.name
    }
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_lambda_function.bexh_api_proxy_post,
    aws_api_gateway_integration.integration
  ]

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "test"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "bexh_api_proxy_post_lambda_role" {
  name = "bexh-api-proxy-post-lambda-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "terraform_lambda_policy" {
  role       = aws_iam_role.bexh_api_proxy_post_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bexh_api_proxy_post.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

// region: DynamoDb

resource "aws_dynamodb_table" "this" {
  name         = "Tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Uid"

  attribute {
    name = "Uid"
    type = "N"
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }
}

// region: ES

resource "aws_security_group" "es_sg" {
  name        = "${var.es_domain}-sg"
  description = "Allow inbound traffic to ElasticSearch from VPC CIDR"
  vpc_id      = var.vpc

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      var.vpc_cidr
    ]
  }

  ingress {
    description = "whitelist IPs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.whitelisted_ips
  }

  ingress {
    description = "All inbound from sg"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_service_linked_role" "es" {
  aws_service_name = "es.amazonaws.com"
  description      = "Allows Amazon ES to manage AWS resources for a domain on your behalf."
}

resource "aws_elasticsearch_domain" "es" {
  domain_name           = var.es_domain
  elasticsearch_version = "6.8"

  cluster_config {
    instance_type = "t2.medium.elasticsearch"
  }

  vpc_options {
    subnet_ids         = var.es_subnets
    security_group_ids = [aws_security_group.es_sg.id]
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = data.aws_iam_policy_document.this.json

  tags = {
    Domain = var.es_domain
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    effect  = "Allow"
    actions = ["es:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = ["arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.es_domain}/*"]
  }
}

// section: Email Integration
resource "aws_lambda_function" "bexh_email" {
  s3_bucket         = "bexh-lambda-deploy-develop-189266647936"
  s3_key            = "bexh-email-aws-lambda.zip"
  s3_object_version = var.bexh_email_lambda_s3_version
  function_name     = "bexh-verification-email"
  role              = aws_iam_role.bexh_emailer_lambda_role.arn
  handler           = "main.src.app.verification_email.service.handler"
  runtime           = "python3.8"
  timeout           = 600
  environment {
    variables = {
      ENV_NAME            = var.env_name
      LOG_LEVEL           = var.log_level
      TWILIO_API_KEY      = var.twilio_api_key
    }
  }
}

resource "aws_sns_topic" "email_topic" {
  name = "bexh-email-handler-topic"
}

resource "aws_sns_topic" "this" {
  arn = aws_sns_topic.email_topic.arn

  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "__default_policy_ID"

  statement {
    actions = [
      "SNS:Subscribe",
      # "SNS:SetTopicAttributes",
      # "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      # "SNS:ListSubscriptionsByTopic",
      # "SNS:GetTopicAttributes",
      # "SNS:DeleteTopic",
      # "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.email_topic.arn,
    ]

    sid = "__default_statement_ID"
  }
}

resource "aws_lambda_permission" "email_invoke_function" {
  statement_id  = "AllowSnsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bexh_email.function_name
  principal     = "sns.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = aws_sns_topic.email_topic.arn
}

resource "aws_iam_role" "bexh_emailer_lambda_role" {
  name = "bexh-emailer-lambda-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "emailer_basic_policy" {
  role       = aws_iam_role.bexh_emailer_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
