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

resource "aws_rds_cluster" "this" {
  engine_mode                     = "serverless"
  engine                          = "aurora-mysql"
  engine_version                  = "5.7.mysql_aurora.2.07.1"
  cluster_identifier              = "bexh-ods-cluster-${var.env_name}-${var.account_id}"
  database_name                   = "BexhOdsDb"
  master_username                 = local.db_creds.username
  master_password                 = local.db_creds.password
  db_cluster_parameter_group_name = "default.aurora-mysql5.7"
  vpc_security_group_ids          = ["${aws_security_group.rds_sg.id}"]
  enable_http_endpoint            = true
  final_snapshot_identifier       = "bexh-ods-cluster-snapshot-${var.env_name}-${var.account_id}"

  scaling_configuration {
    auto_pause               = true
    max_capacity             = 2
    seconds_until_auto_pause = 300
  }
}

# resource "null_resource" "setup_db" {
#   depends_on = [aws_rds_cluster.this] #wait for the db to be ready
#   triggers = {
#     file_sha = "${sha1(file("file.sql"))}"
#   }
#   provisioner "local-exec" {
#     command = "echo test"
#   }
# }

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
  s3_bucket         = "bexh-lambda-deploy-dev-189266647936"
  s3_key            = "bexh-api-aws-lambda.zip"
  s3_object_version = var.bexh_api_lambda_s3_version
  function_name     = "bexh-api-proxy-post"
  role              = aws_iam_role.bexh_api_proxy_post_lambda_role.arn
  handler           = "main.src.service.handler"
  runtime           = "python3.8"
  timeout           = 60
  environment {
    variables = {
      ENV_NAME                          = var.env_name
      LOG_LEVEL                         = var.log_level
      TOKEN_TABLE_NAME                  = aws_dynamodb_table.this.name
      MYSQL_HOST_URL                    = aws_rds_cluster.this.endpoint
      MYSQL_DATABASE_NAME               = aws_rds_cluster.this.database_name
      BET_STATUS_CHANGE_EMAIL_SNS_TOPIC = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
      VERIFICATION_EMAIL_SNS_TOPIC      = module.bexh_verification_email_sns_lambda.aws_sns_topic.arn
      EXCHANGE_BET_KINESIS_STREAM       = var.make_bets_kinesis_stream_name
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
    subnet_ids         = [var.es_subnets[0]]
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
    resources = ["arn:aws:es:${data.aws_region.current.name}:${var.account_id}:domain/${var.es_domain}/*"]
  }
}

module "bexh_verification_email_sns_lambda" {
  source = "../bexh_sns_lambda_integration"

  function_name     = "verification-email"
  s3_key            = "bexh-email-aws-lambda.zip"
  s3_object_version = var.bexh_email_lambda_s3_version
  env_name          = var.env_name
  account_id        = var.account_id
  handler           = "main.src.app.verification_email.service.handler"
  timeout           = 900
  env_vars = {
    ENV_NAME       = var.env_name
    LOG_LEVEL      = var.log_level
    TWILIO_API_KEY = var.twilio_api_key
    BASE_URL       = var.base_url
    BEXH_EMAIL     = var.bexh_email
  }

  sns_topic_name = "verification-email"
}

module "bexh_bet_status_change_sns_lambda" {
  source = "../bexh_sns_lambda_integration"

  function_name     = "bet-status-change-email"
  s3_key            = "bexh-email-aws-lambda.zip"
  s3_object_version = var.bexh_email_lambda_s3_version
  env_name          = var.env_name
  account_id        = data.aws_caller_identity.current.account_id
  handler           = "main.src.app.bet_status_change_email.service.handler"
  timeout           = 900
  env_vars = {
    ENV_NAME       = var.env_name
    LOG_LEVEL      = var.log_level
    TWILIO_API_KEY = var.twilio_api_key
    BASE_URL       = var.base_url
    BEXH_EMAIL     = var.bexh_email
  }

  sns_topic_name = "bet-status-change-email"
}

// section: ECS Fargate Configuration

resource "aws_security_group" "ecs_sg" {
  name        = "bexh-connector-sg-${var.env_name}-${var.account_id}"
  description = "Connector ecs sg"

  ingress {
    description = "All inbound from sg"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # TODO: replace this with privatelink https://aws.amazon.com/blogs/compute/setting-up-aws-privatelink-for-amazon-ecs-and-amazon-ecr/
  ingress {
    description = "Http inbound for ecr"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "bexh-cluster-${var.env_name}-${var.account_id}"
}

// section: bexh app event connector

resource "aws_dynamodb_table" "event_connector_kcl_state_manager" {
  name         = "bexh-app-event-connector-kcl-st-mgmt-${var.env_name}-${var.account_id}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shard"

  attribute {
    name = "shard"
    type = "S"
  }
}

module "bexh_app_event_connector_service" {
  source = "../bexh_ecs_service"

  name            = "event-connector"
  cluster_id      = aws_ecs_cluster.this.id
  env_name        = var.env_name
  account_id      = var.account_id
  vpc             = var.vpc
  region          = var.region
  image           = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/bexh-connector-aws-ecs:${var.connector_image_tag}"
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  log_level       = var.log_level
  subnets         = var.es_subnets
  env_vars = [
    {
      name  = "LOG_LEVEL"
      value = var.log_level
    },
    {
      name  = "ENV_NAME"
      value = var.env_name
    },
    {
      name  = "MODULE"
      value = "src.app.event_connector.invoke"
    },
    {
      name  = "APP_NAME"
      value = "event-connector"
    },
    {
      name  = "KINESIS_SOURCE_STREAM_NAME"
      value = "bexh-exch-events-out-${var.env_name}-${var.account_id}"
    },
    {
      name  = "KCL_STATE_MANAGER_TABLE_NAME"
      value = aws_dynamodb_table.event_connector_kcl_state_manager.name
    },
    {
      name  = "MYSQL_HOST_URL"
      value = aws_rds_cluster.this.endpoint
    },
    {
      name  = "MYSQL_DATABASE_NAME"
      value = aws_rds_cluster.this.database_name
    },
    {
      name  = "MYSQL_DB_USERNAME"
      value = local.db_creds.username
    },
    {
      name  = "MYSQL_DB_PASSWORD"
      value = local.db_creds.password
    },
    {
      name  = "ES_HOST"
      value = aws_elasticsearch_domain.es.endpoint
    },
    {
      name  = "ES_PORT"
      value = "9200"
    },
    {
      name  = "BET_STATUS_CHANGE_EMAIL_SNS_TOPIC_ARN"
      value = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
    }
  ]
  instance_count = var.connector_instance_count
  ecs_task_definition_policy = jsonencode({
    "Version" = "2012-10-17"
    "Statement" = [
      {
        "Effect" = "Allow"
        "Action" = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
        ]
        "Resource" = "arn:aws:kinesis:${var.region}:${var.account_id}:stream/bexh-*"
      },
      {
        "Effect" = "Allow",
        "Action" = "sns:Publish",
        "Resource" = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
      },
      {
        "Effect" = "Allow",
        "Action" = [
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        "Resource" = aws_dynamodb_table.event_connector_kcl_state_manager.arn
      }
    ]
  })
}


// section: bexh app bet connector

resource "aws_dynamodb_table" "bet_connector_kcl_state_manager" {
  name         = "bexh-app-bet-connector-kcl-st-mgmt-${var.env_name}-${var.account_id}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shard"

  attribute {
    name = "shard"
    type = "S"
  }
}

module "bexh_app_bet_connector_service" {
  source = "../bexh_ecs_service"

  name            = "bet-connector"
  cluster_id      = aws_ecs_cluster.this.id
  env_name        = var.env_name
  account_id      = var.account_id
  vpc             = var.vpc
  region          = var.region
  image           = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/bexh-connector-aws-ecs:${var.connector_image_tag}"
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  log_level       = var.log_level
  subnets         = var.es_subnets
  env_vars = [
    {
      name  = "LOG_LEVEL"
      value = var.log_level
    },
    {
      name  = "ENV_NAME"
      value = var.env_name
    },
    {
      name  = "MODULE"
      value = "src.app.bet_connector.invoke"
    },
    {
      name  = "APP_NAME"
      value = "bet-connector"
    },
    {
      name  = "KINESIS_SOURCE_STREAM_NAME"
      value = "bexh-exch-bets-out-${var.env_name}-${var.account_id}"
    },
    {
      name  = "KCL_STATE_MANAGER_TABLE_NAME"
      value = aws_dynamodb_table.bet_connector_kcl_state_manager.name
    },
    {
      name  = "MYSQL_HOST_URL"
      value = aws_rds_cluster.this.endpoint
    },
    {
      name  = "MYSQL_DATABASE_NAME"
      value = aws_rds_cluster.this.database_name
    },
    {
      name  = "MYSQL_DB_USERNAME"
      value = local.db_creds.username
    },
    {
      name  = "MYSQL_DB_PASSWORD"
      value = local.db_creds.password
    },
    {
      name  = "ES_HOST"
      value = aws_elasticsearch_domain.es.endpoint
    },
    {
      name  = "ES_PORT"
      value = "9200"
    },
    {
      name  = "BET_STATUS_CHANGE_EMAIL_SNS_TOPIC_ARN"
      value = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
    }
  ]
  instance_count = var.connector_instance_count
  ecs_task_definition_policy = jsonencode({
    "Version" = "2012-10-17"
    "Statement" = [
      {
        "Effect" = "Allow"
        "Action" = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator"
        ]
        "Resource" = "arn:aws:kinesis:${var.region}:${var.account_id}:stream/bexh-*"
      },
      {
        "Effect" = "Allow"
        "Action" = [
          "sns:Publish"
        ]
        "Resource" = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
      },
      {
        "Effect" = "Allow"
        "Action" = [
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        "Resource" = aws_dynamodb_table.bet_connector_kcl_state_manager.arn
      }
    ]
  })
}


// section: bexh app aggregated bet info connector

resource "aws_dynamodb_table" "ag_bet_info_connector_kcl_state_manager" {
  name         = "bexh-app-ag-bet-info-connector-kcl-st-mgmt-${var.env_name}-${var.account_id}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shard"

  attribute {
    name = "shard"
    type = "S"
  }
}

module "bexh_app_ag_bet_info_connector_service" {
  source = "../bexh_ecs_service"

  name            = "ag-bet-info-connector"
  cluster_id      = aws_ecs_cluster.this.id
  env_name        = var.env_name
  account_id      = var.account_id
  vpc             = var.vpc
  region          = var.region
  image           = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/bexh-connector-aws-ecs:${var.connector_image_tag}"
  security_groups = ["${aws_security_group.ecs_sg.id}"]
  log_level       = var.log_level
  subnets         = var.es_subnets
  env_vars        = [
    {
      name = "LOG_LEVEL"
      value = var.log_level
    },
    {
      name = "ENV_NAME"
      value = var.env_name
    },
    {
      name = "MODULE"
      value = "src.app.aggregated_bet_info_connector.invoke"
    },
    {
      name = "APP_NAME"
      value = "ag-bet-info-connector"
    },
    {
      name = "KINESIS_SOURCE_STREAM_NAME"
      value = "bexh-exch-bets-out-${var.env_name}-${var.account_id}"
    },
    {
      name = "KCL_STATE_MANAGER_TABLE_NAME"
      value = aws_dynamodb_table.ag_bet_info_connector_kcl_state_manager.name
    },
    {
      name = "MYSQL_HOST_URL"
      value = aws_rds_cluster.this.endpoint
    },
    {
      name = "MYSQL_DATABASE_NAME"
      value = aws_rds_cluster.this.database_name
    },
    {
      name = "MYSQL_DB_USERNAME"
      value = local.db_creds.username
    },
    {
      name = "MYSQL_DB_PASSWORD"
      value = local.db_creds.password
    },
    {
      name = "ES_HOST"
      value = aws_elasticsearch_domain.es.endpoint
    },
    {
      name = "ES_PORT"
      value = "9200"
    },
    {
      name = "BET_STATUS_CHANGE_EMAIL_SNS_TOPIC_ARN"
      value = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
    }
  ]
  instance_count  = var.connector_instance_count
  ecs_task_definition_policy = jsonencode({
    "Version" = "2012-10-17"
    "Statement" = [
      {
        "Effect" = "Allow"
        "Action" = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator"
        ]
        "Resource" = "arn:aws:kinesis:${var.region}:${var.account_id}:stream/bexh-*"
      },
      {
        "Effect" = "Allow"
        "Action" = [
          "sns:Publish"
        ]
        "Resource" = module.bexh_bet_status_change_sns_lambda.aws_sns_topic.arn
      },
      {
        "Effect" = "Allow"
        "Action" = [
          "dynamodb:CreateTable",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        "Resource" = aws_dynamodb_table.ag_bet_info_connector_kcl_state_manager.arn
      }
    ]
  })
}

// section: bet aggregator kinesis analytics app

resource "aws_cloudwatch_log_group" "this" {
  name = "bexh-app-${var.env_name}-${var.account_id}"
}

resource "aws_cloudwatch_log_stream" "this" {
  name           = "bexh-app-agg-bets-${var.env_name}-${var.account_id}"
  log_group_name = aws_cloudwatch_log_group.this.name
}

resource "aws_kinesis_stream" "bexh_app_agg_bets" {
  name             = "bexh-app-agg-bets-${var.env_name}-${var.account_id}"
  shard_count      = 1
}

resource "aws_iam_role" "bexh_kinesis_analytics_execution_role" {
  name = "bexh-app-kinesis-analytics-execution-role"

  inline_policy {
    name = "bexh-app-kinesis-analytics-kinesis-access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "kinesis:DescribeStream",
            "kinesis:GetShardIterator",
            "kinesis:GetRecords",
            "kinesis:ListShards"
          ],
          Effect   = "Allow",
          Resource = var.bets_kinesis_stream_arn
        },
        {
          Action = [
            "kinesis:DescribeStream",
            "kinesis:PutRecord",
            "kinesis:PutRecords"
          ],
          Effect = "Allow",
          Resource = aws_kinesis_stream.bexh_app_agg_bets.arn
        }
      ]
    })
  }

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "kinesisanalytics.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_kinesis_analytics_application" "this" {
  name                   = "bexh-app-bet-aggregator-${var.env_name}-${var.account_id}"
  start_application = true
  code = <<EOF
        CREATE OR REPLACE STREAM "AGG_BETS" (
                                          "event_id" INTEGER, 
                                          "odds"   DOUBLE);
        -- CREATE OR REPLACE PUMP to insert into output
        CREATE OR REPLACE PUMP "STREAM_PUMP" AS 
          INSERT INTO "AGG_BETS" 
            SELECT STREAM "event_id",
                          AVG("odds") AS odds
            FROM    "BEXH_BETS_001"
            GROUP BY "event_id", 
                    STEP("BEXH_BETS_001".ROWTIME BY INTERVAL '5' MINUTE);
        EOF
  inputs {
    name_prefix = "BEXH_BETS"

    schema {
      record_columns {
        name     = "event_id"
        sql_type = "INTEGER"
        mapping  = "$.event_id"
      }
      record_columns {
        name     = "sport"
        sql_type = "VARCHAR(8)"
        mapping  = "$.sport"
      }
      record_columns {
        name     = "bet_id"
        sql_type = "INTEGER"
        mapping  = "$.bets[0:].bet_id"
      }
      record_columns {
        name     = "brokerage_id"
        sql_type = "INTEGER"
        mapping  = "$.bets[0:].brokerage_id"
      }
      record_columns {
        name     = "user_id"
        sql_type = "VARCHAR(64)"
        mapping  = "$.bets[0:].user_id"
      }
      record_columns {
        name     = "amount"
        sql_type = "INTEGER"
        mapping  = "$.bets[0:].amount"
      }
      record_columns {
        name     = "status"
        sql_type = "VARCHAR(8)"
        mapping  = "$.bets[0:].status"
      }
      record_columns {
        name     = "execution_time"
        sql_type = "VARCHAR(32)"
        mapping  = "$.execution_time"
      }
      record_columns {
        name     = "odds"
        sql_type = "INTEGER"
        mapping  = "$.odds"
      }

      record_encoding = "UTF-8"

      record_format {
        # record_format_type = "JSON"

        mapping_parameters {
          json {
            record_row_path = "$"
          }
        }
      }
    }

    starting_position_configuration {
      starting_position = "TRIM_HORIZON"
    }

    kinesis_stream {
      resource_arn = var.bets_kinesis_stream_arn
      role_arn = aws_iam_role.bexh_kinesis_analytics_execution_role.arn
    }

    parallelism {
      count = 1
    }
  }

  outputs {
    name = "AGG_BETS"

    schema {
      record_format_type = "JSON"
    }

    kinesis_stream {
      resource_arn = aws_kinesis_stream.bexh_app_agg_bets.arn
      role_arn = aws_iam_role.bexh_kinesis_analytics_execution_role.arn
    }

  }

  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.this.arn
    role_arn = aws_iam_role.bexh_kinesis_analytics_execution_role.arn
  }
}
